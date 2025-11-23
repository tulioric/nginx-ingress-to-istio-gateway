#!/bin/bash
set -euo pipefail

OUTPUT_DIR="./generated"
REPORT="$OUTPUT_DIR/report.txt"

mkdir -p "${OUTPUT_DIR}"
echo "" > "$REPORT"

echo "🔍 Coletando todos os ingress do cluster..."
INGRESSES=$(kubectl get ingress --all-namespaces -o json)

COUNT=$(echo "$INGRESSES" | jq '.items | length')
echo "📦 Total de ingress encontrados: $COUNT"
echo

# -------------------------------------------------------------------
# Função: converter snippet NGINX → Lua Envoy automaticamente
# -------------------------------------------------------------------
convert_snippet_to_lua() {
    local snippet="$1"

    # Deny all
    if echo "$snippet" | grep -qi "deny all"; then
cat <<'EOF'
function envoy_on_request(request_handle)
  request_handle:respond({[":status"] = "403"}, "Forbidden")
end
EOF
        return
    fi

    # Return 301 redirect
    if echo "$snippet" | grep -qi "return 301"; then
        local target=$(echo "$snippet" | sed -n 's/.*return 301\s*\(.*\);/\1/p')
cat <<EOF
function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")
  request_handle:respond(
    { [":status"] = "301", ["location"] = "${target}" .. path},
    ""
  )
end
EOF
        return
    fi

    # add_header
    if echo "$snippet" | grep -qi "add_header"; then
        local header=$(echo "$snippet" | awk '{print $2}')
        local value=$(echo "$snippet" | awk '{print $3}' | sed 's/;//')
cat <<EOF
function envoy_on_request(request_handle)
  request_handle:headers():add("${header}", "${value}")
end
EOF
        return
    fi

    # rewrite ^/foo/(.*)$ /$1
    if echo "$snippet" | grep -qi "rewrite"; then
        local regex=$(echo "$snippet" | sed -n 's/.*rewrite \^\(.*\) .*/\1/p')
        local replacement=$(echo "$snippet" | sed -n 's/.*rewrite .* \(.*\);/\1/p')
cat <<EOF
function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")
  local newpath = string.gsub(path, "${regex}", "${replacement}")
  request_handle:headers():replace(":path", newpath)
end
EOF
        return
    fi

    # Se chegou aqui → não reconhecemos (então geramos TODO)
cat <<EOF
-- TODO: Conversão automática não implementada para este snippet.
-- Snippet original abaixo:
-- ${snippet}
function envoy_on_request(request_handle)
  -- Implementar comportamento manualmente aqui
end
EOF
}

# -------------------------------------------------------------------
# Loop de todos os ingress
# -------------------------------------------------------------------
for row in $(echo "${INGRESSES}" | jq -r '.items | to_entries[] | @base64'); do
    _jq() {
        echo "${row}" | base64 --decode | jq -r "${1}"
    }

    NS=$(_jq '.value.metadata.namespace')
    NAME=$(_jq '.value.metadata.name')
    ANNOTATIONS=$(_jq '.value.metadata.annotations')
    HAS_SNIPPET="false"

    echo "➡️  Processando ingress: ${NS}/${NAME}"

    SNIPPET_RAW=$(echo "$ANNOTATIONS" | jq -r '."nginx.ingress.kubernetes.io/configuration-snippet" // empty')

    if [ "$SNIPPET_RAW" != "" ]; then
        HAS_SNIPPET="true"
    fi

    # Decide nome do arquivo
    if [ "$HAS_SNIPPET" = "true" ]; then
        FILE="${OUTPUT_DIR}/snippet-gateway-${NS}-${NAME}.yaml"
    else
        FILE="${OUTPUT_DIR}/gateway-${NS}-${NAME}.yaml"
    fi

    # Processar básico
    HOSTS=$(_jq '.value.spec.rules[].host // empty')
    TLS=$(_jq '.value.spec.tls // empty')
    RULES_JSON=$(_jq '.value.spec.rules // empty')

    cat > "$FILE" <<EOF
# AUTO-GERADO — NÃO APLICA DIRETAMENTE EM PRODUÇÃO
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${NAME}-gateway
  namespace: ${NS}
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
EOF

    # TLS
    if [ "$TLS" != "null" ]; then
cat >> "$FILE" <<EOF
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
EOF
        SECRETS=$(_jq '.value.spec.tls[].secretName // empty')
        for S in $SECRETS; do
            echo "      - name: $S" >> "$FILE"
        done
    fi

# HTTPRoute
cat >> "$FILE" <<EOF
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${NAME}-httproute
  namespace: ${NS}
spec:
  parentRefs:
    - name: ${NAME}-gateway
  hostnames:
EOF

    for H in $HOSTS; do
        echo "    - \"$H\"" >> "$FILE"
    done

    echo "  rules:" >> "$FILE"

    RULE_COUNT=$(echo "$RULES_JSON" | jq 'length')

    for i in $(seq 0 $(($RULE_COUNT - 1))); do
        PATHS=$(echo "$RULES_JSON" | jq ".[$i].http.paths")
        PATH_COUNT=$(echo "$PATHS" | jq 'length')

        for p in $(seq 0 $(($PATH_COUNT - 1))); do
            PATH=$(echo "$PATHS" | jq -r ".[$p].path")
            BACKEND=$(echo "$PATHS" | jq -r ".[$p].backend.service.name")
            PORT=$(echo "$PATHS" | jq -r ".[$p].backend.service.port.number")

cat >> "$FILE" <<EOF
    - matches:
        - path:
            type: PathPrefix
            value: "$PATH"
      backendRefs:
        - name: $BACKEND
          port: $PORT
EOF
        done
    done

    # Se houver snippet → gerar EnvoyFilter
    if [ "$HAS_SNIPPET" = "true" ]; then
        LUA_CODE=$(convert_snippet_to_lua "$SNIPPET_RAW")

cat >> "$FILE" <<EOF
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: ${NAME}-snippet-filter
  namespace: ${NS}
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
    patch:
      operation: INSERT_FIRST
      value:
        name: envoy.filters.http.lua
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
          inlineCode: |
$(echo "$LUA_CODE" | sed 's/^/            /')
EOF

    fi

    echo "✔️ Gerado: $FILE"
    echo "Ingress: $NS/$NAME → File: $(basename $FILE)" >> "$REPORT"
done

echo "📄 Relatório disponível em $REPORT"
echo "✨ Finalizado!"
