# Cadastrando os Provedores Ollama no Dify

> Se você está no Windows, leia também `docs/windows-gpu-notes.md` antes deste passo — a forma como as GPUs são alocadas (e portanto qual modelo responde mais rápido) difere do Linux.

Depois que `./scripts/bootstrap.sh` (Linux/WSL2) ou `.\scripts\bootstrap.ps1` (Windows/PowerShell) terminar e você tiver criado a conta admin em `http://localhost/install`, siga estes passos para conectar os dois Ollama (chat e embedding/rerank) ao Dify.

## 1. Acesse Configurações de Provedores de Modelo

No canto superior direito, clique no seu avatar → **Configurações** → **Provedores de Modelo**. Clique em **Adicionar Modelo** e escolha **Ollama** na lista (procure por "Ollama" — ele aparece entre os provedores compatíveis com modelos auto-hospedados).

## 2. Cadastre o modelo de CHAT (GPU 0)

Preencha o formulário do provedor Ollama assim:

| Campo | Valor |
|---|---|
| Model Name | o mesmo valor de `GPU0_CHAT_MODEL` no seu `.env`, ex: `qwen2.5:7b-instruct-q4_K_M` |
| Base URL | veja a tabela abaixo, conforme seu `HOST_OS` |
| Model Type | `Chat` |
| Context Size | igual ao `OLLAMA_GPU0_NUM_CTX` do seu `.env` (padrão: `4096`) |

**Base URL conforme `HOST_OS` no `.env`:**

| HOST_OS | Base URL (chat, GPU0) | Base URL (embed/rerank, GPU1) |
|---|---|---|
| `windows` | `http://host.docker.internal:11434` | `http://host.docker.internal:11435` |
| `linux` | `http://172.17.0.1:11434` (IP da bridge `docker0` — confirme com `ip addr show docker0`) | `http://172.17.0.1:11435` |

> **Linux, alternativa mais robusta:** em vez de depender do IP da bridge (que pode variar), conecte o Dify à mesma rede Docker (`dify-local-gpu-net`) e use os nomes dos serviços diretamente: `http://ollama-gpu0:11434` e `http://ollama-gpu1:11434` (nesse caso a porta interna é sempre `11434`, já que o remapeamento `11435` é só no host). Veja `docs/troubleshooting.md` para o trecho de compose que faz essa conexão de rede.

Clique em **Salvar**. O Dify deve confirmar a conexão automaticamente (faz uma chamada de teste no Ollama).

## 3. Cadastre o modelo de EMBEDDING (GPU 1)

Repita o processo, agora apontando para a outra instância:

| Campo | Valor |
|---|---|
| Model Name | valor de `GPU1_EMBED_MODEL`, ex: `nomic-embed-text` |
| Base URL | porta 11435, conforme a tabela do passo 2 |
| Model Type | `Text Embedding` |

## 4. Cadastre o RERANKER (GPU 1, opcional)

Se você definiu `GPU1_RERANK_MODEL` no `.env`:

| Campo | Valor |
|---|---|
| Model Name | valor de `GPU1_RERANK_MODEL`, ex: `bge-reranker-v2-m3` |
| Base URL | mesma URL do passo 3 (porta 11435) |
| Model Type | `Rerank` |

## 5. Defina os modelos padrão do workspace

Em **Provedores de Modelo**, no topo da página, defina:

- **System Model Settings → Chat Model:** o modelo da GPU 0
- **System Model Settings → Embedding Model:** o modelo da GPU 1
- **System Model Settings → Rerank Model:** o reranker da GPU 1 (se cadastrado)

## 6. Crie sua base de conhecimento (Knowledge Base) usando o vector store local

Ao criar uma **Knowledge Base** em **Conhecimento**, o Dify perguntará qual vector store usar. Se o seu `docker-compose.override.yml` já está com Qdrant no ar, configure-o como vector store do Dify editando o `.env` interno do Dify (`dify/docker/.env`):

```bash
VECTOR_STORE=qdrant
QDRANT_URL=http://qdrant:6333
QDRANT_API_KEY=<o mesmo valor de QDRANT_API_KEY do seu .env raiz>
```

Depois rode `docker compose restart api worker` dentro de `dify/docker/` para aplicar.

## 7. Teste o pipeline completo

1. Suba um PDF ou documento de teste em **Conhecimento**.
2. Crie uma **Aplicação de Chat** simples, associe a Knowledge Base recém-criada.
3. Faça uma pergunta sobre o conteúdo do documento.
4. Rode `./scripts/check-gpu-affinity.sh` em outro terminal durante a pergunta — você deve ver VRAM sendo usada na GPU 0 (geração da resposta) e picos rápidos na GPU 1 (embedding da pergunta + rerank dos trechos recuperados).

Se a resposta vier coerente e citando o conteúdo do documento, o pipeline RAG está funcionando com afinidade de GPU corretamente configurada.
