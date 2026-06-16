#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — setup completo do stack Dify + Ollama (2 GPUs) + Qdrant
# Funciona em Linux nativo e em Windows via WSL2 (rode este script DENTRO
# do WSL2 — é o caminho recomendado; veja docs/windows-gpu-notes.md para
# rodar fora do WSL2 usando os scripts .ps1).
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Verificando pré-requisitos..."

command -v docker >/dev/null 2>&1 || { echo "ERRO: docker não encontrado. Instale o Docker primeiro."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERRO: Docker Compose v2 não encontrado."; exit 1; }
command -v nvidia-smi >/dev/null 2>&1 || { echo "ERRO: nvidia-smi não encontrado. Verifique o driver NVIDIA."; exit 1; }

echo "==> GPUs detectadas:"
nvidia-smi -L

echo "==> Preparando .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "    Criado .env a partir do template."
  echo "    IMPORTANTE: confirme o valor de HOST_OS (linux ou windows) antes de continuar."
else
  echo "    .env já existe, mantendo o atual."
fi

# shellcheck disable=SC1091
source .env

HOST_OS="${HOST_OS:-linux}"
echo "==> HOST_OS configurado como: ${HOST_OS}"

if [ "$HOST_OS" = "linux" ]; then
  if ! docker info 2>/dev/null | grep -qi nvidia; then
    echo "AVISO: o runtime 'nvidia' não aparece em 'docker info'."
    echo "       Instale o NVIDIA Container Toolkit e rode:"
    echo "       sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
  fi
elif [ "$HOST_OS" = "windows" ]; then
  echo "    Modo Windows/WSL2: o passthrough de GPU específica por container"
  echo "    não é garantido pelo Docker Desktop. Veja docs/windows-gpu-notes.md."
  if [ "$(nvidia-smi -L | wc -l)" -lt 2 ]; then
    echo "AVISO: nvidia-smi dentro do WSL2 só está reportando 1 GPU. Isso é uma"
    echo "       limitação conhecida do passthrough WSL2 com múltiplas GPUs em"
    echo "       algumas versões de driver. Consulte docs/windows-gpu-notes.md."
  fi
else
  echo "ERRO: HOST_OS='${HOST_OS}' inválido no .env. Use 'linux' ou 'windows'."
  exit 1
fi

DIFY_DIR="${DIFY_DIR:-./dify}"

echo "==> Clonando/atualizando o Dify oficial em ${DIFY_DIR}..."
if [ ! -d "$DIFY_DIR" ]; then
  if [ "${DIFY_VERSION:-latest}" = "latest" ]; then
    TAG=$(curl -s https://api.github.com/repos/langgenius/dify/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    echo "    Última release detectada: ${TAG}"
    git clone --branch "$TAG" --depth 1 https://github.com/langgenius/dify.git "$DIFY_DIR"
  else
    git clone --branch "$DIFY_VERSION" --depth 1 https://github.com/langgenius/dify.git "$DIFY_DIR"
  fi
else
  echo "    Diretório ${DIFY_DIR} já existe, pulando clone (rode 'git pull' manualmente lá para atualizar)."
fi

echo "==> Configurando .env interno do Dify..."
cd "$DIFY_DIR/docker"
if [ ! -f .env ]; then
  cp .env.example .env
fi
sed -i.bak "s/^EXPOSE_NGINX_PORT=.*/EXPOSE_NGINX_PORT=${DIFY_HTTP_PORT:-80}/" .env || true
sed -i.bak "s/^EXPOSE_NGINX_SSL_PORT=.*/EXPOSE_NGINX_SSL_PORT=${DIFY_HTTPS_PORT:-443}/" .env || true
cd "$ROOT_DIR"

echo "==> Subindo Ollama (gpu0/gpu1) + Qdrant..."
./scripts/up.sh

echo "==> Aguardando Ollama ficar saudável..."
sleep 5

echo "==> Baixando modelos definidos no .env..."
./scripts/pull-models.sh

echo "==> Subindo o Dify..."
cd "$DIFY_DIR/docker"
docker compose up -d
cd "$ROOT_DIR"

echo ""
echo "============================================================"
echo " Stack no ar (HOST_OS=${HOST_OS})."
echo "  - Dify:           http://localhost:${DIFY_HTTP_PORT:-80}/install"
echo "  - Ollama (chat):  http://localhost:${OLLAMA_GPU0_PORT:-11434}"
echo "  - Ollama (embed): http://localhost:${OLLAMA_GPU1_PORT:-11435}"
echo "  - Qdrant:         http://localhost:${QDRANT_PORT:-6333}/dashboard"
echo ""
echo " Próximo passo: abra o Dify, finalize a conta admin e cadastre"
echo " os dois provedores Ollama em Configurações > Provedores de Modelo."
echo " Veja docs/model-providers.md para o passo a passo."
if [ "$HOST_OS" = "windows" ]; then
  echo ""
  echo " Você está em modo Windows: rode ./scripts/check-gpu-affinity.sh"
  echo " para confirmar como as GPUs foram alocadas e leia"
  echo " docs/windows-gpu-notes.md se notar os dois modelos na mesma GPU."
fi
echo "============================================================"
