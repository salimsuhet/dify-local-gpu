#!/usr/bin/env bash
# ============================================================================
# switch-model.sh — troca um dos modelos do stack: baixa o novo modelo na
# instância Ollama certa e atualiza o .env.
#
# Uso:
#   ./scripts/switch-model.sh code  qwen2.5-coder:1.5b-instruct-q4_K_M
#   ./scripts/switch-model.sh chat  mistral:7b-instruct-q4_K_M
#   ./scripts/switch-model.sh embed bge-m3
#
# Depois, cadastre o novo modelo no Dify (docs/dify-setup.md). Trocar o
# modelo de embedding exige reindexar as Bases de Conhecimento.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROLE="${1:-}"
MODEL="${2:-}"
case "$ROLE" in
  code)  CONTAINER=ollama-gpu0; ENV_KEY=GPU0_CODE_MODEL ;;
  chat)  CONTAINER=ollama-gpu1; ENV_KEY=GPU1_CHAT_MODEL ;;
  embed) CONTAINER=ollama-gpu1; ENV_KEY=GPU1_EMBED_MODEL ;;
  *) ROLE="" ;;
esac
if [ -z "$ROLE" ] || [ -z "$MODEL" ]; then
  echo "Uso: $0 <code|chat|embed> <modelo>"
  echo "Exemplo: $0 code qwen2.5-coder:1.5b-instruct-q4_K_M"
  exit 1
fi

echo "==> Baixando '${MODEL}' em ${CONTAINER}..."
docker exec "$CONTAINER" ollama pull "$MODEL"

echo "==> Atualizando .env (${ENV_KEY}=${MODEL})..."
if grep -q "^${ENV_KEY}=" .env; then
  sed -i.bak "s|^${ENV_KEY}=.*|${ENV_KEY}=${MODEL}|" .env && rm -f .env.bak
else
  echo "${ENV_KEY}=${MODEL}" >> .env
fi

echo "==> Pronto. Confira a licença do modelo em docs/licencas.md."
echo "    Para liberar disco: docker exec ${CONTAINER} ollama rm <modelo-antigo>"
