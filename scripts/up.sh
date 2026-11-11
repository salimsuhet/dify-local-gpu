#!/usr/bin/env bash
# ============================================================================
# up.sh — sobe os dois Ollama (GPU0 = código, GPU1 = conversa + embedding)
# com o overlay de GPU correspondente ao HOST_OS do .env.
#
# Uso:
#   ./scripts/up.sh
#   ./scripts/up.sh --force-recreate      (argumentos extras vão para o compose)
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "ERRO: arquivo .env não encontrado. Rode primeiro: cp .env.example .env"
  exit 1
fi

# shellcheck disable=SC1091
source .env

case "${HOST_OS:-linux}" in
  linux)   GPU_OVERLAY="compose/gpu.linux.yml" ;;
  windows) GPU_OVERLAY="compose/gpu.windows.yml" ;;
  *) echo "ERRO: HOST_OS='${HOST_OS}' inválido no .env. Use 'linux' ou 'windows'."; exit 1 ;;
esac

echo "==> HOST_OS=${HOST_OS:-linux} -> overlay de GPU: ${GPU_OVERLAY}"
docker compose --env-file .env -f docker-compose.base.yml -f "$GPU_OVERLAY" up -d "$@"
