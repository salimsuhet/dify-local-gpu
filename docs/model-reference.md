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
