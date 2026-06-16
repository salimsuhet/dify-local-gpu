# ============================================================================
# up.ps1 — sobe Ollama (gpu0/gpu1) + Qdrant escolhendo o overlay de GPU
# correto (Linux ou Windows) conforme HOST_OS no .env.
#
# Uso (PowerShell, na raiz do projeto):
#   .\scripts\up.ps1
# ============================================================================

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

if (-not (Test-Path ".env")) {
    Write-Error "Arquivo .env não encontrado. Rode primeiro: Copy-Item .env.example .env"
    exit 1
}

# Carrega o .env para o ambiente do processo atual
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

$HostOs = [System.Environment]::GetEnvironmentVariable("HOST_OS")
if (-not $HostOs) { $HostOs = "windows" }

switch ($HostOs) {
    "linux"   { $GpuOverlay = "compose/gpu.linux.yml" }
    "windows" { $GpuOverlay = "compose/gpu.windows.yml" }
    default {
        Write-Error "HOST_OS='$HostOs' inválido no .env. Use 'linux' ou 'windows'."
        exit 1
    }
}

Write-Host "==> HOST_OS=$HostOs -> usando overlay de GPU: $GpuOverlay"

docker compose --env-file .env -f docker-compose.base.yml -f $GpuOverlay up -d

Write-Host "==> Stack Ollama/Qdrant no ar. Rode .\scripts\check-gpu-affinity.ps1 para confirmar a alocação de GPU."
