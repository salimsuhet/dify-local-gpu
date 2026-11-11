# ============================================================================
# up.ps1 — sobe os dois Ollama (GPU0 = código, GPU1 = conversa + embedding)
# com o overlay de GPU correspondente ao HOST_OS do .env.
#
# Uso (na raiz do projeto):
#   .\scripts\up.ps1
#   .\scripts\up.ps1 --force-recreate      (argumentos extras vão para o compose)
# ============================================================================

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

if (-not (Test-Path ".env")) {
    Write-Error "Arquivo .env não encontrado. Rode primeiro: Copy-Item .env.example .env"
    exit 1
}

$HostOs = "windows"
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*HOST_OS=(.*)$') { $HostOs = $matches[1].Trim() }
}

switch ($HostOs) {
    "linux"   { $GpuOverlay = "compose/gpu.linux.yml" }
    "windows" { $GpuOverlay = "compose/gpu.windows.yml" }
    default {
        Write-Error "HOST_OS='$HostOs' inválido no .env. Use 'linux' ou 'windows'."
        exit 1
    }
}

Write-Host "==> HOST_OS=$HostOs -> overlay de GPU: $GpuOverlay"
docker compose --env-file .env -f docker-compose.base.yml -f $GpuOverlay up -d @args
exit $LASTEXITCODE
