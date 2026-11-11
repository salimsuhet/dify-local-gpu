# ============================================================================
# check-gpu-affinity.ps1 — mostra a que GPU cada Ollama está preso, quanta
# VRAM cada placa usa e se algum modelo foi parcialmente para a CPU.
# ============================================================================

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "==> GPUs físicas:"
nvidia-smi -L
Write-Host ""
Write-Host "==> VRAM por GPU:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
Write-Host ""

foreach ($c in @("ollama-gpu0", "ollama-gpu1")) {
    $running = docker ps --format '{{.Names}}' | Where-Object { $_ -eq $c }
    if (-not $running) {
        Write-Host "==> ${c}: não está rodando"
        continue
    }
    $envs = docker inspect $c --format '{{range .Config.Env}}{{println .}}{{end}}' |
        Where-Object { $_ -match '^(CUDA_VISIBLE_DEVICES|NVIDIA_VISIBLE_DEVICES)=' }
    Write-Host "==> ${c}: $($envs -join ', ')"
    $gpuLine = docker logs $c 2>&1 | Select-String 'inference compute' | Select-Object -Last 1
    if ($gpuLine) { Write-Host "    GPU detectada pelo Ollama: $($gpuLine.Line -replace '.*msg=', '')" }
    Write-Host "    Modelos carregados (PROCESSOR deve ser '100% GPU'):"
    docker exec $c ollama ps | ForEach-Object { "      $_" }
    Write-Host ""
}

Write-Host "Se algum modelo aparecer como 'CPU/GPU', ele não coube na VRAM:"
Write-Host "reduza OLLAMA_GPU*_NUM_CTX no .env e rode .\scripts\up.ps1 --force-recreate"
