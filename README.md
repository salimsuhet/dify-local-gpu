# Assistente de Código Local — Dify + Ollama em 2 GPUs

Stack 100% local para rodar um **assistente de programação** com o [Dify](https://github.com/langgenius/dify) como interface e o [Ollama](https://ollama.com) servindo os modelos, um por GPU. Pensado para workstations com duas GPUs pequenas (ex: 2x RTX A2000 6 GB) e para uso em laboratório de ensino.

## Premissas do projeto

1. **Foco em assistente de código.** O modelo padrão e a documentação priorizam geração, explicação e revisão de código. A troca por outros modelos continua aberta (um comando + cadastro no Dify).
2. **Tudo local.** Nenhum prompt, código ou documento sai da máquina. Os serviços escutam só em `localhost`.
3. **Licenças abertas e permissivas.** Cada componente e cada modelo recomendado tem licença verificada em [`docs/licencas.md`](docs/licencas.md) — incluindo a única ressalva do stack (a licença do Dify).
4. **Configuração só pelo `.env`.** Qual modelo vai em qual GPU, portas e contexto se mudam no `.env`, sem editar compose.

## Arquitetura

```
                         Navegador (localhost)
                                 │
                    ┌────────────▼─────────────┐
                    │  Dify  (web, api, worker, │
                    │  plugin_daemon, ...)      │
                    │  Postgres + pgvector (RAG)│
                    └──────┬─────────────┬──────┘
           rede dify-local-gpu-net       │
                 ┌─────────▼───┐   ┌─────▼──────────────┐
                 │ ollama-gpu0 │   │ ollama-gpu1        │
                 │ GPU 0       │   │ GPU 1              │
                 │ CÓDIGO      │   │ CONVERSA + EMBED   │
                 │ qwen2.5-    │   │ qwen2.5:7b         │
                 │ coder:7b    │   │ nomic-embed-text   │
                 │ ctx 8192    │   │ ctx 4096           │
                 └─────────────┘   └────────────────────┘
```

- **GPU 0 — modelo de código**, sozinho na placa para ter a maior janela de contexto possível (código consome contexto rápido).
- **GPU 1 — modelo de conversa** (interpretar pedidos, rotear, explicar conceitos) **+ embedding** para as Bases de Conhecimento.
- **pgvector** (dentro do próprio Dify) guarda os vetores do RAG — não há banco vetorial separado.
- Os dois modelos ficam carregados ao mesmo tempo: alternar entre conversa e código não descarrega nada da VRAM.

## Pré-requisitos

| | Windows (Docker Desktop) | Linux (ou Docker nativo dentro do WSL2) |
|---|---|---|
| Driver | NVIDIA atualizado no Windows | NVIDIA (`nvidia-smi` funcionando) |
| Docker | Docker Desktop com backend **WSL2** | Docker + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) |
| Compose | v2.35+ (exigido pelo Dify 1.19) | v2.35+ |
| Scripts | `scripts\*.ps1` (PowerShell) | `scripts/*.sh` (bash) |
| `HOST_OS` no `.env` | `windows` | `linux` |

Ambos: `git`, ~25 GB livres em disco (imagens do Dify + ~10 GB de modelos), internet na primeira execução.

Confira que as duas GPUs aparecem:

```
nvidia-smi -L
# GPU 0: NVIDIA RTX A2000 (UUID: ...)
# GPU 1: NVIDIA RTX A2000 (UUID: ...)
```

## Instalação

**Windows (PowerShell):**

```powershell
git clone <este-repositorio> dify-local-gpu
cd dify-local-gpu
.\scripts\bootstrap.ps1        # cria o .env com HOST_OS=windows se não existir
```

**Linux / WSL2:**

```bash
git clone <este-repositorio> dify-local-gpu
cd dify-local-gpu
cp .env.example .env           # HOST_OS=linux já é o padrão
./scripts/bootstrap.sh
```

O bootstrap:

1. Clona o Dify oficial (última release) em `./dify/`
2. Configura o Dify: **pgvector** como banco vetorial, senhas/tokens aleatórios, porta HTTP e um `docker-compose.override.yaml` que liga o Dify à rede dos Ollama
3. Sobe `ollama-gpu0` e `ollama-gpu1`, cada um preso à sua GPU
4. Baixa os modelos definidos no `.env` (~10 GB na primeira vez)
5. Sobe o Dify

Depois, siga **[`docs/dify-setup.md`](docs/dify-setup.md)**: criar a conta admin em `http://localhost/install`, instalar o plugin Ollama, cadastrar os modelos e criar o app "Assistente de Código" (com prompt de sistema pronto).

## Configuração (`.env`)

```bash
HOST_OS=windows                                   # ou linux

GPU0_CODE_MODEL=qwen2.5-coder:7b-instruct-q4_K_M  # GPU 0: código
OLLAMA_GPU0_NUM_CTX=8192

GPU1_CHAT_MODEL=qwen2.5:7b-instruct-q4_K_M        # GPU 1: conversa (opcional)
GPU1_EMBED_MODEL=nomic-embed-text                 # GPU 1: embedding
OLLAMA_GPU1_NUM_CTX=4096
```

No Dify, a Base URL é sempre a mesma, em qualquer sistema:

| Papel | Base URL no Dify |
|---|---|
| Código (GPU 0) | `http://ollama-gpu0:11434` |
| Conversa e embedding (GPU 1) | `http://ollama-gpu1:11434` |

Do host (scripts, testes, extensões de IDE), as mesmas instâncias ficam em `http://localhost:11434` e `http://localhost:11435`.

## Trocando de modelo

```powershell
.\scripts\switch-model.ps1 code  qwen2.5-coder:1.5b-instruct-q4_K_M   # Windows
./scripts/switch-model.sh  chat  mistral:7b-instruct-q4_K_M           # Linux
```

Papéis: `code` (GPU 0), `chat` e `embed` (GPU 1). Depois cadastre o novo modelo no Dify. Antes de adotar um modelo, confira a licença em [`docs/licencas.md`](docs/licencas.md) e o consumo de VRAM em [`docs/model-reference.md`](docs/model-reference.md).

## Verificando as GPUs

```powershell
.\scripts\check-gpu-affinity.ps1     # Windows
./scripts/check-gpu-affinity.sh      # Linux
```

Mostra a GPU (endereço PCI) que cada Ollama enxerga, a VRAM por placa e, para cada modelo carregado, se ele está **100% na GPU** ou se parte foi para a CPU (sinal de contexto grande demais).

## Comandos do dia a dia (`make`)

O `Makefile` funciona igual no Windows e no Linux: detecta o sistema e chama o script `.ps1` ou `.sh` correspondente.

| Comando | O que faz |
|---|---|
| `make` | lista os comandos |
| `make setup` | instalação completa (bootstrap) |
| `make up` / `make down` | sobe os Ollama e o Dify / para tudo (dados preservados) |
| `make restart` | `down` + `up` |
| `make status` | containers, modelos carregados (`100% GPU`?) e VRAM por placa |
| `make gpu` | diagnóstico detalhado de GPU |
| `make test` | teste de ponta a ponta: serviços, rede e carga paralela nas duas GPUs |
| `make pull` | baixa os modelos definidos no `.env` |
| `make switch ROLE=code MODEL=<modelo>` | troca um modelo (`ROLE`: `code`, `chat`, `embed`) |
| `make logs S=api` | logs de um serviço do Dify (`api`, `worker`, `plugin_daemon`...) |
| `make ollama-logs` | logs dos dois Ollama |

**Instalando o make:**
- Linux / WSL2: `sudo apt install make`
- Windows: `winget install ezwinports.make` (ou GnuWin32 Make 3.81+). Abra um terminal novo depois de instalar.

Sem make, os scripts continuam funcionando diretamente (`.\scripts\*.ps1` ou `./scripts/*.sh`), e os comandos equivalentes estão no próprio `Makefile`.

## Estrutura do repositório

```
dify-local-gpu/
├── Makefile                    # atalhos: make setup, up, down, status, switch...
├── docker-compose.base.yml     # ollama-gpu0 e ollama-gpu1, sem config de GPU
├── compose/
│   ├── gpu.linux.yml           # isolamento por device_ids (Docker)
│   └── gpu.windows.yml         # isolamento por CUDA_VISIBLE_DEVICES (Docker Desktop)
├── .env.example
├── ide/
│   └── continue-config.yaml    # configuração do Continue (VS Code) para os Ollama locais
├── apps/
│   └── assistente-de-codigo.yml # app pronto para importar no Dify (Estúdio → Importar DSL)
├── scripts/                    # bootstrap, up, pull-models, switch-model, check-gpu-affinity (.sh e .ps1)
├── docs/
│   ├── dify-setup.md           # configurar o Dify e criar o assistente de código
│   ├── vscode.md               # assistente dentro do VS Code (extensão Continue)
│   ├── model-reference.md      # modelos de código/conversa/embedding que cabem em 6 GB
│   ├── licencas.md             # licença de cada componente e modelo; uso em universidade
│   ├── windows-gpu-notes.md    # como o isolamento de GPU funciona no Docker Desktop
│   └── troubleshooting.md
└── dify/                       # gerado pelo bootstrap (clone oficial, fora do git)
```

## Limites desta configuração

- **Qualidade:** modelos de 7B são bons para funções, scripts, explicações, testes e revisão de trechos. Ficam bem abaixo de modelos de nuvem em tarefas grandes (refatorar um projeto inteiro, arquitetura).
- **Concorrência:** com `NUM_PARALLEL=1`, cada GPU atende uma requisição por vez; as demais esperam na fila. Na prática, 2 a 5 pessoas usando ao mesmo tempo com espera aceitável.
- **Rede:** tudo está preso a `127.0.0.1`. Para atender outras máquinas (ex: alunos de um laboratório), exponha **só o Dify**, com HTTPS e contas individuais — veja a seção de uso institucional em [`docs/licencas.md`](docs/licencas.md).

## Licença

Este repositório contém apenas a infraestrutura (compose, scripts, documentação). O Dify, o Ollama e cada modelo têm suas próprias licenças — resumo e implicações em [`docs/licencas.md`](docs/licencas.md).
