#!/usr/bin/env bash
# ============================================================================
# pull-models.sh — baixa os modelos definidos no .env, cada um na
# instância Ollama certa:
#   GPU0 (ollama-gpu0): GPU0_CODE_MODEL
#   GPU1 (ollama-gpu1): GPU1_CHAT_MODEL, GPU1_EMBED_MODEL
#
# Rode novamente sempre que mudar algum desses modelos no .env.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source .env

wait_for_ollama() {
  echo "    Aguardando $1..."
  for _ in $(seq 1 30); do
    docker exec "$1" ollama list >/dev/null 2>&1 && return 0
    sleep 2
  done
  echo "ERRO: $1 não respondeu a tempo. Veja: docker logs $1"
  exit 1
}

pull_model() {
  local container="$1" model="$2" label="$3"
  if [ -z "$model" ]; then
    echo "    [${label}] nenhum modelo definido, pulando."
    return 0
  fi
  echo "    [${label}] baixando '${model}' em ${container}..."
  docker exec "$container" ollama pull "$model" \
    || { echo "ERRO: falha ao baixar '${model}'. Confira o nome em https://ollama.com/library"; exit 1; }
}

echo "==> GPU0 — modelo de código"
wait_for_ollama ollama-gpu0
pull_model ollama-gpu0 "${GPU0_CODE_MODEL:-}" "código"

echo "==> GPU1 — conversa + embedding"
wait_for_ollama ollama-gpu1
pull_model ollama-gpu1 "${GPU1_CHAT_MODEL:-}" "conversa"
pull_model ollama-gpu1 "${GPU1_EMBED_MODEL:-}" "embedding"

echo "==> Modelos em disco:"
echo "--- ollama-gpu0 ---"; docker exec ollama-gpu0 ollama list
echo "--- ollama-gpu1 ---"; docker exec ollama-gpu1 ollama list
