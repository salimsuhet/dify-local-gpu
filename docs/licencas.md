# Licenças

Premissa do projeto: usar apenas componentes com **licença aberta e permissiva**, adequados inclusive para uso institucional (ex: laboratório de universidade pública atendendo alunos).

> Este documento é uma leitura técnica das licenças, não um parecer jurídico. Para uso institucional, valide com a procuradoria ou o Núcleo de Inovação Tecnológica (NIT) da instituição — principalmente o item do Dify.

Legenda: ✅ permissiva, sem condições relevantes · ⚠️ permitido com condições · ❌ incompatível com a premissa

## Software

| Componente | Licença | Status | Observação |
|---|---|---|---|
| Ollama | MIT | ✅ | |
| PostgreSQL | PostgreSQL License | ✅ | banco do Dify |
| pgvector | PostgreSQL License | ✅ | banco vetorial do RAG |
| Redis 6 | BSD-3-Clause | ✅ | O Dify fixa a versão 6. A partir do 7.4 o Redis mudou de licença (RSALv2/SSPL; AGPLv3 no 8.x) — não atualize a imagem por conta própria |
| Nginx | BSD-2-Clause | ✅ | |
| Squid (proxy SSRF do Dify) | GPLv2 | ✅ | usado sem modificação, como serviço separado: sem obrigação adicional |
| Docker Engine / Compose | Apache 2.0 | ✅ | |
| Continue (extensão VS Code/JetBrains, opcional) | Apache 2.0 | ✅ | desligue a telemetria (`continue.telemetryEnabled: false`) para manter tudo local |
| Docker Desktop | Licença comercial da Docker | ⚠️ | Gratuito para educação e organizações pequenas; empresas com 250+ funcionários **ou** receita anual acima de US$ 10 mi precisam de assinatura. Alternativa sem essa condição: Docker Engine nativo no Linux ou dentro do WSL2 (`HOST_OS=linux`) |
| **Dify** | Dify Open Source License (Apache 2.0 + condições) | ⚠️ | ver abaixo |

### A condição do Dify

A licença do Dify é Apache 2.0 com duas condições adicionais:

1. **Multi-tenant:** sem autorização por escrito da LangGenius, não é permitido operar o Dify como ambiente multi-tenant. Na licença, **um tenant = um workspace**.
   - Uma instalação com **um workspace**, onde as pessoas são membros: permitido.
   - Uma instalação que dá um workspace separado para cada turma, cliente ou aluno: exige licença comercial.
   - Se precisar separar turmas, a saída dentro da licença é uma instalação por turma.
2. **Marca:** não é permitido remover ou alterar o logo e as informações de copyright da interface do Dify.

Por essas condições, a licença do Dify **não é reconhecida como open source pela OSI**, embora o código seja aberto. Para os usos deste projeto (uso individual, equipe ou laboratório com um workspace) ela é compatível. É o único componente do stack com ressalva — e o motivo de o Dify ficar isolado como "interface": os modelos e o Ollama funcionam sem ele.

O plugin Ollama do Dify é instalado pelo Marketplace do Dify; confira a licença exibida na página do plugin no momento da instalação.

## Modelos

A licença vale **por tamanho**: dentro da mesma família, tamanhos diferentes podem ter licenças diferentes.

### Recomendados (usados por padrão)

| Modelo | Papel | Licença | Status |
|---|---|---|---|
| `qwen2.5-coder:7b` | código (GPU 0) | Apache 2.0 | ✅ |
| `qwen2.5:7b` | conversa (GPU 1) | Apache 2.0 | ✅ |
| `nomic-embed-text` | embedding (GPU 1) | Apache 2.0 | ✅ |

### Alternativas compatíveis com a premissa

| Modelo | Papel | Licença | Status |
|---|---|---|---|
| `qwen2.5-coder:0.5b` / `1.5b` / `14b` / `32b` | código | Apache 2.0 | ✅ |
| `qwen3-coder:30b` | código (GPUs de 24 GB) | Apache 2.0 | ✅ |
| `devstral:24b` (Mistral) | código / modo Agent (GPUs de 24 GB) | Apache 2.0 | ✅ |
| `granite-code:3b` / `8b` (IBM) | código | Apache 2.0 | ✅ |
| `qwen2.5:14b` / `32b` | conversa | Apache 2.0 | ✅ |
| `mistral-small:24b` | conversa (GPUs de 24 GB) | Apache 2.0 | ✅ |
| `granite3.3:2b` / `8b` (IBM) | conversa | Apache 2.0 | ✅ |
| `mistral:7b` | conversa | Apache 2.0 | ✅ |
| `phi4-mini` (Microsoft) | conversa | MIT | ✅ |
| `bge-m3` | embedding | MIT | ✅ |
| `mxbai-embed-large` | embedding | Apache 2.0 | ✅ |

### Evitar ou usar com cuidado

| Modelo | Licença | Status | Motivo |
|---|---|---|---|
| `qwen2.5-coder:3b`, `qwen2.5:3b` | Qwen Research License | ❌ | só uso não comercial/pesquisa; exceção na família Qwen2.5 |
| `qwen2.5:72b` | Qwen License | ⚠️ | condições próprias |
| `llama3.1`, `llama3.2`, `codellama` | Llama Community License | ⚠️ | exige aviso "Built with Llama" e política de uso aceitável da Meta |
| `gemma2`, `codegemma` | Gemma Terms of Use | ⚠️ | política de uso proibido; termos próprios do Google |
| `starcoder2` | BigCode OpenRAIL-M | ⚠️ | restrições de uso herdadas pelos derivados |
| `deepseek-coder-v2` | DeepSeek Model License | ⚠️ | restrições de uso |
| `codestral` | Mistral Non-Production License | ❌ | proíbe uso em produção |

Antes de adotar um modelo fora desta lista, abra a página dele em `https://ollama.com/library/<modelo>` e confira o arquivo **License**.

## Uso em laboratório de universidade pública

O stack padrão pode ser usado para atender alunos, desde que:

- **Dify:** uma instalação com um único workspace para o laboratório (ou uma instalação por turma, se precisar separar). Manter a marca do Dify.
- **Modelos:** usar os recomendados ou alternativas marcadas ✅. Se adotar um ⚠️, cumprir as condições (ex: aviso "Built with Llama").
- **Docker:** Docker Desktop é gratuito para uso educacional; em servidor Linux use o Docker Engine.

Pontos que não são de licença, mas pesam no ambiente institucional:

- **LGPD:** conversas e documentos enviados ficam gravados no Postgres do Dify (`dify/docker/volumes/`). Defina retenção, quem tem acesso administrativo e informe os usuários. Rodar tudo localmente evita transferência de dados a terceiros.
- **Capacidade:** duas GPUs de 6 GB atendem poucas pessoas simultaneamente (ver README, "Limites").
- **Exposição na rede:** publique somente o Dify (porta do Nginx), com HTTPS e contas individuais. Os Ollama devem continuar presos a `127.0.0.1`, sem autenticação própria.
