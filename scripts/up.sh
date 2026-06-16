#!/usr/bin/env bash
# ============================================================================
# up.sh — sobe Ollama (gpu0/gpu1) + Qdrant escolhendo o overlay de GPU
# correto (Linux ou Windows) conforme HOST_OS no .env.
#
# Uso:
#   ./scripts/up.sh            (sobe em modo detached)
#   ./scripts/up.sh --build    (qualquer argumento extra é passado ao compose)
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

HOST_OS="${HOST_OS:-linux}"

case "$HOST_OS" in
  linux)
    GPU_OVERLAY="compose/gpu.linux.yml"
    ;;
  windows)
    GPU_OVERLAY="compose/gpu.windows.yml"
    ;;
  *)
    echo "ERRO: HOST_OS='${HOST_OS}' inválido no .env. Use 'linux' ou 'windows'."
    exit 1
    ;;
esac

echo "==> HOST_OS=${HOST_OS} -> usando overlay de GPU: ${GPU_OVERLAY}"

docker compose \
  --env-file .env \
  -f docker-compose.base.yml \
  -f "$GPU_OVERLAY" \
  up -d "$@"

echo "==> Stack Ollama/Qdrant no ar. Rode ./scripts/check-gpu-affinity.sh para confirmar a alocação de GPU."
