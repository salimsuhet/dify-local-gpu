# Troubleshooting

## O modelo responde muito devagar / aparece `CPU/GPU` no `ollama ps`

O modelo não coube inteiro na VRAM e parte foi para a CPU (muito mais lenta).

1. Veja o diagnóstico: `.\scripts\check-gpu-affinity.ps1` (ou `.sh`). O ideal é `100% GPU`.
2. Confira os logs: `docker logs ollama-gpu0 2>&1 | findstr "offloaded MiB.free"`. Se aparecer `offloaded 26/29 layers` com ~1000 MiB ainda livres, a margem de VRAM está alta: confira `OLLAMA_VRAM_MARGIN_MIB=256` no `.env` e recrie os containers.
3. Reduza o contexto no `.env` (`OLLAMA_GPU0_NUM_CTX=6144` ou `4096`) e recrie: `.\scripts\up.ps1 --force-recreate`.
3. Atualize o "Model context size" do modelo no Dify para o mesmo valor.
4. Confirme que nada mais usa a GPU (`nvidia-smi`): navegador com aceleração, outro container, monitor ligado na placa.
5. Se persistir, troque por um modelo menor: `.\scripts\switch-model.ps1 code qwen2.5-coder:1.5b-instruct-q4_K_M`.

## O Dify não conecta ao Ollama ao cadastrar o modelo

Use `http://ollama-gpu0:11434` / `http://ollama-gpu1:11434` (nunca `localhost`: dentro do container do Dify, `localhost` é o próprio container).

Esses nomes funcionam porque o bootstrap cria `dify/docker/docker-compose.override.yaml`, que liga `api`, `worker` e `plugin_daemon` à rede `dify-local-gpu-net`. Verifique:

```powershell
docker network inspect dify-local-gpu-net --format '{{range .Containers}}{{.Name}} {{end}}'
# deve listar ollama-gpu0, ollama-gpu1 e os containers api, worker e plugin_daemon do Dify
```

Se faltar algum, rode o bootstrap de novo (ele é idempotente) ou recrie o Dify: `cd dify/docker; docker compose up -d --force-recreate`.

O Dify sobe antes dos Ollama? A rede é criada pelo `up` dos Ollama. Rode `.\scripts\up.ps1` antes de `docker compose up` do Dify.

## O Dify não sobe: `DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN` vazio ou erro de profile

O bootstrap preenche esses valores em `dify/docker/.env`. Confira:

```powershell
Select-String -Path dify/docker/.env -Pattern '^(COMPOSE_PROFILES|VECTOR_STORE|DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN)='
# COMPOSE_PROFILES deve conter pgvector (e não weaviate); VECTOR_STORE=pgvector; token não vazio
```

O Dify 1.19 exige Docker Compose v2.35+ (`docker compose version`).

## Download de imagem falha com `Forbidden` (403)

Sintoma: `failed to copy: httpReadSeeker: failed open: ... registry-1.docker.io/v2/.../blobs/...: Forbidden` no `docker compose pull` ou `up`.

Acontece atrás de proxies corporativos (o Docker Desktop mostra `http.docker.internal:3128` em `docker info`) quando muitas camadas são baixadas em paralelo. O bootstrap já baixa as imagens uma por vez com novas tentativas; para refazer manualmente:

```powershell
Push-Location dify/docker
docker compose config --images | Sort-Object -Unique | ForEach-Object { docker pull $_ }
docker compose up -d
Pop-Location
```

Se uma imagem específica falhar sempre, o proxy está bloqueando esse endereço: fale com a equipe de rede para liberar `registry-1.docker.io` e `production.cloudflare.docker.com`.

## O link do app aponta para `http://127.0.0.1:3000/...` e não abre

A porta 3000 é interna do container `web`; o acesso é sempre pelo Nginx (`http://localhost`). Troque o início do link à mão (`http://localhost/chat/...`) ou corrija de vez em `dify/docker/.env`:

```
APP_WEB_URL=http://localhost
SERVICE_API_URL=http://localhost
CONSOLE_WEB_URL=http://localhost
```

Depois: `cd dify/docker; docker compose up -d`. O bootstrap já grava esses valores. Ao expor o Dify na rede (ex: laboratório), use o nome ou IP do servidor no lugar de `localhost`.

## Upload na Base de Conhecimento fica em "Indexando" para sempre

- O modelo de embedding padrão do workspace está definido? (Provedores de Modelo → Configurações do modelo do sistema)
- O worker está saudável? `cd dify/docker; docker compose logs --tail 50 worker`
- O pgvector está no ar? `docker compose ps pgvector`

## Os dois Ollama estão na mesma GPU

Veja `docs/windows-gpu-notes.md` (Windows) ou, no Linux, confira `GPU0_DEVICE_INDEX` / `GPU1_DEVICE_INDEX` contra `nvidia-smi -L` e recrie com `./scripts/up.sh --force-recreate`.

## `nvidia-smi` funciona no host, mas o container não vê a GPU (Linux)

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all ubuntu nvidia-smi -L
```

Se o último comando não listar as GPUs, o problema é na instalação do NVIDIA Container Toolkit.

## Scripts `.ps1` com erro de sintaxe ou acentos estranhos

O Windows PowerShell 5.1 só lê UTF-8 corretamente se o arquivo tiver BOM. Os `.ps1` deste repositório são salvos com BOM; se um editor remover o BOM, caracteres como `—` viram aspas e quebram o script. Regrave em "UTF-8 with BOM" (VS Code: barra de status → encoding → *Save with Encoding*).

Se a execução de scripts estiver bloqueada: `powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1`.

## Acompanhar o download de um modelo

```powershell
docker exec -it ollama-gpu0 ollama pull qwen2.5-coder:7b-instruct-q4_K_M
```

## Liberar espaço removendo modelos

```powershell
docker exec ollama-gpu0 ollama list
docker exec ollama-gpu0 ollama rm <modelo>
```

## Resetar tudo

**Apaga conversas, Bases de Conhecimento e modelos baixados.** Faça backup de `dify/docker/volumes/` antes, se precisar.

Windows:
```powershell
docker compose -f docker-compose.base.yml -f compose/gpu.windows.yml down -v
Push-Location dify/docker; docker compose down -v; Pop-Location
Remove-Item -Recurse -Force dify
.\scripts\bootstrap.ps1
```

Linux:
```bash
docker compose -f docker-compose.base.yml -f compose/gpu.linux.yml down -v
(cd dify/docker && docker compose down -v)
sudo rm -rf dify          # os volumes do Dify pertencem ao root
./scripts/bootstrap.sh
```
