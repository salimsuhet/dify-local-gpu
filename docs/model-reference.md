# Referência de Modelos para GPUs de 6 GB (RTX A2000)

Todos os valores assumem quantização **Q4_K_M** e as otimizações já ativas no compose:

- `OLLAMA_FLASH_ATTENTION=1` e `OLLAMA_KV_CACHE_TYPE=q8_0` — reduzem à metade a VRAM gasta com contexto;
- `LLAMA_ARG_FIT_TARGET=256` (variável `OLLAMA_VRAM_MARGIN_MIB` no `.env`) — margem de VRAM que o Ollama deixa livre. O padrão de 1024 MiB deixa 3 das 29 camadas de um 7B na CPU numa placa de 6 GB.

> **VRAM útil é menor que 6 GB.** No Windows, o driver reserva cerca de 1 GB: o Ollama reporta `available="5.0 GiB"` por placa (veja com `docker logs ollama-gpu0 | findstr "inference compute"`). No Linux sem interface gráfica na placa, sobra perto de 5,6 GB. Os números abaixo já consideram esse limite.

## Desempenho medido (2x RTX A2000 6 GB, Windows 11 + Docker Desktop)

| GPU | Modelos carregados | Contexto | Camadas na GPU | Geração |
|---|---|---|---|---|
| 0 | `qwen2.5-coder:7b` | 8192 | 29/29 (100% GPU) | **46 tokens/s** |
| 1 | `qwen2.5:7b` + `nomic-embed-text` (juntos) | 4096 / 2048 | 100% GPU ambos | **40 tokens/s** |

Com a margem padrão de 1 GiB, o mesmo modelo de código ficava com 26/29 camadas na GPU e gerava 35 tokens/s. A primeira requisição depois de carregar um modelo é bem mais lenta (aquecimento): meça sempre a partir da segunda.

Licença de cada modelo: [`licencas.md`](licencas.md). Só aparecem aqui modelos ✅ (Apache 2.0 / MIT).

## GPU 0 — modelo de código

| Modelo | Tag Ollama | Pesos | Contexto em 5 GB | Uso |
|---|---|---|---|---|
| **Qwen2.5-Coder 7B** | `qwen2.5-coder:7b-instruct-q4_K_M` | 4,7 GB | ~8K | **Recomendado.** Melhor modelo de código Apache 2.0 que cabe na placa |
| Granite Code 8B (IBM) | `granite-code:8b` | 4,6 GB | ~8K | Alternativa Apache 2.0; teste lado a lado com o Qwen no seu tipo de código |
| Qwen2.5-Coder 1.5B | `qwen2.5-coder:1.5b-instruct-q4_K_M` | 1,0 GB | 32K | Muito rápido; bom para autocompletar e tarefas curtas, fraco para lógica complexa |
| Qwen2.5-Coder 14B | `qwen2.5-coder:14b-instruct-q4_K_M` | 9 GB | — | ❌ não cabe; exigiria offload para CPU (lento) |

**Recomendação:** `qwen2.5-coder:7b-instruct-q4_K_M` com `OLLAMA_GPU0_NUM_CTX=8192`. Se `check-gpu-affinity` mostrar `CPU/GPU` em vez de `100% GPU`, baixe para `6144`.

### Quanto é 8K de contexto em código?

Cerca de 600–800 linhas de código somando **tudo**: prompt de sistema, histórico da conversa, código colado e a resposta. Em conversas longas o Dify corta o histórico mais antigo. Dicas:

- Cole só o trecho relevante (a função, não o arquivo inteiro).
- Comece uma conversa nova ao mudar de assunto.
- Para "conhecer" um projeto grande, use uma Base de Conhecimento (RAG) em vez de colar arquivos — veja `dify-setup.md`.

## GPU 1 — conversa + embedding

Os dois ficam carregados ao mesmo tempo (`OLLAMA_MAX_LOADED_MODELS=2`), então a soma precisa caber na placa.

### Conversa (opcional)

| Modelo | Tag Ollama | Pesos | Observação |
|---|---|---|---|
| **Qwen2.5 7B** | `qwen2.5:7b-instruct-q4_K_M` | 4,7 GB | **Recomendado.** Bom em PT-BR; entende pedidos e explica conceitos. Cabe com embedding e ctx 4096 |
| Mistral 7B | `mistral:7b-instruct-q4_K_M` | 4,4 GB | Mais leve, um pouco mais fraco em PT-BR |
| Granite 3.3 8B (IBM) | `granite3.3:8b` | 4,9 GB | No limite com o embedding junto |
| Phi-4-mini 3.8B | `phi4-mini` | 2,5 GB | Sobra VRAM para contexto maior |

Se não precisar de um modelo de conversa separado, deixe `GPU1_CHAT_MODEL=` vazio e use o modelo de código para tudo — o Qwen2.5-Coder conversa razoavelmente bem, só é menos fluente em PT-BR.

### Embedding (Bases de Conhecimento)

| Modelo | Tag Ollama | VRAM | Observação |
|---|---|---|---|
| **Nomic Embed Text** | `nomic-embed-text` | ~0,3 GB | **Recomendado.** 768 dimensões, até 8192 tokens por trecho |
| BGE-M3 | `bge-m3` | ~1,2 GB | Melhor em textos multilíngues/PT-BR; não cabe junto com um chat 7B |
| MxBai Embed Large | `mxbai-embed-large` | ~0,7 GB | Boa qualidade em inglês |

**Trocar o modelo de embedding exige reindexar** as Bases de Conhecimento existentes: os vetores antigos não são compatíveis com o novo modelo.

## Sobre reranking

O Ollama não oferece API de reranking, e o plugin Ollama do Dify não cadastra modelos do tipo "Rerank" — por isso o projeto não inclui reranker. Na Base de Conhecimento, use **busca híbrida** com o modo **Weighted Score** (pesos entre semântica e palavra-chave), que não depende de reranker.

## Combinações sugeridas

| Cenário | GPU 0 | GPU 1 |
|---|---|---|
| **Padrão** — assistente de código + conversa | `qwen2.5-coder:7b` (ctx 8192) | `qwen2.5:7b` + `nomic-embed-text` |
| Só código, contexto máximo | `qwen2.5-coder:7b` (ctx 8192) | `qwen2.5-coder:1.5b` (respostas rápidas) + `nomic-embed-text` |
| Laboratório com mais usuários | `qwen2.5-coder:7b` | `qwen2.5-coder:7b` (segunda cópia: duas filas em paralelo) + `nomic-embed-text` |

## Máquinas com GPUs maiores

O projeto funciona igual em placas maiores: só muda o `.env`. Todos os modelos abaixo são **Apache 2.0 ou MIT** (ver [`licencas.md`](licencas.md)).

> **Estimativas, não medições.** Os valores desta seção foram calculados (pesos Q4_K_M + KV cache em q8_0 + margem), não testados em cada placa. Confirme com `make test` e `make gpu` na máquina nova: o importante é cada modelo aparecer como `100% GPU`. No Windows, desconte ~1 GB por placa (reserva do driver).

### Por tamanho de VRAM (por placa)

| VRAM | GPU 0 — código | Contexto GPU 0 | GPU 1 — conversa + embedding | Contexto GPU 1 |
|---|---|---|---|---|
| **6 GB** (testado) | `qwen2.5-coder:7b` (4,7 GB) | 8192 | `qwen2.5:7b` + `nomic-embed-text` | 4096 |
| **8 GB** | `qwen2.5-coder:7b` | 16384 | `qwen2.5:7b` + `nomic-embed-text` | 8192 |
| **12 GB** | `qwen2.5-coder:14b` (9 GB) | 8192 | `qwen2.5:7b` + `bge-m3` (1,2 GB) | 16384 |
| **16 GB** | `qwen2.5-coder:14b` | 32768 | `qwen2.5:14b` (9 GB) + `bge-m3` | 8192 |
| **24 GB** | `qwen2.5-coder:32b` (20 GB) | 8192–16384 | `mistral-small:24b` (14 GB) + `bge-m3` | 16384 |
| **24 GB**, alternativa | `qwen3-coder:30b` (19 GB, MoE: bem mais rápido) | 16384 | idem | idem |
| **24 GB**, para modo Agent | `devstral:24b` (14 GB, feito para agentes) | 32768 | idem | idem |

Tags completas no Ollama: acrescente o sufixo de quantização quando existir, ex: `qwen2.5-coder:14b-instruct-q4_K_M`, `qwen2.5-coder:32b-instruct-q4_K_M`. Confira a tag exata em `https://ollama.com/library/<modelo>`.

### O que muda com mais VRAM

- **Modelo maior = qualidade.** O salto de 7B para 14B é o mais perceptível em código (lógica, menos erros de API); 32B se aproxima de assistentes comerciais em tarefas de um arquivo.
- **Contexto maior = mais código por conversa.** 32K tokens são ~2.500–3.000 linhas: dá para anexar vários arquivos no Continue ou usar `@Codebase` com folga.
- **Modo Agent do Continue** passa a ser viável a partir de ~24 GB, com um modelo feito para isso (`devstral:24b`) e contexto de 32K. Abaixo disso, continue usando Chat e Edit.
- **Mais usuários simultâneos:** com VRAM sobrando, aumente `OLLAMA_GPU0_NUM_PARALLEL` (2–4). Cada requisição paralela reserva o próprio contexto: `NUM_PARALLEL=4` com contexto de 8192 gasta a VRAM de um contexto de 32768.
- **Mais modelos carregados juntos:** aumente `OLLAMA_GPU0_MAX_LOADED_MODELS` / `OLLAMA_GPU1_MAX_LOADED_MODELS` se a soma dos modelos couber na placa (ex: um modelo rápido de autocompletar ao lado do de código).
- **Margem de VRAM:** em placas grandes, volte `OLLAMA_VRAM_MARGIN_MIB` para 512–1024; os 256 MiB só são necessários em placas de 6 GB.

### Checklist ao trocar de máquina ou de modelo

1. `nvidia-smi -L` e ajuste `GPU0_DEVICE_INDEX` / `GPU1_DEVICE_INDEX`.
2. No `.env`: modelos, `OLLAMA_GPU*_NUM_CTX` e, se quiser, `NUM_PARALLEL` / `MAX_LOADED_MODELS`.
3. `make pull`, depois `make up` (ou `.\scripts\up.ps1 --force-recreate` se os Ollama já estavam no ar).
4. `make test` — todos os modelos devem aparecer `100% GPU`.
5. No Dify, cadastre os novos modelos com **Model context size igual ao `.env`** e troque o modelo nos apps.
6. Atualize os arquivos que têm o modelo escrito à mão:
   - `apps/assistente-de-codigo.yml` — `name`, `num_ctx` e o bloco "Sobre você" (nome do modelo);
   - `ide/continue-config.yaml` — `model` e `contextLength` de cada entrada.
7. Se trocar o modelo de embedding (ex: para `bge-m3`), **reindexe** as Bases de Conhecimento.
