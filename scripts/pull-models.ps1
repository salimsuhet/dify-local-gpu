# ============================================================================
# pull-models.ps1 — baixa/atualiza os modelos definidos no .env,
# cada um na instância Ollama correta (GPU0 = chat, GPU1 = embed/rerank).
#
# Rode novamente sempre que mudar GPU0_CHAT_MODEL, GPU1_EMBED_MODEL ou
# GPU1_RERANK_MODEL no .env.
# ============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

function Get-EnvOrDefault($key, $default) {
    if ($envVars.ContainsKey($key) -and $envVars[$key]) { return $envVars[$key] }
    return $default
}

$Gpu0Url = "http://localhost:$(Get-EnvOrDefault 'OLLAMA_GPU0_PORT' '11434')"
$Gpu1Url = "http://localhost:$(Get-EnvOrDefault 'OLLAMA_GPU1_PORT' '11435')"

function Wait-ForOllama($url, $name) {
    Write-Host "    Aguardando $name responder em $url..."
    for ($i = 0; $i -lt 30; $i++) {
        try {
            Invoke-WebRequest -Uri "$url/api/tags" -UseBasicParsing -TimeoutSec 3 | Out-Null
            return
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    Write-Error "$name não respondeu a tempo em $url."
    exit 1
}

function Pull-Model($url, $model, $label) {
    if (-not $model) {
        Write-Host "    [$label] nenhum modelo definido, pulando."
        return
    }
    Write-Host "    [$label] baixando '$model'..."
    $body = @{ name = $model } | ConvertTo-Json
    Invoke-RestMethod -Uri "$url/api/pull" -Method Post -Body $body -ContentType "application/json" | Out-Null
}

Write-Host "==> GPU0 ($Gpu0Url) — modelo de chat"
Wait-ForOllama $Gpu0Url "ollama-gpu0"
Pull-Model $Gpu0Url (Get-EnvOrDefault 'GPU0_CHAT_MODEL' '') "chat"

Write-Host "==> GPU1 ($Gpu1Url) — embedding + rerank"
Wait-ForOllama $Gpu1Url "ollama-gpu1"
Pull-Model $Gpu1Url (Get-EnvOrDefault 'GPU1_EMBED_MODEL' '') "embedding"
Pull-Model $Gpu1Url (Get-EnvOrDefault 'GPU1_RERANK_MODEL' '') "rerank"

Write-Host "==> Modelos disponíveis em cada GPU:"
Write-Host "--- GPU0 (chat) ---"
try { (Invoke-RestMethod -Uri "$Gpu0Url/api/tags") | ConvertTo-Json -Depth 5 } catch {}
Write-Host "--- GPU1 (embed/rerank) ---"
try { (Invoke-RestMethod -Uri "$Gpu1Url/api/tags") | ConvertTo-Json -Depth 5 } catch {}
