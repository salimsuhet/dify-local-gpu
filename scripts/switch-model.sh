#!/usr/bin/env bash
# ============================================================================
# switch-model.sh — troca o modelo carregado em uma GPU específica,
# sem precisar editar docker-compose ou derrubar o stack inteiro.
#
# Uso:
#   ./scripts/switch-model.sh gpu0 llama3.1:8b-instruct-q4_K_M
#   ./scripts/switch-model.sh gpu1 bge-m3
#
# Isso também atualiza o .env para que o novo modelo persista após restart.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-}"
MODEL="${2:-}"

if [ -z "$TARGET" ] || [ -z "$MODEL" ]; then
  echo "Uso: $0 <gpu0|gpu1> <nome-do-modelo>"
  echo "Exemplo: $0 gpu0 llama3.1:8b-instruct-q4_K_M"
  exit 1
fi

# shellcheck disable=SC1091
source .env

case "$TARGET" in
  gpu0)
    URL="http://localhost:${OLLAMA_GPU0_PORT:-11434}"
    ENV_KEY="GPU0_CHAT_MODEL"
    ;;
  gpu1)
    URL="http://localhost:${OLLAMA_GPU1_PORT:-11435}"
    ENV_KEY="GPU1_EMBED_MODEL"
    ;;
  *)
    echo "ERRO: target deve ser 'gpu0' ou 'gpu1'."
    exit 1
    ;;
esac

echo "==> Baixando '${MODEL}' em ${TARGET} (${URL})..."
curl -s "${URL}/api/pull" -d "{\"name\": \"${MODEL}\"}" | tail -n 1
echo ""

echo "==> Atualizando .env (${ENV_KEY}=${MODEL})..."
if grep -q "^${ENV_KEY}=" .env; then
  sed -i.bak "s/^${ENV_KEY}=.*/${ENV_KEY}=${MODEL}/" .env
else
  echo "${ENV_KEY}=${MODEL}" >> .env
fi

echo "==> Pronto. O modelo '${MODEL}' já está disponível em ${TARGET}."
echo "    Modelos antigos continuam baixados em disco; rode 'ollama list' dentro"
echo "    do container se quiser remover os que não usa mais, para liberar espaço:"
echo "    docker exec -it ollama-${TARGET} ollama rm <modelo-antigo>"
