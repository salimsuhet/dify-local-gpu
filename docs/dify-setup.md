# Configurando o Dify como Assistente de Código

Depois que o bootstrap terminar. Testado com Dify 1.19.

## 1. Conta de administrador

Abra `http://localhost/install` e crie a conta admin. Esse usuário administra o único workspace da instalação (ver condição de licença em [`licencas.md`](licencas.md)).

## 2. Instalar o plugin Ollama

Desde a versão 1.0, os provedores de modelo do Dify são plugins.

1. Clique em **Plugins** (canto superior direito) → **Marketplace**.
2. Procure **Ollama** (publicado por `langgenius`) e clique em **Instalar**.

Precisa de internet só nesta etapa. Para máquinas sem internet: baixe o pacote `.difypkg` do plugin em outra máquina pelo [Marketplace](https://marketplace.dify.ai) e use **Plugins → Instalar plugin → Arquivo local**.

## 3. Cadastrar os modelos

Em **Configurações → Provedores de Modelo → Ollama → Adicionar modelo**, cadastre um por vez. A Base URL usa o **nome do container**, porque o bootstrap liga o Dify à rede dos Ollama — vale para Windows e Linux.

**Modelo de código (GPU 0):**

| Campo | Valor |
|---|---|
| Model Name | `qwen2.5-coder:7b-instruct-q4_K_M` (igual a `GPU0_CODE_MODEL` no `.env`) |
| Model Type | LLM |
| Base URL | `http://ollama-gpu0:11434` |
| Completion mode | Chat |
| Model context size | `8192` (igual a `OLLAMA_GPU0_NUM_CTX`) |
| Upper bound for max tokens | `4096` |
| Vision / Function call | Não |

**Modelo de conversa (GPU 1):**

| Campo | Valor |
|---|---|
| Model Name | `qwen2.5:7b-instruct-q4_K_M` (igual a `GPU1_CHAT_MODEL`) |
| Model Type | LLM |
| Base URL | `http://ollama-gpu1:11434` |
| Completion mode | Chat |
| Model context size | `4096` (igual a `OLLAMA_GPU1_NUM_CTX`) |
| Upper bound for max tokens | `2048` |
| Function call | Sim (necessário se for usar o modelo em Agentes) |

**Embedding (GPU 1):**

| Campo | Valor |
|---|---|
| Model Name | `nomic-embed-text` |
| Model Type | Text Embedding |
| Base URL | `http://ollama-gpu1:11434` |
| Model context size | `2048` (limite do `nomic-embed-text` no Ollama; trechos maiores são truncados) |

> **Context size precisa bater com o `.env`.** O Dify usa esse número para decidir quanto histórico enviar; se ele for maior que o contexto real do Ollama, o início do prompt é cortado silenciosamente.

## 4. Modelos padrão do workspace

Em **Provedores de Modelo → Configurações do modelo do sistema**:

- **Modelo de raciocínio do sistema:** `qwen2.5:7b` (usado pelo Dify para gerar títulos de conversa, sugestões etc. — deixa a GPU 0 livre para código)
- **Modelo de Embedding:** `nomic-embed-text`
- **Rerank:** deixe vazio (ver `model-reference.md`)

## 5. Criar o app "Assistente de Código"

### Caminho recomendado: importar o app pronto

O repositório traz o app já configurado em [`apps/assistente-de-codigo.yml`](../apps/assistente-de-codigo.yml) (formato DSL do Dify): modelo `qwen2.5-coder:7b`, Temperature 0.2, Top P 0.9, até 2048 tokens de resposta, contexto 8192, prompt de sistema abaixo, mensagem de abertura e perguntas sugeridas.

1. Clique em **Estúdio** (menu superior).
2. Na coluna da esquerda, clique em **Importar arquivo DSL** (em inglês: *Import DSL file*).
3. Arraste ou selecione `apps/assistente-de-codigo.yml` e clique em **Criar**.
4. O editor do app abre. Teste no painel **Depurar e visualizar**, à direita.
5. Clique em **Publicar** (canto superior direito) → **Publicar atualização**. Depois, **Publicar → Executar app** abre o chat numa URL própria (`http://localhost/chat/...`), que pode ser compartilhada com os membros do workspace.

Se aparecer um aviso sobre a versão do DSL ou sobre dependências de plugin, confirme. O app só precisa do plugin Ollama, que já está instalado.

Para mudar o prompt depois: abra o app no Estúdio, edite o campo **Instruções** e publique de novo.

### Alternativa: criar do zero

1. **Estúdio → Criar do zero (Create from Blank)**. Se o tipo **Chatbot** não aparecer na lista, abra **Mais tipos básicos de app (More basic app types)**.
2. Escolha **Chatbot** e dê o nome "Assistente de Código".
3. No canto superior direito do editor, clique no nome do modelo e selecione `qwen2.5-coder:7b-instruct-q4_K_M`. No mesmo painel: **Temperature 0.2**, **Top P 0.9**, **Num Predict 2048**, **Num Ctx 8192**.
4. Em **Instruções**, cole o prompt de sistema abaixo.
5. **Publicar**.

O modelo não aparece na lista? Ele não foi cadastrado (passo 3) ou foi cadastrado com outro "Model Type". Confira em **Configurações → Provedores de Modelo → Ollama**.

### Prompt de sistema

~~~text
Você é um assistente de programação. Responda sempre em português do Brasil;
mantenha código, nomes de funções, mensagens de erro e comandos no idioma original.

Como responder:
- Vá direto ao ponto. Comece pelo código ou pela resposta, depois explique o necessário.
- Todo código em blocos ``` com a linguagem indicada (```python, ```sql, ...).
- Prefira soluções simples, legíveis e idiomáticas da linguagem em uso.
- Ao corrigir um erro, explique a causa em uma ou duas frases antes da correção.
- Ao alterar código existente, mostre apenas o trecho alterado, com contexto suficiente
  para localizá-lo, a menos que peçam o arquivo inteiro.
- Se faltar informação essencial (linguagem, versão, mensagem de erro completa),
  pergunte antes de supor.
- Se não tiver certeza de que uma API, função ou flag existe, diga isso claramente
  em vez de inventar.
- Aponte problemas de segurança evidentes (injeção de SQL, segredos no código,
  entrada sem validação) quando aparecerem.

Sobre você:
- Você é o modelo Qwen2.5-Coder 7B, executado localmente via Ollama, na GPU do
  próprio computador do usuário, com a interface Dify. Nenhum dado sai da máquina.
- Você não tem acesso à internet, a arquivos ou ao sistema do usuário: só vê o
  que for enviado nesta conversa.
- Se perguntarem onde você roda ou quem você é, responda com base nestas
  informações, não no seu treinamento.
~~~

> **Por que o bloco "Sobre você"?** Um modelo não sabe onde está sendo executado: sem essa instrução, o Qwen responde, com base no treinamento, que é "um assistente que funciona em nuvem". Se trocar o modelo, atualize o nome no bloco.

Para uso didático, acrescente por exemplo: *"O usuário é estudante. Explique o raciocínio passo a passo e, quando o pedido for um exercício, dê dicas antes da solução completa."*

## 6. (Opcional) Base de Conhecimento com seu código e documentação

Permite perguntar sobre um projeto, uma biblioteca interna ou o material de uma disciplina sem colar tudo na conversa. Os vetores ficam no **pgvector**.

1. **Conhecimento → Criar conhecimento** → envie os arquivos (`.md`, `.txt`, `.pdf`, `.html`, código salvo como `.txt`/`.md`).
2. Configuração de trechos (chunks) recomendada para código e documentação técnica:
   - **Modo:** Geral (General), delimitador `\n\n`
   - **Tamanho máximo do trecho:** 800–1000 tokens, **sobreposição:** 100
   - **Indexação:** Alta qualidade, embedding `nomic-embed-text`
   - **Recuperação:** Busca híbrida → Weighted Score (ex: 0,7 semântica / 0,3 palavra-chave), Top K 3
3. No app "Assistente de Código", em **Contexto**, adicione a Base de Conhecimento.

Mantenha o Top K baixo (3): cada trecho recuperado consome contexto do modelo de código (8K no total).

## 7. (Opcional) Um chat que decide sozinho quem responde

Implementa a ideia "um modelo interpreta, outro gera código", numa interface só:

1. **Estúdio → Criar do zero → Chatflow**.
2. Depois do nó **Início**, adicione **Classificador de Perguntas** com o modelo `qwen2.5:7b` e duas classes:
   - *Código:* "pedidos para escrever, corrigir, explicar, revisar ou converter código, comandos ou consultas"
   - *Geral:* "qualquer outra pergunta ou conversa"
3. Classe *Código* → nó **LLM** com `qwen2.5-coder:7b` e o prompt de sistema da seção 5.
4. Classe *Geral* → nó **LLM** com `qwen2.5:7b` e um prompt de assistente geral.
5. Ligue os dois a nós **Resposta** e publique.

O classificador roda na GPU 1, então não disputa VRAM com o modelo de código.

## 8. (Opcional) Usar os modelos direto no VS Code

Para programar dentro do editor (chat sobre o arquivo aberto, edição inline, autocompletar), use a extensão Continue apontando para os mesmos Ollama — guia completo em [`vscode.md`](vscode.md), configuração pronta em [`ide/continue-config.yaml`](../ide/continue-config.yaml).

## Teste rápido

1. No app "Assistente de Código", peça: *"Escreva uma função Python que valide CPF, com testes pytest."*
2. Em outro terminal, rode `.\scripts\check-gpu-affinity.ps1` (ou `.sh`): o `qwen2.5-coder` deve aparecer em `ollama-gpu0` com **100% GPU**.
