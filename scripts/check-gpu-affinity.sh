#!/usr/bin/env bash
# ============================================================================
# check-gpu-affinity.sh — mostra a que GPU cada Ollama está preso, quanta
# VRAM cada placa usa e se algum modelo foi parcialmente para a CPU.
# ============================================================================
set -uo pipefail

echo "==> GPUs físicas:"
nvidia-smi -L
echo ""
echo "==> VRAM por GPU:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
echo ""

for c in ollama-gpu0 ollama-gpu1; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    echo "==> ${c}: não está rodando"
    continue
  fi
  envs=$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(CUDA_VISIBLE_DEVICES|NVIDIA_VISIBLE_DEVICES)=' | paste -sd' ' -)
  echo "==> ${c}: ${envs}"
  gpu=$(docker logs "$c" 2>&1 | grep 'inference compute' | tail -n1 | sed 's/.*msg=//')
  [ -n "$gpu" ] && echo "    GPU detectada pelo Ollama: ${gpu}"
  echo "    Modelos carregados (PROCESSOR deve ser '100% GPU'):"
  docker exec "$c" ollama ps | sed 's/^/      /'
  echo ""
done

echo "Se algum modelo aparecer como 'CPU/GPU', ele não coube na VRAM:"
echo "reduza OLLAMA_GPU*_NUM_CTX no .env e rode ./scripts/up.sh --force-recreate"
