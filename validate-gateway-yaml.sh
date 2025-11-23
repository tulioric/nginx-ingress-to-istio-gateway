#!/bin/bash
set -euo pipefail

DIR="./generated"

echo "🔍 Rodando yamllint..."
yamllint "$DIR"

echo "🔍 Rodando kubeval..."
kubeval "$DIR"/*.yaml --strict

echo "🔍 Validando com kubectl dry-run..."
for f in $DIR/*.yaml; do
    echo "Validando: $f"
    kubectl apply --dry-run=client -f "$f" > /dev/null
done

echo "✨ Todos os arquivos são válidos!"
