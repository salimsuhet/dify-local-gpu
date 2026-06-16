# ============================================================================
# bootstrap.ps1 — setup completo do stack em PowerShell puro (sem WSL2).
#
# Pré-requisitos: Docker Desktop com backend WSL2 ativado (mesmo rodando
# os comandos a partir do PowerShell, o Docker Desktop usa WSL2 por baixo
# para o GPU passthrough). Driver NVIDIA atualizado no Windows host.
#
# Uso:
#   .\scripts\bootstrap.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "==> Verificando pré-requisitos..."

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker não encontrado. Instale o Docker Desktop primeiro."
    exit 1
}

docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Compose v2 não encontrado."
    exit 1
}

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Write-Warning "nvidia-smi não encontrado no PATH do Windows. Verifique o driver NVIDIA."
} else {
    Write-Host "==> GPUs detectadas:"
    nvidia-smi -L
}

Write-Host "==> Preparando .env..."
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "    Criado .env a partir do template."
    Write-Host "    NOTA: HOST_OS deve ficar como 'windows' para este fluxo."
} else {
    Write-Host "    .env já existe, mantendo o atual."
}

# Carrega .env no ambiente do processo
$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $envVars[$key] = $value
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

$HostOs = $envVars["HOST_OS"]
if (-not $HostOs) { $HostOs = "windows" }
Write-Host "==> HOST_OS configurado como: $HostOs"

if ($HostOs -ne "windows") {
    Write-Warning "HOST_OS='$HostOs' no .env, mas você está rodando o bootstrap .ps1 (fluxo Windows)."
    Write-Warning "Edite o .env e defina HOST_OS=windows, ou use scripts/bootstrap.sh dentro do WSL2."
}

$DifyDir = $envVars["DIFY_DIR"]
if (-not $DifyDir) { $DifyDir = "./dify" }

Write-Host "==> Clonando/atualizando o Dify oficial em $DifyDir..."
if (-not (Test-Path $DifyDir)) {
    $DifyVersion = $envVars["DIFY_VERSION"]
    if (-not $DifyVersion -or $DifyVersion -eq "latest") {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/langgenius/dify/releases/latest"
        $tag = $release.tag_name
        Write-Host "    Última release detectada: $tag"
        git clone --branch $tag --depth 1 https://github.com/langgenius/dify.git $DifyDir
    } else {
        git clone --branch $DifyVersion --depth 1 https://github.com/langgenius/dify.git $DifyDir
    }
} else {
    Write-Host "    Diretório $DifyDir já existe, pulando clone."
}

Write-Host "==> Configurando .env interno do Dify..."
Push-Location "$DifyDir/docker"
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
}
$difyEnv = Get-Content ".env"
$httpPort = $envVars["DIFY_HTTP_PORT"]; if (-not $httpPort) { $httpPort = "80" }
$httpsPort = $envVars["DIFY_HTTPS_PORT"]; if (-not $httpsPort) { $httpsPort = "443" }
$difyEnv = $difyEnv -replace '^EXPOSE_NGINX_PORT=.*', "EXPOSE_NGINX_PORT=$httpPort"
$difyEnv = $difyEnv -replace '^EXPOSE_NGINX_SSL_PORT=.*', "EXPOSE_NGINX_SSL_PORT=$httpsPort"
Set-Content ".env" $difyEnv
Pop-Location

Write-Host "==> Subindo Ollama (gpu0/gpu1) + Qdrant..."
& "$PSScriptRoot\up.ps1"

Write-Host "==> Aguardando Ollama ficar saudável..."
Start-Sleep -Seconds 5

Write-Host "==> Baixando modelos definidos no .env..."
& "$PSScriptRoot\pull-models.ps1"

Write-Host "==> Subindo o Dify..."
Push-Location "$DifyDir/docker"
docker compose up -d
Pop-Location

Write-Host ""
Write-Host "============================================================"
Write-Host " Stack no ar (HOST_OS=$HostOs)."
Write-Host "  - Dify:           http://localhost:$httpPort/install"
Write-Host "  - Ollama (chat):  http://localhost:$($envVars['OLLAMA_GPU0_PORT'])"
Write-Host "  - Ollama (embed): http://localhost:$($envVars['OLLAMA_GPU1_PORT'])"
Write-Host "  - Qdrant:         http://localhost:$($envVars['QDRANT_PORT'])/dashboard"
Write-Host ""
Write-Host " Próximo passo: abra o Dify, finalize a conta admin e cadastre"
Write-Host " os dois provedores Ollama em Configurações > Provedores de Modelo."
Write-Host " Veja docs/model-providers.md para o passo a passo."
Write-Host ""
Write-Host " Rode .\scripts\check-gpu-affinity.ps1 para confirmar a alocação"
Write-Host " de GPU e leia docs/windows-gpu-notes.md se notar os dois modelos"
Write-Host " competindo pela mesma GPU."
Write-Host "============================================================"
