#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — setup completo do assistente de código local (Linux/WSL2).
#
#   1. Valida pré-requisitos (Docker, Compose, driver NVIDIA)
#   2. Clona o Dify oficial em $DIFY_DIR
#   3. Configura o Dify: pgvector como banco vetorial, segredos aleatórios,
#      porta HTTP e conexão com a rede dos Ollama
#   4. Sobe os dois Ollama (um por GPU) e baixa os modelos do .env
#   5. Sobe o Dify
#
# Uso (na raiz do projeto):
#   ./scripts/bootstrap.sh
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Define KEY=VALUE num arquivo .env (substitui se existir, acrescenta se não).
set_env_value() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file" && rm -f "${file}.bak"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}
get_env_value() { grep -E "^$2=" "$1" | tail -n1 | cut -d= -f2- || true; }

echo "==> Verificando pré-requisitos..."
command -v docker >/dev/null 2>&1 || { echo "ERRO: docker não encontrado."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERRO: Docker Compose v2 não encontrado."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERRO: git não encontrado."; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "ERRO: openssl não encontrado."; exit 1; }
command -v nvidia-smi >/dev/null 2>&1 || { echo "ERRO: nvidia-smi não encontrado. Verifique o driver NVIDIA."; exit 1; }
echo "==> GPUs detectadas:"
nvidia-smi -L

echo "==> Preparando .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "    Criado .env a partir do template. Confira HOST_OS antes de seguir."
else
  echo "    .env já existe, mantendo o atual."
fi
# shellcheck disable=SC1091
source .env

HOST_OS="${HOST_OS:-linux}"
echo "==> HOST_OS=${HOST_OS}"
case "$HOST_OS" in
  linux)
    if ! docker info 2>/dev/null | grep -qi nvidia; then
      echo "AVISO: runtime 'nvidia' não aparece em 'docker info'. Instale o NVIDIA"
      echo "       Container Toolkit e rode: sudo nvidia-ctk runtime configure --runtime=docker"
    fi ;;
  windows) echo "    Modo Docker Desktop: isolamento via CUDA_VISIBLE_DEVICES (docs/windows-gpu-notes.md)." ;;
  *) echo "ERRO: HOST_OS='${HOST_OS}' inválido. Use 'linux' ou 'windows'."; exit 1 ;;
esac

DIFY_DIR="${DIFY_DIR:-./dify}"
echo "==> Clonando o Dify oficial em ${DIFY_DIR}..."
if [ ! -d "$DIFY_DIR" ]; then
  VERSION="${DIFY_VERSION:-latest}"
  if [ "$VERSION" = "latest" ]; then
    VERSION=$(curl -fsSL https://api.github.com/repos/langgenius/dify/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    echo "    Última release: ${VERSION}"
  fi
  git clone --branch "$VERSION" --depth 1 https://github.com/langgenius/dify.git "$DIFY_DIR"
else
  echo "    ${DIFY_DIR} já existe, pulando clone."
fi

echo "==> Configurando o Dify (pgvector, segredos, porta, rede)..."
DIFY_DOCKER="${DIFY_DIR}/docker"
DIFY_ENV="${DIFY_DOCKER}/.env"
[ -f "$DIFY_ENV" ] || cp "${DIFY_DOCKER}/.env.example" "$DIFY_ENV"

# Banco vetorial: pgvector (licença PostgreSQL) no lugar do padrão (Weaviate)
PROFILES=$(get_env_value "$DIFY_ENV" COMPOSE_PROFILES | tr ',' '\n' | grep -v -e '^weaviate$' -e '^pgvector$' -e '^$' | paste -sd, -)
set_env_value "$DIFY_ENV" COMPOSE_PROFILES "pgvector${PROFILES:+,$PROFILES}"
set_env_value "$DIFY_ENV" VECTOR_STORE pgvector

# Segredos: gerados uma vez, preservados nas execuções seguintes
[ -n "$(get_env_value "$DIFY_ENV" PGVECTOR_POSTGRES_PASSWORD)" ] || set_env_value "$DIFY_ENV" PGVECTOR_POSTGRES_PASSWORD "$(openssl rand -hex 16)"
[ -n "$(get_env_value "$DIFY_ENV" DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN)" ] || set_env_value "$DIFY_ENV" DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN "$(openssl rand -hex 32)"

set_env_value "$DIFY_ENV" EXPOSE_NGINX_PORT "${DIFY_HTTP_PORT:-80}"
set_env_value "$DIFY_ENV" EXPOSE_NGINX_SSL_PORT "${DIFY_HTTPS_PORT:-443}"

# URLs públicas: sem elas, os links de compartilhamento apontam para a porta
# interna do container web (http://127.0.0.1:3000), que não é acessível.
BASE_URL="http://localhost"
[ "${DIFY_HTTP_PORT:-80}" = "80" ] || BASE_URL="http://localhost:${DIFY_HTTP_PORT}"
for k in APP_WEB_URL SERVICE_API_URL CONSOLE_WEB_URL; do set_env_value "$DIFY_ENV" "$k" "$BASE_URL"; done

# Conecta os serviços do Dify que chamam modelos à rede dos Ollama
cat > "${DIFY_DOCKER}/docker-compose.override.yaml" <<EOF
# Gerado por dify-local-gpu/scripts/bootstrap — conecta o Dify à rede dos Ollama.
services:
  api:
    networks: [ollama_net]
  worker:
    networks: [ollama_net]
  plugin_daemon:
    networks: [ollama_net]
networks:
  ollama_net:
    external: true
    name: ${SHARED_NETWORK_NAME:-dify-local-gpu-net}
EOF

echo "==> Subindo os Ollama (GPU0 = código, GPU1 = conversa + embedding)..."
./scripts/up.sh

echo "==> Baixando os modelos definidos no .env..."
./scripts/pull-models.sh

echo "==> Baixando as imagens do Dify (uma por vez, com novas tentativas)..."
# Pull paralelo do compose falha com 403 atrás de alguns proxies corporativos.
for img in $(cd "$DIFY_DOCKER" && docker compose config --images | sort -u); do
  for try in 1 2 3 4; do
    echo "    ${img} (tentativa ${try})"
    docker pull -q "$img" >/dev/null && break
    [ "$try" -eq 4 ] && { echo "ERRO: falha ao baixar ${img}. Veja docs/troubleshooting.md"; exit 1; }
    sleep 5
  done
done

echo "==> Subindo o Dify..."
(cd "$DIFY_DOCKER" && docker compose up -d)

cat <<EOF

============================================================
 Stack no ar.
  Dify:  http://localhost:${DIFY_HTTP_PORT:-80}/install   (crie a conta admin)

 No Dify, instale o plugin Ollama e cadastre os modelos com:
  código   (GPU0): http://ollama-gpu0:11434
  conversa (GPU1): http://ollama-gpu1:11434
  embedding(GPU1): http://ollama-gpu1:11434
 Passo a passo: docs/dify-setup.md

 Confira a alocação de GPU: ./scripts/check-gpu-affinity.sh
============================================================
EOF
