# ============================================================================
# Makefile — atalhos para os comandos do dia a dia.
#
# Funciona em Linux/WSL2 (chama scripts/*.sh) e no Windows (chama
# scripts/*.ps1). As receitas evitam sintaxe exclusiva de bash para rodar
# também quando o make do Windows usa o cmd.exe como shell.
#
#   make            lista os comandos
#   make setup      instalação completa (bootstrap)
#   make up / down  sobe / para tudo
# ============================================================================

# Lê o .env (KEY=valor é sintaxe válida de make). Ausente na 1a execução.
-include .env

ifeq ($(OS),Windows_NT)
  HOST_OS ?= windows
  # Make de 32 bits (ex: GnuWin32) não enxerga o System32 real, onde ficam
  # nvidia-smi e o PowerShell de 64 bits; "Sysnative" dá acesso a ele.
  SYSNATIVE := $(wildcard $(SystemRoot)/Sysnative/WindowsPowerShell/v1.0/powershell.exe)
  PWSH      := $(if $(SYSNATIVE),$(SYSNATIVE),powershell) -NoProfile -ExecutionPolicy Bypass
  RUN        = $(PWSH) -File scripts/$(1).ps1
  NVSMI     := $(PWSH) -Command nvidia-smi
else
  HOST_OS ?= linux
  RUN        = ./scripts/$(1).sh
  NVSMI     := nvidia-smi
endif

DIFY_DIR ?= ./dify
OLLAMA  = docker compose --env-file .env -f docker-compose.base.yml -f compose/gpu.$(HOST_OS).yml
DIFY    = docker compose --project-directory $(DIFY_DIR)/docker

# Parâmetros opcionais: make logs S=api  |  make switch ROLE=code MODEL=...
S     ?=
ROLE  ?=
MODEL ?=

.DEFAULT_GOAL := help
.PHONY: help setup up down restart status gpu test pull switch \
        ollama-up ollama-down dify-up dify-down logs ollama-logs

# $(info) imprime pelo próprio make: igual em sh e cmd.exe
help:
	$(info Comandos disponíveis  [HOST_OS=$(HOST_OS)])
	$(info )
	$(info make setup        instalação completa: clona o Dify, sobe tudo, baixa modelos)
	$(info make up           sobe os Ollama e depois o Dify)
	$(info make down         para o Dify e depois os Ollama; dados preservados)
	$(info make restart      down + up)
	$(info make status       containers, modelos carregados e uso das GPUs)
	$(info make gpu          diagnóstico detalhado de GPU: check-gpu-affinity)
	$(info make test         teste de ponta a ponta: carga paralela nas duas GPUs)
	$(info make pull         baixa os modelos definidos no .env)
	$(info make switch ROLE=code MODEL=qwen2.5-coder:1.5b-instruct-q4_K_M)
	$(info .                 troca um modelo; ROLE: code, chat ou embed)
	$(info make logs S=api   logs de um serviço do Dify: api, worker, plugin_daemon...)
	$(info make ollama-logs  logs dos dois Ollama)
	$(info make ollama-up | ollama-down | dify-up | dify-down)
	@docker --version

setup:
	$(call RUN,bootstrap)

up: ollama-up dify-up

down: dify-down ollama-down

restart: down up

ollama-up:
	$(call RUN,up)

ollama-down:
	$(OLLAMA) down

dify-up:
	$(DIFY) up -d

dify-down:
	$(DIFY) down

status:
	$(OLLAMA) ps
	$(DIFY) ps
	docker exec ollama-gpu0 ollama ps
	docker exec ollama-gpu1 ollama ps
	$(NVSMI) --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv

gpu:
	$(call RUN,check-gpu-affinity)

test:
	$(call RUN,test-setup)

pull:
	$(call RUN,pull-models)

switch:
	$(if $(and $(ROLE),$(MODEL)),,$(error Informe ROLE e MODEL. Ex: make switch ROLE=code MODEL=qwen2.5-coder:1.5b-instruct-q4_K_M))
	$(call RUN,switch-model) $(ROLE) $(MODEL)

logs:
	$(DIFY) logs -f --tail 100 $(S)

ollama-logs:
	$(OLLAMA) logs -f --tail 100
