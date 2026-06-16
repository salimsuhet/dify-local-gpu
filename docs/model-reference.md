# Referência de Modelos para GPUs de 6GB VRAM (RTX A2000)

Esta tabela assume **Q4_K_M** (quantização padrão recomendada — melhor equilíbrio qualidade/tamanho) e contexto modesto (2-4K tokens). Os valores de VRAM já incluem o KV cache para esse contexto; aumentar a janela de contexto aumenta o consumo.

> Regra prática confirmada por múltiplas fontes: **modelos de 8B em Q4_K_M consomem ~6-7GB de VRAM**. Em uma A2000 de 6GB isso é o limite — funciona, mas com contexto curto e pouca margem. Para mais conforto (contexto maior, sem risco de OOM), prefira a faixa de 7B.

## GPU 0 — Modelo de Chat (LLM principal)

| Modelo | Tag Ollama | VRAM aprox. (Q4_K_M) | Cabe em 6GB? | Observação |
|---|---|---|---|---|
| **Qwen2.5 7B Instruct** | `qwen2.5:7b-instruct-q4_K_M` | ~5GB | ✅ Confortável | Recomendado. Forte em PT-BR e multilíngue, bom para RAG/agentes |
| Mistral 7B Instruct | `mistral:7b-instruct-q4_K_M` | ~4.5GB | ✅ Confortável | Mais leve, respostas rápidas, menos forte em PT-BR que Qwen |
| Llama 3.1 8B Instruct | `llama3.1:8b-instruct-q4_K_M` | ~6-7GB | ⚠️ No limite | Cabe, mas reduza `OLLAMA_GPU0_NUM_CTX` para 2048-3072 para evitar OOM |
| Gemma 2 9B Instruct | `gemma2:9b-instruct-q4_K_M` | ~7GB+ | ⚠️ Arriscado | Só com contexto bem reduzido; considere Gemma 2 2B se instável |
| Qwen2.5 14B Instruct | `qwen2.5:14b-instruct-q4_K_M` | ~9-10GB | ❌ Não cabe | Precisaria de offload parcial para CPU — perde muita velocidade |
| Phi-4-mini 3.8B | `phi4-mini:3.8b-q4_K_M` | ~2.5GB | ✅ Muita margem | Boa opção se quiser contexto maior ou rodar 2 modelos na mesma GPU |

**Recomendação inicial:** `qwen2.5:7b-instruct-q4_K_M` — melhor equilíbrio para uso em português, RAG e agentes, com margem de VRAM confortável na A2000 de 6GB.

## GPU 1 — Embedding + Reranker (pipeline de RAG)

Modelos de embedding/rerank são muito mais leves que LLMs de geração — sobra bastante espaço em 6GB para rodar os dois ao mesmo tempo.

| Modelo | Tag Ollama | VRAM aprox. | Função | Observação |
|---|---|---|---|---|
| **Nomic Embed Text** | `nomic-embed-text` | ~0.3GB | Embedding | Recomendado. 768 dim, até 8192 tokens por chunk, bom custo/benefício |
| BGE-M3 | `bge-m3` | ~1.2GB | Embedding | Multilíngue forte, ótimo para PT-BR, um pouco mais pesado |
| MxBai Embed Large | `mxbai-embed-large` | ~0.7GB | Embedding | Boa qualidade em inglês, 1024 dim |
| **BGE Reranker v2-M3** | `bge-reranker-v2-m3` | ~1.1GB | Rerank | Recomendado. Reordena os resultados de busca antes de enviar ao LLM, melhora bastante a precisão do RAG |

**Recomendação inicial:** `nomic-embed-text` (embedding) + `bge-reranker-v2-m3` (rerank) — juntos consomem menos de 2GB, deixando bastante margem na GPU 1 mesmo com várias requisições paralelas.

## Por que separar chat de embedding/rerank em GPUs diferentes

Em uma única GPU de 6GB, o modelo de chat (5-7GB) já ocupa quase toda a VRAM. Se o embedding/rerank tivesse que compartilhar a mesma placa, o Ollama precisaria descarregar e recarregar modelos a cada chamada (troca de contexto cara, alguns segundos de latência por troca) ou simplesmente falharia por falta de memória durante uma indexação de RAG enquanto uma conversa está em andamento. Com duas GPUs dedicadas, ambos os modelos ficam permanentemente carregados e respondem em paralelo sem essa penalidade.

## Ajustando para sua carga de uso

- **Poucos documentos, conversas curtas:** a configuração padrão deste repositório já atende bem.
- **RAG com muitos documentos grandes (centenas de páginas):** considere `bge-m3` no lugar de `nomic-embed-text` para melhor retrieval multilíngue, mesmo custando um pouco mais de VRAM — ainda cabe folgado na GPU 1.
- **Conversas muito longas (precisa de contexto grande):** prefira `mistral:7b-instruct-q4_K_M` (mais leve) em vez de um 8B, para liberar VRAM para `OLLAMA_GPU0_NUM_CTX` maior.
- **Quer testar um 14B+ mesmo assim:** edite `OLLAMA_GPU0_NUM_CTX` para um valor bem baixo (ex: 1024) no `.env` antes de rodar `./scripts/switch-model.sh gpu0 qwen2.5:14b-instruct-q4_K_M` — pode funcionar com offload parcial, mas a velocidade cai bastante.

## Quantizações alternativas

Se `Q4_K_M` ainda assim apertar demais (por exemplo, rodando outro processo que também usa a GPU), existe a opção `Q4_0` ou `Q3_K_M`, que reduzem mais o tamanho em troca de leve perda de qualidade nas respostas:

```bash
./scripts/switch-model.sh gpu0 qwen2.5:7b-instruct-q3_K_M
```

Use isso como último recurso — para a maioria dos casos, `Q4_K_M` na faixa de 7B é o ponto ideal para suas duas A2000 de 6GB.
