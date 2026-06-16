# Dify + Ollama Local GPU Stack

Stack 100% local para rodar o [Dify](https://github.com/langgenius/dify) (plataforma de agentes/RAG) com modelos servidos via [Ollama](https://ollama.com), com afinidade de GPU configurável por modelo através do `.env`.

Pensado para workstations com múltiplas GPUs pequenas (ex: 2x RTX A2000 6GB), onde você quer:

- Um LLM de chat dedicado a uma GPU
- Um modelo de embeddings (+ opcionalmente reranker) dedicado à outra GPU
- Tudo acessível apenas em `localhost`, sem expor nada à rede externa
- Trocar qual modelo vai em qual GPU só editando o `.env`, sem tocar em compose files
- **Funcionar tanto em Linux quanto em Windows (Docker Desktop), escolhido por uma única variável no `.env`**

## Suporte a Linux e Windows

O projeto detecta o sistema operacional através da variável `HOST_OS` no `.env` (`linux` ou `windows`) e seleciona automaticamente o overlay de GPU correto:

| | Linux (nativo ou Docker dentro do WSL2) | Windows (Docker Desktop) |
|---|---|---|
| Overlay usado | `compose/gpu.linux.yml` | `compose/gpu.windows.yml` |
| Isolamento de GPU por container | Garantido (`device_ids` fixo por placa) | **Não garantido** — limitação conhecida do Docker Desktop/WSL2 (veja abaixo) |
| Scripts | `scripts/*.sh` (bash) | `scripts/*.ps1` (PowerShell) — ou os mesmos `.sh` se você rodar dentro do WSL2 |

> **Importante sobre Windows:** o passthrough de uma GPU *específica* para um container não é confiável hoje no Docker Desktop — há relatos consistentes de `device_ids` sendo ignorado ou de apenas a primeira GPU ficar visível para containers, mesmo com duas instaladas. Por isso, no modo `windows` os dois containers Ollama recebem acesso a **todas** as GPUs visíveis, e é o próprio driver/Ollama (não o Docker) quem decide onde cada modelo carrega. Na prática, com modelos pequenos isso costuma funcionar bem, mas sem garantia formal. Detalhes completos e como verificar o que de fato aconteceu: `docs/windows-gpu-notes.md`.

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                     localhost                             │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────────┐  │
│  │  Dify    │   │  Dify    │   │   Vector Store        │  │
│  │  Web     │──▶│  API/    │──▶│   (Qdrant)            │  │
│  │  :80     │   │  Worker  │   │   :6333               │  │
│  └──────────┘   └────┬─────┘   └──────────────────────┘  │
│                       │                                    │
│         ┌─────────────┴─────────────┐                     │
│         ▼                           ▼                     │
│  ┌─────────────────┐       ┌─────────────────┐            │
│  │ ollama-gpu0      │       │ ollama-gpu1      │            │
│  │ :11434           │       │ :11435           │            │
│  │ GPU 0 (A2000 #1) │       │ GPU 1 (A2000 #2) │            │
│  │ Linux: fixo       │       │ Linux: fixo       │            │
│  │ Windows: melhor   │       │ Windows: melhor   │            │
│  │ esforço           │       │ esforço           │            │
│  │                  │       │                  │            │
│  │ GPU0_CHAT_MODEL  │       │ GPU1_EMBED_MODEL │            │
│  │ (definido no     │       │ GPU1_RERANK_MODEL│            │
│  │  .env)           │       │ (definido no     │            │
│  │                  │       │  .env)           │            │
│  └──────────────────┘       └──────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

## Pré-requisitos

### Linux
- Driver NVIDIA instalado (`nvidia-smi` funcionando)
- Docker + Docker Compose v2.24+
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) instalado e configurado (`nvidia-ctk runtime configure --runtime=docker`)

### Windows
- Driver NVIDIA atualizado no Windows host
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) com backend **WSL2** ativado
- WSL2 atualizado (`wsl --update`)
- Recomendado: rodar os scripts `.sh` deste repositório de dentro de uma distro WSL2 (ex: Ubuntu) — é o caminho mais testado. Alternativamente, use os scripts `.ps1` equivalentes direto no PowerShell.

Ambos: ~20GB de disco livre para imagens + modelos (cada modelo 7-8B quantizado ocupa 4-5GB).

Verifique que as duas GPUs aparecem:

```bash
nvidia-smi -L
# GPU 0: NVIDIA RTX A2000 (UUID: ...)
# GPU 1: NVIDIA RTX A2000 (UUID: ...)
```

## Setup rápido

### Linux (ou Windows via WSL2)

```bash
git clone <este-repositorio> dify-local-gpu
cd dify-local-gpu
cp .env.example .env
# edite .env e confirme HOST_OS=linux (ou windows, se estiver usando Docker Desktop por dentro do WSL2)
./scripts/bootstrap.sh
```

### Windows (PowerShell, sem WSL2)

```powershell
git clone <este-repositorio> dify-local-gpu
cd dify-local-gpu
Copy-Item .env.example .env
# edite .env e confirme HOST_OS=windows
.\scripts\bootstrap.ps1
```

O bootstrap faz:

1. Clona o repositório oficial do Dify em `./dify/`
2. Lê `HOST_OS` do `.env` e escolhe o overlay de GPU correspondente
3. Sobe Ollama nas duas GPUs (`scripts/up.sh` / `up.ps1`)
4. Faz o `pull` dos modelos definidos no `.env`
5. Sobe o Dify apontando para os dois Ollama locais

Depois disso, acesse `http://localhost/install` para finalizar a configuração inicial do Dify (criar conta admin).

## Configurando os modelos por GPU (`.env`)

Edite o arquivo `.env` na raiz do projeto. As variáveis relevantes:

```bash
# Sistema operacional do host — define qual overlay de GPU é usado
HOST_OS=linux   # ou "windows"

# GPU física que cada container Ollama deve usar (apenas relevante em HOST_OS=linux)
GPU0_DEVICE_INDEX=0
GPU1_DEVICE_INDEX=1

# Modelo de CHAT (LLM principal) — vai na GPU0
GPU0_CHAT_MODEL=qwen2.5:7b-instruct-q4_K_M

# Modelos de EMBEDDING e RERANK — vão na GPU1
GPU1_EMBED_MODEL=nomic-embed-text
GPU1_RERANK_MODEL=bge-reranker-v2-m3

# Portas expostas em localhost para cada instância Ollama
OLLAMA_GPU0_PORT=11434
OLLAMA_GPU1_PORT=11435

# Janela de contexto (ajuste fino opcional)
OLLAMA_GPU0_NUM_CTX=4096
OLLAMA_GPU1_NUM_CTX=2048
```

Para trocar o modelo de chat, por exemplo para Llama 3.1 8B:

```bash
./scripts/switch-model.sh gpu0 llama3.1:8b-instruct-q4_K_M     # Linux/WSL2
.\scripts\switch-model.ps1 gpu0 llama3.1:8b-instruct-q4_K_M    # Windows PowerShell
```

Não é necessário editar nenhum arquivo de compose — a alocação de GPU e o modelo carregado são inteiramente dirigidos pelo `.env`.

## Verificando a afinidade de GPU

```bash
./scripts/check-gpu-affinity.sh     # Linux/WSL2
.\scripts\check-gpu-affinity.ps1    # Windows PowerShell
```

Isso mostra, via `nvidia-smi`, qual processo Ollama está em qual GPU e quanta VRAM está sendo usada. No Linux o resultado deve mostrar isolamento exato; no Windows, use para confirmar como o driver de fato distribuiu os modelos (veja `docs/windows-gpu-notes.md`).

## Conectando os modelos ao Dify

No painel do Dify (`Configurações > Provedores de Modelo`), adicione dois provedores **Ollama** — um para chat (GPU0), outro para embedding/rerank (GPU1). A Base URL correta depende do seu `HOST_OS`; veja a tabela completa em `docs/model-providers.md`.

## Estrutura do repositório

```
dify-local-gpu/
├── docker-compose.base.yml       # Serviços Ollama/Qdrant SEM config de GPU
├── compose/
│   ├── gpu.linux.yml             # Overlay: 1 GPU dedicada por container (Linux)
│   └── gpu.windows.yml           # Overlay: GPUs visíveis a ambos (Windows/Docker Desktop)
├── .env.example                  # Template de configuração (HOST_OS, modelos, portas, GPUs)
├── scripts/
│   ├── bootstrap.sh / .ps1       # Setup inicial completo
│   ├── up.sh / .ps1              # Sobe Ollama+Qdrant com o overlay de GPU correto
│   ├── pull-models.sh / .ps1     # Baixa/atualiza modelos definidos no .env
│   ├── check-gpu-affinity.sh / .ps1  # Confirma qual processo está em qual GPU
│   └── switch-model.sh / .ps1    # Troca modelo de uma GPU específica em runtime
├── docs/
│   ├── model-reference.md        # Modelos recomendados por faixa de VRAM (6GB)
│   ├── model-providers.md        # Como cadastrar os providers Ollama no Dify
│   ├── windows-gpu-notes.md      # Limitações de GPU passthrough no Docker Desktop
│   └── troubleshooting.md        # Problemas comuns (OOM, conectividade, reset)
└── dify/                         # (gerado pelo bootstrap — clone oficial do Dify)
```

## Por que dois containers Ollama em vez de um?

Um único processo Ollama escolhe automaticamente em qual GPU carregar cada modelo, e pode tentar fazer split de um modelo grande entre as duas — o que não é o que você quer aqui. Rodando duas instâncias Ollama separadas, no Linux conseguimos fixar cada uma a uma GPU física diferente via `device_ids`, garantindo isolamento real. No Windows essa garantia não existe ao nível do Docker (ver seção acima e `docs/windows-gpu-notes.md`), mas a separação em dois containers ainda ajuda a organizar a configuração e os logs por responsabilidade (chat vs. embedding/rerank).

## Licenças

Este repositório é apenas o "wrapper" de infraestrutura (compose files, scripts, documentação). O Dify é licenciado pela LangGenius, Inc. sob a [Dify Open Source License](https://github.com/langgenius/dify/blob/main/LICENSE) (Apache 2.0 com adendos). Os modelos referenciados em `docs/model-reference.md` têm suas próprias licenças (Llama 3.1 Community License, Apache 2.0 para Qwen2.5, MIT para Nomic Embed, etc) — confira antes de uso comercial.
