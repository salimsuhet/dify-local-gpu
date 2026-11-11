# ============================================================================
# pull-models.ps1 — baixa os modelos definidos no .env, cada um na
# instância Ollama certa:
#   GPU0 (ollama-gpu0): GPU0_CODE_MODEL
#   GPU1 (ollama-gpu1): GPU1_CHAT_MODEL, GPU1_EMBED_MODEL
#
# Rode novamente sempre que mudar algum desses modelos no .env.
# ============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#=\s][^=]*)=(.*)$') { $envVars[$matches[1].Trim()] = $matches[2].Trim() }
}

function Wait-ForOllama([string]$Container) {
    Write-Host "    Aguardando $Container..."
    # No PowerShell 5.1, stderr redirecionado de comando nativo vira erro
    # terminante sob "Stop"; aqui a falha é esperada enquanto o Ollama sobe.
    $ErrorActionPreference = "Continue"
    for ($i = 0; $i -lt 30; $i++) {
        docker exec $Container ollama list *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    throw "$Container não respondeu a tempo. Veja: docker logs $Container"
}

function Get-Model([string]$Container, [string]$Model, [string]$Label) {
    if (-not $Model) {
        Write-Host "    [$Label] nenhum modelo definido, pulando."
        return
    }
    Write-Host "    [$Label] baixando '$Model' em $Container..."
    docker exec $Container ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Falha ao baixar '$Model'. Confira o nome em https://ollama.com/library" }
}

Write-Host "==> GPU0 — modelo de código"
Wait-ForOllama "ollama-gpu0"
Get-Model "ollama-gpu0" $envVars["GPU0_CODE_MODEL"] "código"

Write-Host "==> GPU1 — conversa + embedding"
Wait-ForOllama "ollama-gpu1"
Get-Model "ollama-gpu1" $envVars["GPU1_CHAT_MODEL"] "conversa"
Get-Model "ollama-gpu1" $envVars["GPU1_EMBED_MODEL"] "embedding"

Write-Host "==> Modelos em disco:"
Write-Host "--- ollama-gpu0 ---"; docker exec ollama-gpu0 ollama list
Write-Host "--- ollama-gpu1 ---"; docker exec ollama-gpu1 ollama list
