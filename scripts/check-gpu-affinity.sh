#!/usr/bin/env bash
# ============================================================================
# check-gpu-affinity.sh — confirma em qual(is) GPU(s) cada container Ollama
# está rodando, e quanto de VRAM cada um está usando.
#
# Em HOST_OS=linux, espera-se isolamento real (cada container em 1 GPU).
# Em HOST_OS=windows, ambos containers têm acesso a todas as GPUs visíveis
# — este script ajuda a ver onde cada modelo de fato acabou carregado.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
[ -f .env ] && source .env

HOST_OS="${HOST_OS:-linux}"

echo "==> HOST_OS=${HOST_OS}"
echo ""
echo "==> Mapeamento de GPUs físicas:"
nvidia-smi -L
echo ""

echo "==> Uso de VRAM por GPU:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv
echo ""

echo "==> Processos com uso de GPU (se o host expor essa métrica):"
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv 2>/dev/null || echo "  (não disponível neste ambiente — comum em WSL2; veja a seção 'VRAM por GPU' acima)"
echo ""

echo "==> Containers Ollama ativos e configuração de GPU:"
for c in ollama-gpu0 ollama-gpu1; do
  if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
    if [ "$HOST_OS" = "linux" ]; then
      gpu=$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep NVIDIA_VISIBLE_DEVICES || echo "NVIDIA_VISIBLE_DEVICES não definida")
      echo "  ${c}: ${gpu}"
    else
      echo "  ${c}: modo windows — todas as GPUs visíveis (sem fixação por container)"
    fi
  else
    echo "  ${c}: container não está rodando"
  fi
done

echo ""
echo "==> Modelos atualmente carregados em VRAM em cada instância:"
echo "--- GPU0 (chat) ---"
curl -s http://localhost:"${OLLAMA_GPU0_PORT:-11434}"/api/ps | python3 -m json.tool 2>/dev/null || echo "  (sem resposta — ollama-gpu0 está no ar?)"
echo "--- GPU1 (embed/rerank) ---"
curl -s http://localhost:"${OLLAMA_GPU1_PORT:-11435}"/api/ps | python3 -m json.tool 2>/dev/null || echo "  (sem resposta — ollama-gpu1 está no ar?)"

if [ "$HOST_OS" = "windows" ]; then
  echo ""
  echo "NOTA: em modo Windows, se 'nvidia-smi --query-gpu' mostrar VRAM"
  echo "concentrada em uma única GPU mesmo com os dois modelos carregados,"
  echo "isso é esperado: o Ollama (não o Docker) decidiu colocar ambos na"
  echo "mesma placa. Veja docs/windows-gpu-notes.md para mitigar."
fi
