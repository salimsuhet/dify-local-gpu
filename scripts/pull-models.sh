#!/usr/bin/env bash
# ============================================================================
# pull-models.sh — baixa/atualiza os modelos definidos no .env,
# cada um na instância Ollama correta (GPU0 = chat, GPU1 = embed/rerank).
#
# Rode novamente sempre que mudar GPU0_CHAT_MODEL, GPU1_EMBED_MODEL ou
# GPU1_RERANK_MODEL no .env.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source .env

GPU0_URL="http://localhost:${OLLAMA_GPU0_PORT:-11434}"
GPU1_URL="http://localhost:${OLLAMA_GPU1_PORT:-11435}"

wait_for_ollama() {
  local url="$1"
  local name="$2"
  echo "    Aguardando ${name} responder em ${url}..."
  for _ in $(seq 1 30); do
    if curl -s -o /dev/null "${url}/api/tags"; then
      return 0
    fi
    sleep 2
  done
  echo "ERRO: ${name} não respondeu a tempo em ${url}."
  exit 1
}

pull_model() {
  local url="$1"
  local model="$2"
  local label="$3"
  if [ -z "$model" ]; then
    echo "    [${label}] nenhum modelo definido, pulando."
    return 0
  fi
  echo "    [${label}] baixando '${model}'..."
  curl -s "${url}/api/pull" -d "{\"name\": \"${model}\"}" | tail -n 1
  echo ""
}

echo "==> GPU0 (${GPU0_URL}) — modelo de chat"
wait_for_ollama "$GPU0_URL" "ollama-gpu0"
pull_model "$GPU0_URL" "${GPU0_CHAT_MODEL:-}" "chat"

echo "==> GPU1 (${GPU1_URL}) — embedding + rerank"
wait_for_ollama "$GPU1_URL" "ollama-gpu1"
pull_model "$GPU1_URL" "${GPU1_EMBED_MODEL:-}" "embedding"
pull_model "$GPU1_URL" "${GPU1_RERANK_MODEL:-}" "rerank"

echo "==> Modelos disponíveis em cada GPU:"
echo "--- GPU0 (chat) ---"
curl -s "${GPU0_URL}/api/tags" | python3 -m json.tool 2>/dev/null || true
echo "--- GPU1 (embed/rerank) ---"
curl -s "${GPU1_URL}/api/tags" | python3 -m json.tool 2>/dev/null || true
