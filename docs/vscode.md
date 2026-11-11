# Assistente de código dentro do VS Code (Continue)

O Dify é o chat no navegador. Para programar **dentro do editor** — perguntar sobre o arquivo aberto, editar código selecionado, autocompletar — use a extensão [Continue](https://github.com/continuedev/continue) (Apache 2.0) apontando para os mesmos Ollama deste projeto. Nada passa pelo Dify nem sai da máquina.

## Instalação

```powershell
code --install-extension Continue.continue
New-Item -ItemType Directory -Force $env:USERPROFILE\.continue | Out-Null
Copy-Item ide\continue-config.yaml $env:USERPROFILE\.continue\config.yaml
```

Linux: `cp ide/continue-config.yaml ~/.continue/config.yaml`.

**Desligue a telemetria** (vem ligada e envia dados de uso anônimos): em `settings.json` do VS Code, `"continue.telemetryEnabled": false` — ou *Settings* → busque "continue telemetry".

Os Ollama precisam estar no ar (`make up` ou `make status` para conferir).

## Como os modelos são usados

| Modelo | GPU | Papel no Continue |
|---|---|---|
| `qwen2.5-coder:7b` | 0 | chat, edição inline, aplicar mudanças, autocompletar |
| `qwen2.5:7b` | 1 | chat geral (escolha no seletor de modelo do painel) |
| `nomic-embed-text` | 1 | indexar o projeto para `@Codebase` |

## Uso

- **Abrir o chat:** ícone do Continue na barra lateral, ou **Ctrl + L**. Com código selecionado, Ctrl + L já anexa a seleção.
- **Editar código no lugar:** selecione o trecho, **Ctrl + I**, descreva a mudança ("adicione tratamento de erro", "converta para async"). Aceite ou rejeite o diff.
- **Anexar contexto com `@`:** `@Files` (um arquivo), `@Current File`, `@Problems` (erros do editor), `@Terminal` (saída do terminal), `@Git Diff` (suas mudanças), `@Codebase` (busca no projeto indexado).
- **Autocompletar:** sugestões em cinza enquanto digita; **Tab** aceita. Desligue no ícone do Continue na barra de status se atrapalhar.

## O que esperar, comparado a assistentes de código na nuvem

Assistentes agênticos na nuvem (como Claude Code, Copilot Agent ou Cursor) leem arquivos, rodam comandos, testam e editam vários arquivos **por conta própria**, com modelos muito maiores e contextos de centenas de milhares de tokens. Este setup local funciona de outro jeito:

| | Assistente agêntico na nuvem | Este setup (Continue + Qwen2.5-Coder 7B local) |
|---|---|---|
| Quem escolhe o contexto | o assistente lê o que precisar | **você** anexa com `@` |
| Executar comandos e testes | sim, sozinho | não; você roda e anexa a saída com `@Terminal` |
| Editar vários arquivos | sim | um trecho por vez (Ctrl+I), com sua aprovação |
| Contexto | centenas de milhares de tokens | 8K (~600–800 linhas no total) |
| Privacidade | código enviado ao provedor | **nada sai da máquina** |
| Custo | assinatura ou uso | zero após a instalação |

Na prática: trate-o como um par de programação para **trechos** — escrever uma função, explicar um erro, gerar testes, revisar um diff — e não como alguém que assume uma tarefa inteira.

## Limites com um modelo de 7B e 8K de contexto

- **Anexe pouco e específico.** 8K tokens são cerca de 600–800 linhas no total (seu pedido + arquivos anexados + resposta). Prefira `@Files` com o arquivo certo a `@Codebase` em projetos grandes.
- **Modo Agent (o modelo editar vários arquivos e rodar comandos sozinho) não funciona bem** com este modelo: o prompt das ferramentas ocupa boa parte do contexto e um 7B erra muito as chamadas. Use os modos **Chat** e **Edit**.
- **Autocompletar e chat dividem a GPU 0.** Com `OLLAMA_GPU0_NUM_PARALLEL=1`, uma sugestão de autocompletar espera o chat terminar (e vice-versa). Se incomodar, desligue o autocompletar ou aumente o paralelismo para 2 (dobra o consumo de contexto na VRAM; reduza `OLLAMA_GPU0_NUM_CTX` para 6144).
- Para tarefas grandes (refatorar o projeto todo, arquitetura), um modelo local de 7B é bem mais limitado que assistentes na nuvem.

## Problemas comuns

- **"Failed to connect" / sem resposta:** confira `make status`; os Ollama precisam estar em `localhost:11434` e `11435`.
- **Configuração não carregou:** o ícone de engrenagem no painel do Continue mostra erros do `config.yaml`. Depois de editar o arquivo, o Continue recarrega sozinho.
- **Primeira resposta lenta:** o modelo estava descarregado (após 30 min sem uso, `OLLAMA_KEEP_ALIVE`); as seguintes são normais.
