# 🚀 Migração Automática de NGINX Ingress → Gateway API + Istio

Este repositório contém um conjunto completo de scripts para:

* Extrair todos os **Ingress NGINX** do cluster
* Gerar automaticamente **Gateway API + HTTPRoute + EnvoyFilter**
* Converter **snippets NGINX** automaticamente para **Lua/Envoy**
* Criar manifests em arquivos YAML organizados
* Validar todos os manifestos antes de aplicar
* Gerar relatório detalhado
* **Sem alterar produção** — tudo é feito offline/local

O objetivo é tornar a migração para Istio + Gateway API *automática, segura e repetível*, sem alterar nenhum recurso do cluster.

---

# 📦 Conteúdo do repositório

```
.
├── generate-istio-gateway-from-ingress.sh   # Script principal
├── validate-gateway-yaml.sh                 # Validação dos manifests
├── convert-snippet-nginx-to-lua.sh          # Conversão isolada de snippets
├── generated/                               # Saída automática dos manifests
│   ├── gateway-<ns>-<ingress>.yaml
│   ├── snippet-gateway-<ns>-<ingress>.yaml
│   └── report.txt
└── README.md
```

---

# 🧠 Como funciona?

## 1. Coletar todos os ingress

O script usa:

```
kubectl get ingress --all-namespaces -o json
```

Isso permite rodar em clusters:

* com RBAC somente de leitura
* em produção
* em staging

Sem qualquer modificação dos recursos existentes.

---

## 2. Classificação automática

Cada ingress é classificado como:

### ✔️ **gateway-* (sem snippet)**

Ingress sem `nginx.ingress.kubernetes.io/*snippet*`.

### ✔️ **snippet-gateway-* (com snippet)**

Ingress contendo:

* `configuration-snippet`
* `server-snippet`
* `location-snippet`
* `proxy-snippet`
* ou qualquer snippet nginx customizado

---

## 3. Geração de Gateway + HTTPRoute

Scripts produzem automaticamente:

* **Gateway**
* **HTTPRoute**
* **TLS**
* **BackendRefs**
* **PathPrefix matches**
* **hostnames**
* **múltiplos serviços por regra**

---

## 4. Conversão automática de snippets NGINX → EnvoyFilter (Lua)

Regras reconhecidas automaticamente:

| Snippet NGINX              | Comportamento gerado              |
| -------------------------- | --------------------------------- |
| `deny all;`                | Bloqueio 403 em Lua               |
| `return 301 https://foo;`  | Redirecionamento Lua              |
| `add_header X-Foo Bar;`    | Header adicional                  |
| `rewrite ^/foo/(.*)$ /$1;` | path rewrite                      |
| `if ($host ~ regex)`       | condicional Lua                   |
| `proxy_set_header ...`     | manipulação de header             |
| outros                     | TODO + snippet original comentado |

Os filtros são adicionados via:

```
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
```

---

## 5. Relatório automático

Em `generated/report.txt`, contendo:

* todos os ingress processados
* arquivos gerados
* classificação snippet/non-snippet

---

# 📥 Como usar

## 1. Clonar o repo

```bash
git clone <seu-repo>
cd <seu-repo>
```

## 2. Garantir requisitos

### Dependências:

* bash
* kubectl
* jq
* yamllint
* kubeval

No Debian/Ubuntu:

```bash
sudo apt install jq yamllint
```

Instalar kubeval:

```bash
wget https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
tar xf kubeval-linux-amd64.tar.gz
sudo mv kubeval /usr/local/bin/
```

---

## 3. Gerar todos os manifests

```bash
./generate-istio-gateway-from-ingress.sh
```

Saída será criada em `./generated/`.

---

## 4. Validar todos os arquivos YAML

```bash
./validate-gateway-yaml.sh
```

Verificações:

1. **yamllint**
2. **kubeval**
3. **kubectl apply --dry-run=client**

---

## 5. Converter snippets em arquivo separado

```bash
./convert-snippet-nginx-to-lua.sh snippet.txt
```

---

# 📁 Estrutura de saída

Exemplo de arquivos criados:

```
generated/
├── gateway-prod-orders.yaml
├── snippet-gateway-prod-auth.yaml
├── snippet-gateway-prod-billing.yaml
├── gateway-dev-api.yaml
└── report.txt
```

---

# 🧪 Ambiente seguro

Os scripts:

* **NÃO aplicam nada ao cluster**
* Geração totalmente offline
* Compatível com pipelines CI/CD
* Ideal para migração progressiva

---

# 🛡️ Segurança

* Nenhum recurso existente é modificado
* O script funciona até com permissões limitadas
* Todos os recursos gerados são isolados

---

# 🧩 Roadmap futuro

* Conversão automática de regex complexas nginx → Envoy
* Templates Helm para deploy progressivo
* Migração canary com `weight` no HTTPRoute
* Suporte completo a `auth_request` → ExtAuthz

---

# 🤝 Contribuições

Pull requests são bem-vindos.
Para discussões, abra uma issue no repositório.

---

# 📄 Licença

MIT License

---
