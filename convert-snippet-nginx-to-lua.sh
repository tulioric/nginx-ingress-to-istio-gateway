#!/bin/bash
set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Uso: $0 arquivo_snippet.txt"
    exit 1
fi

SNIPPET=$(cat "$1")

convert() {
    local snippet="$1"

    if echo "$snippet" | grep -qi "deny all"; then
cat <<EOF
function envoy_on_request(request_handle)
  request_handle:respond({[":status"]="403"},"Forbidden")
end
EOF
        return
    fi

    if echo "$snippet" | grep -qi "return 301"; then
        target=$(echo "$snippet" | sed -n 's/.*return 301\s*\(.*\);/\1/p')
cat <<EOF
function envoy_on_request(request_handle)
  local path = request_handle:headers():get(":path")
  request_handle:respond(
    { [":status"]="301", ["location"]="${target}"..path },
    ""
  )
end
EOF
        return
    fi

    if echo "$snippet" | grep -qi "add_header"; then
        header=$(echo "$snippet" | awk '{print $2}')
        value=$(echo "$snippet" | awk '{print $3}' | sed 's/;//')
cat <<EOF
function envoy_on_request(request_handle)
  request_handle:headers():add("${header}", "${value}")
end
EOF
        return
    fi

    # fallback
cat <<EOF
-- TODO: Conversão manual necessária
-- Snippet original:
-- ${snippet}
function envoy_on_request(request_handle)
end
EOF
}

convert "$SNIPPET"
