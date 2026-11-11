# GPU no Windows (Docker Desktop / WSL2)

## Resumo

No Docker Desktop, a forma "Docker" de fixar um container a uma GPU (`device_ids`) não é confiável. Este projeto contorna isso isolando as GPUs **um nível abaixo, no CUDA**, e o resultado é verificável.

| | Linux (`gpu.linux.yml`) | Windows (`gpu.windows.yml`) |
|---|---|---|
| O que o container recebe | só a GPU do `device_ids` | todas as GPUs (`count: all`) |
| Quem isola | o Docker / NVIDIA Container Toolkit | o CUDA, via `CUDA_VISIBLE_DEVICES` |
| Ordem dos índices | a do `nvidia-smi -L` | igual, graças a `CUDA_DEVICE_ORDER=PCI_BUS_ID` |
| Resultado | 1 GPU por Ollama | 1 GPU por Ollama |

## Por que `device_ids` não basta no Docker Desktop

O Docker Desktop expõe as GPUs aos containers por paravirtualização (GPU-PV, via `/dev/dxg` do WSL2), e não pelo mecanismo do NVIDIA Container Toolkit do Linux. Há relatos consistentes de `device_ids` sendo ignorado — o container vê todas as placas, ou só a primeira.

Mas, quando o container enxerga todas as GPUs, o próprio runtime CUDA respeita `CUDA_VISIBLE_DEVICES`: o processo Ollama só "vê" a placa indicada. É isso que o overlay faz:

```yaml
ollama-gpu0:
  environment:
    - CUDA_DEVICE_ORDER=PCI_BUS_ID
    - CUDA_VISIBLE_DEVICES=${GPU0_DEVICE_INDEX:-0}
```

`CUDA_DEVICE_ORDER=PCI_BUS_ID` é importante com duas placas iguais: sem ele, o CUDA ordena por "mais rápida primeiro" e o índice pode não corresponder ao do `nvidia-smi`.

## Como verificar

```powershell
.\scripts\check-gpu-affinity.ps1
```

Cada Ollama deve reportar **uma** GPU e com **endereços PCI diferentes**. Exemplo real (2x RTX A2000):

```
==> ollama-gpu0: CUDA_VISIBLE_DEVICES=0
    GPU detectada pelo Ollama: ... description="NVIDIA RTX A2000" pci_id=0000:17:00.0 total="6.0 GiB" available="5.0 GiB"
==> ollama-gpu1: CUDA_VISIBLE_DEVICES=1
    GPU detectada pelo Ollama: ... description="NVIDIA RTX A2000" pci_id=0000:65:00.0 total="6.0 GiB" available="5.0 GiB"
```

Com modelos carregados, `nvidia-smi` deve mostrar VRAM ocupada nas duas placas, e `ollama ps` deve mostrar `100% GPU` em cada modelo.

## VRAM disponível no Windows

O driver do Windows (WDDM) reserva parte da memória de cada placa: numa A2000 de 6 GB, o Ollama vê **5,0 GiB disponíveis**. Por isso o compose ativa flash attention e KV cache em 8 bits, e o contexto padrão do modelo de código é 8192. Se um monitor estiver ligado a uma das placas, ela terá ainda menos VRAM livre — prefira colocar o modelo de conversa (o menor consumo de contexto) nessa placa, trocando os índices no `.env`.

## Se o isolamento falhar

Sintoma: os dois Ollama mostram o mesmo `pci_id`, ou um deles mostra duas GPUs.

1. Confirme os índices com `nvidia-smi -L` e ajuste `GPU0_DEVICE_INDEX` / `GPU1_DEVICE_INDEX` no `.env`.
2. Recrie os containers: `.\scripts\up.ps1 --force-recreate`.
3. Atualize o driver NVIDIA e o Docker Desktop.
4. Alternativa definitiva: usar Docker Engine **dentro do WSL2**, sem Docker Desktop, com NVIDIA Container Toolkit — aí o comportamento é o do Linux, e você usa `HOST_OS=linux` e os scripts `.sh`:

   ```bash
   # dentro do Ubuntu no WSL2 (sem Docker Desktop instalado/ativo)
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER
   # instale o NVIDIA Container Toolkit:
   # https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
   ```

   Esse caminho também evita a condição de licença comercial do Docker Desktop (ver `licencas.md`).
