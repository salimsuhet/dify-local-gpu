# Troubleshooting

## "CUDA out of memory" ao carregar o modelo de chat

A GPU de 6GB está sendo disputada por outro processo (ex: ambiente gráfico, outro container, ou contexto configurado grande demais).

1. Confirme que mais nada está usando a GPU: `nvidia-smi`
2. Reduza `OLLAMA_GPU0_NUM_CTX` no `.env` (tente `2048`)
3. Reinicie só o container afetado:
   - Linux: `docker compose -f docker-compose.base.yml -f compose/gpu.linux.yml restart ollama-gpu0`
   - Windows: `docker compose -f docker-compose.base.yml -f compose/gpu.windows.yml restart ollama-gpu0`
4. Se persistir, troque para um modelo mais leve: `./scripts/switch-model.sh gpu0 mistral:7b-instruct-q4_K_M` (ou `.ps1` no Windows)

## O Dify não consegue alcançar o Ollama (`Connection refused` ou timeout)

Causa mais comum: o Dify está rodando em um container Docker separado do Ollama, e `localhost` dentro do container do Dify não é o `localhost` da sua máquina.

- **Linux:** use o IP da interface `docker0` (`ip addr show docker0`, geralmente `172.17.0.1`) ou conecte o Dify à mesma rede Docker do Ollama (`dify-local-gpu-net`) e use o nome do serviço (`http://ollama-gpu0:11434`) em vez de `localhost`.
- **Mac/Windows (Docker Desktop):** use `http://host.docker.internal:11434`.

Para conectar o Dify à rede compartilhada, edite `dify/docker/docker-compose.yaml` (ou crie um `docker-compose.override.yml` dentro da pasta do Dify) adicionando a rede externa:

```yaml
networks:
  default:
    external: true
    name: dify-local-gpu-net
```

## `nvidia-smi` funciona no host mas o container não vê a GPU

O NVIDIA Container Toolkit não está configurado para o Docker:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

Se o último comando não mostrar as GPUs, o problema é na instalação do toolkit, não no docker-compose deste repositório.

## Erro `vm.max_map_count` muito baixo (afeta o Qdrant)

Sintoma comum em vector stores baseados em mmap:

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

## Os dois containers Ollama estão usando a mesma GPU

**No Linux:** confirme os índices reais no `.env`:

```bash
nvidia-smi -L
```

Se a saída mostrar, por exemplo, `GPU 0: ... UUID: GPU-aaa...` e `GPU 1: ... UUID: GPU-bbb...`, confirme que `GPU0_DEVICE_INDEX=0` e `GPU1_DEVICE_INDEX=1` no `.env` correspondem à ordem real. Depois de qualquer mudança:

```bash
./scripts/up.sh --force-recreate ollama-gpu0 ollama-gpu1
./scripts/check-gpu-affinity.sh
```

**No Windows:** isso é esperado e documentado — o Docker Desktop não garante isolamento de GPU por container hoje. Veja `docs/windows-gpu-notes.md` para detalhes e mitigações.

## Pull de modelo trava ou fica muito lento

Modelos de 7-8B têm ~4-5GB de download. Em conexões lentas isso pode levar bastante tempo. Para acompanhar o progresso em tempo real (o `pull-models.sh` só mostra a última linha):

```bash
docker exec -it ollama-gpu0 ollama pull qwen2.5:7b-instruct-q4_K_M
```

## Quero remover um modelo antigo para liberar espaço em disco

```bash
docker exec -it ollama-gpu0 ollama list
docker exec -it ollama-gpu0 ollama rm <nome-do-modelo>
```

## Quero resetar tudo e começar do zero

Linux/WSL2:
```bash
docker compose -f docker-compose.base.yml -f compose/gpu.linux.yml down -v
cd dify/docker && docker compose down -v && cd ../..
rm -rf dify .env
./scripts/bootstrap.sh
```

Windows (PowerShell):
```powershell
docker compose -f docker-compose.base.yml -f compose/gpu.windows.yml down -v
Set-Location dify/docker; docker compose down -v; Set-Location ../..
Remove-Item -Recurse -Force dify, .env
.\scripts\bootstrap.ps1
```

**Atenção:** isso apaga todos os dados (conversas, bases de conhecimento, modelos baixados). Faça backup antes se houver algo importante.
