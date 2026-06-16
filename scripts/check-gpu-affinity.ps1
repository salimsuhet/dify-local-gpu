# ============================================================================
# check-gpu-affinity.ps1 — confirma em qual(is) GPU(s) cada container Ollama
# está rodando, e quanto de VRAM cada um está usando.
# ============================================================================

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$envVars = @{}
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
            $envVars[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
}

function Get-EnvOrDefault($key, $default) {
    if ($envVars.ContainsKey($key) -and $envVars[$key]) { return $envVars[$key] }
    return $default
}

$HostOs = Get-EnvOrDefault "HOST_OS" "windows"

Write-Host "==> HOST_OS=$HostOs"
Write-Host ""
Write-Host "==> Mapeamento de GPUs físicas:"
nvidia-smi -L
Write-Host ""

Write-Host "==> Uso de VRAM por GPU:"
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv
Write-Host ""

Write-Host "==> Containers Ollama ativos:"
foreach ($c in @("ollama-gpu0", "ollama-gpu1")) {
    $running = docker ps --format '{{.Names}}' | Select-String -Pattern "^$c$"
    if ($running) {
        Write-Host "  ${c}: rodando (modo windows — todas as GPUs visíveis, sem fixação por container)"
    } else {
        Write-Host "  ${c}: container não está rodando"
    }
}

Write-Host ""
Write-Host "==> Modelos atualmente carregados em VRAM em cada instância:"
Write-Host "--- GPU0 (chat) ---"
try {
    $r = Invoke-RestMethod -Uri "http://localhost:$(Get-EnvOrDefault 'OLLAMA_GPU0_PORT' '11434')/api/ps"
    $r | ConvertTo-Json -Depth 5
} catch {
    Write-Host "  (sem resposta — ollama-gpu0 está no ar?)"
}
Write-Host "--- GPU1 (embed/rerank) ---"
try {
    $r = Invoke-RestMethod -Uri "http://localhost:$(Get-EnvOrDefault 'OLLAMA_GPU1_PORT' '11435')/api/ps"
    $r | ConvertTo-Json -Depth 5
} catch {
    Write-Host "  (sem resposta — ollama-gpu1 está no ar?)"
}

Write-Host ""
Write-Host "NOTA: em modo Windows, se 'nvidia-smi' mostrar VRAM concentrada"
Write-Host "em uma única GPU mesmo com os dois modelos carregados, isso é"
Write-Host "esperado: o Ollama (não o Docker) decidiu colocar ambos na mesma"
Write-Host "placa. Veja docs/windows-gpu-notes.md para mitigar."
