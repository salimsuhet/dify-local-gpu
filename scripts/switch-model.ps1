# ============================================================================
# switch-model.ps1 — troca o modelo carregado em uma GPU específica,
# sem precisar editar docker-compose ou derrubar o stack inteiro.
#
# Uso:
#   .\scripts\switch-model.ps1 gpu0 llama3.1:8b-instruct-q4_K_M
#   .\scripts\switch-model.ps1 gpu1 bge-m3
# ============================================================================

param(
    [Parameter(Mandatory=$true)][ValidateSet("gpu0","gpu1")][string]$Target,
    [Parameter(Mandatory=$true)][string]$Model
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$envLines = Get-Content ".env"
$envVars = @{}
$envLines | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

if ($Target -eq "gpu0") {
    $Port = if ($envVars["OLLAMA_GPU0_PORT"]) { $envVars["OLLAMA_GPU0_PORT"] } else { "11434" }
    $EnvKey = "GPU0_CHAT_MODEL"
} else {
    $Port = if ($envVars["OLLAMA_GPU1_PORT"]) { $envVars["OLLAMA_GPU1_PORT"] } else { "11435" }
    $EnvKey = "GPU1_EMBED_MODEL"
}
$Url = "http://localhost:$Port"

Write-Host "==> Baixando '$Model' em $Target ($Url)..."
$body = @{ name = $Model } | ConvertTo-Json
Invoke-RestMethod -Uri "$Url/api/pull" -Method Post -Body $body -ContentType "application/json" | Out-Null

Write-Host "==> Atualizando .env ($EnvKey=$Model)..."
if ($envLines -match "^$EnvKey=") {
    $newLines = $envLines -replace "^$EnvKey=.*", "$EnvKey=$Model"
} else {
    $newLines = $envLines + "$EnvKey=$Model"
}
Set-Content ".env" $newLines

Write-Host "==> Pronto. O modelo '$Model' já está disponível em $Target."
Write-Host "    Para remover modelos antigos e liberar espaço:"
Write-Host "    docker exec -it ollama-$Target ollama rm <modelo-antigo>"
