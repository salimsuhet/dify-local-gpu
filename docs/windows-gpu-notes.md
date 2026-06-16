# Notas sobre GPU no Windows (Docker Desktop / WSL2)

Este documento explica por que o comportamento de alocação de GPU é diferente no Windows comparado ao Linux, e o que fazer a respeito.

## O problema, resumido

No Linux com NVIDIA Container Toolkit, é possível fixar um container Docker a uma GPU física específica usando `device_ids` no compose — é exatamente isso que `compose/gpu.linux.yml` faz, garantindo que o container `ollama-gpu0` só veja a GPU 0 e o `ollama-gpu1` só veja a GPU 1.

No Docker Desktop para Windows (que usa WSL2 por baixo para o passthrough de GPU), essa garantia não existe na prática hoje:

- Há relatos confirmados de usuários onde alterar `device_ids` no compose não tem efeito algum — o container continua vendo apenas a primeira GPU do sistema, mesmo especificando o índice da segunda.
- Há também relatos de que, com múltiplas GPUs físicas, apenas uma delas é reconhecida dentro do WSL2, mesmo com ambas funcionando corretamente no Windows nativo.
- O suporte oficial documentado pela Docker para GPU no Windows é baseado em GPU Paravirtualization (GPU-PV) — uma camada adicional de virtualização que não existe no Linux nativo, e que historicamente tem comportamento menos granular para isolar GPUs individuais entre containers.

## O que este repositório faz por causa disso

Quando `HOST_OS=windows` no `.env`, o overlay `compose/gpu.windows.yml` é usado em vez do `compose/gpu.linux.yml`. A diferença:

| | Linux (`gpu.linux.yml`) | Windows (`gpu.windows.yml`) |
|---|---|---|
| Configuração | `device_ids: ["0"]` / `["1"]` | `count: all` (sem device_ids) |
| Isolamento | Garantido pelo Docker — cada container só vê 1 GPU | Não garantido — ambos containers veem todas as GPUs |
| Quem decide onde carregar o modelo | O Docker, antes do container iniciar | O driver NVIDIA / Ollama, em tempo de execução |

Na prática, com duas GPUs de 6GB e modelos pequenos (7B chat + embedding leve), isso costuma funcionar razoavelmente bem mesmo sem a garantia formal: o driver tende a alocar cada processo Ollama em uma GPU com espaço livre. Mas não é uma garantia — é um comportamento observado, não configurado.

## Como verificar o que de fato aconteceu

Depois de subir o stack, rode:

```powershell
.\scripts\check-gpu-affinity.ps1
```

ou, dentro do WSL2:

```bash
./scripts/check-gpu-affinity.sh
```

Olhe a saída de `nvidia-smi --query-gpu=...`. Se você ver VRAM consumida nas duas GPUs (uma com ~5GB do modelo de chat, outra com menos de 2GB do embedding/rerank), o isolamento aconteceu na prática, mesmo sem ser garantido pelo compose. Se toda a VRAM estiver concentrada em uma única GPU, os dois modelos foram colocados juntos.

## Se os dois modelos caírem na mesma GPU

Com modelos pequenos (7B + embedding leve), a soma ainda cabe em 6GB, então mesmo nesse cenário o stack deve continuar funcional — só não há mais separação de carga entre as placas. Opções, em ordem de preferência:

1. **Atualize o driver NVIDIA e o Docker Desktop.** O suporte a múltiplas GPUs no WSL2 tem melhorado em versões recentes; parte dos relatos de "só uma GPU visível" são de versões de driver mais antigas.
2. **Rode os dois containers Ollama fora do Docker, diretamente no Windows ou no WSL2**, usando `CUDA_VISIBLE_DEVICES` no processo Ollama nativo (fora de container) — isso contorna a camada de paravirtualização do Docker Desktop e usa o isolamento de GPU do driver CUDA diretamente, que funciona corretamente fora de containers.
3. **Aceite o comportamento atual.** Se os dois modelos cabem juntos em 6-8GB combinados, o impacto prático é apenas: sem isolamento garantido, mas sem erro funcional.

## Por que não usamos WSL2 com passthrough "tradicional" (sem Docker Desktop)

É possível instalar Docker diretamente dentro de uma distro WSL2 (sem o Docker Desktop como camada intermediária) e, nesse caso, o comportamento de GPU se aproxima mais do Linux nativo, já que o WSL2 expõe as GPUs via `/dev/dxg` direto para o driver dentro da distro. Se você quiser esse caminho:

```bash
# Dentro do WSL2 (Ubuntu), SEM Docker Desktop:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Instale o NVIDIA Container Toolkit normalmente, como no Linux:
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
```

Nesse cenário, defina `HOST_OS=linux` no `.env` (mesmo estando "dentro" do Windows) e use `compose/gpu.linux.yml` — porque tecnicamente, da perspectiva do Docker, esse setup É Linux. A diferença do que descrevemos acima é justamente não usar o Docker Desktop como intermediário.

## Resumo da recomendação

- **Quer simplicidade e já usa Docker Desktop:** `HOST_OS=windows`, aceite a falta de garantia formal de isolamento, valide com `check-gpu-affinity.ps1`.
- **Quer isolamento garantido por GPU, igual ao Linux:** instale Docker diretamente dentro do WSL2 (sem Docker Desktop), use `HOST_OS=linux`, e rode os scripts `.sh` de dentro da distro.
