# ============================================================================
# switch-model.ps1 — troca um dos modelos do stack: baixa o novo modelo na
# instância Ollama certa e atualiza o .env.
#
# Uso:
#   .\scripts\switch-model.ps1 code  qwen2.5-coder:1.5b-instruct-q4_K_M
#   .\scripts\switch-model.ps1 chat  mistral:7b-instruct-q4_K_M
#   .\scripts\switch-model.ps1 embed bge-m3
#
# Depois, cadastre o novo modelo no Dify (docs/dify-setup.md). Trocar o
# modelo de embedding exige reindexar as Bases de Conhecimento.
# ============================================================================

param(
    [Parameter(Mandatory = $true)][ValidateSet("code", "chat", "embed")][string]$Role,
    [Parameter(Mandatory = $true)][string]$Model
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

switch ($Role) {
    "code"  { $Container = "ollama-gpu0"; $EnvKey = "GPU0_CODE_MODEL" }
    "chat"  { $Container = "ollama-gpu1"; $EnvKey = "GPU1_CHAT_MODEL" }
    "embed" { $Container = "ollama-gpu1"; $EnvKey = "GPU1_EMBED_MODEL" }
}

Write-Host "==> Baixando '$Model' em $Container..."
docker exec $Container ollama pull $Model
if ($LASTEXITCODE -ne 0) { throw "Falha ao baixar '$Model'." }

Write-Host "==> Atualizando .env ($EnvKey=$Model)..."
$lines = @(Get-Content ".env")
if ($lines -match "^$EnvKey=") {
    $lines = $lines -replace "^$EnvKey=.*", "$EnvKey=$Model"
} else {
    $lines += "$EnvKey=$Model"
}
[System.IO.File]::WriteAllLines((Resolve-Path ".env"), [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "==> Pronto. Confira a licença do modelo em docs/licencas.md."
Write-Host "    Para liberar disco: docker exec $Container ollama rm <modelo-antigo>"
