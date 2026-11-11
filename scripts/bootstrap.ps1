# ============================================================================
# bootstrap.ps1 — setup completo do assistente de código local (Windows).
#
#   1. Valida pré-requisitos (Docker Desktop, Compose, driver NVIDIA)
#   2. Clona o Dify oficial em $DIFY_DIR
#   3. Configura o Dify: pgvector como banco vetorial, segredos aleatórios,
#      porta HTTP e conexão com a rede dos Ollama
#   4. Sobe os dois Ollama (um por GPU) e baixa os modelos do .env
#   5. Sobe o Dify
#
# Uso (na raiz do projeto):
#   .\scripts\bootstrap.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function New-RandomHex([int]$Bytes) {
    $buf = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    return -join ($buf | ForEach-Object { $_.ToString("x2") })
}

function Read-EnvFile([string]$Path) {
    $vars = @{}
    Get-Content $Path | ForEach-Object {
        if ($_ -match '^\s*([^#=\s][^=]*)=(.*)$') { $vars[$matches[1].Trim()] = $matches[2].Trim() }
    }
    return $vars
}

# Define KEY=VALUE num arquivo .env (substitui se existir, acrescenta se não).
function Set-EnvValue([string]$Path, [string]$Key, [string]$Value) {
    $lines = @(Get-Content $Path)
    $pattern = "^\s*$([regex]::Escape($Key))="
    if ($lines | Where-Object { $_ -match $pattern }) {
        $lines = $lines | ForEach-Object { if ($_ -match $pattern) { "$Key=$Value" } else { $_ } }
    } else {
        $lines += "$Key=$Value"
    }
    [System.IO.File]::WriteAllLines((Resolve-Path $Path), [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "==> Verificando pré-requisitos..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker não encontrado. Instale o Docker Desktop primeiro."
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker Compose v2 não encontrado." }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git não encontrado." }
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host "==> GPUs detectadas:"
    nvidia-smi -L
} else {
    Write-Warning "nvidia-smi não encontrado no PATH. Verifique o driver NVIDIA."
}

Write-Host "==> Preparando .env..."
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Set-EnvValue ".env" "HOST_OS" "windows"
    Write-Host "    Criado .env a partir do template (HOST_OS=windows)."
} else {
    Write-Host "    .env já existe, mantendo o atual."
}
$envVars = Read-EnvFile ".env"
function Get-Cfg($key, $default) { if ($envVars[$key]) { return $envVars[$key] } else { return $default } }

$HostOs = Get-Cfg "HOST_OS" "windows"
Write-Host "==> HOST_OS=$HostOs"
if ($HostOs -ne "windows") {
    Write-Warning "HOST_OS='$HostOs', mas este é o bootstrap do Windows. Use scripts/bootstrap.sh no Linux/WSL2."
}

$DifyDir = Get-Cfg "DIFY_DIR" "./dify"
Write-Host "==> Clonando o Dify oficial em $DifyDir..."
if (-not (Test-Path $DifyDir)) {
    $DifyVersion = Get-Cfg "DIFY_VERSION" "latest"
    if ($DifyVersion -eq "latest") {
        $DifyVersion = (Invoke-RestMethod -Uri "https://api.github.com/repos/langgenius/dify/releases/latest").tag_name
        Write-Host "    Última release: $DifyVersion"
    }
    git clone --branch $DifyVersion --depth 1 https://github.com/langgenius/dify.git $DifyDir
    if ($LASTEXITCODE -ne 0) { throw "Falha ao clonar o Dify." }
} else {
    Write-Host "    $DifyDir já existe, pulando clone."
}

Write-Host "==> Configurando o Dify (pgvector, segredos, porta, rede)..."
$DifyDocker = Join-Path $DifyDir "docker"
$DifyEnv = Join-Path $DifyDocker ".env"
if (-not (Test-Path $DifyEnv)) { Copy-Item (Join-Path $DifyDocker ".env.example") $DifyEnv }
$difyVars = Read-EnvFile $DifyEnv

# Banco vetorial: pgvector (licença PostgreSQL) no lugar do padrão (Weaviate)
$profiles = @(($difyVars["COMPOSE_PROFILES"] -split ',') | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -ne "weaviate" })
if ($profiles -notcontains "pgvector") { $profiles = @("pgvector") + $profiles }
Set-EnvValue $DifyEnv "COMPOSE_PROFILES" ($profiles -join ',')
Set-EnvValue $DifyEnv "VECTOR_STORE" "pgvector"

# Segredos: gerados uma vez, preservados nas execuções seguintes
if (-not $difyVars["PGVECTOR_POSTGRES_PASSWORD"]) { Set-EnvValue $DifyEnv "PGVECTOR_POSTGRES_PASSWORD" (New-RandomHex 16) }
if (-not $difyVars["DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN"]) { Set-EnvValue $DifyEnv "DIFY_AGENT_LOCAL_SANDBOX_AUTH_TOKEN" (New-RandomHex 32) }

$httpPort = Get-Cfg "DIFY_HTTP_PORT" "80"
Set-EnvValue $DifyEnv "EXPOSE_NGINX_PORT" $httpPort
Set-EnvValue $DifyEnv "EXPOSE_NGINX_SSL_PORT" (Get-Cfg "DIFY_HTTPS_PORT" "443")

# URLs públicas: sem elas, os links de compartilhamento apontam para a porta
# interna do container web (http://127.0.0.1:3000), que não é acessível.
$baseUrl = if ($httpPort -eq "80") { "http://localhost" } else { "http://localhost:$httpPort" }
foreach ($k in @("APP_WEB_URL", "SERVICE_API_URL", "CONSOLE_WEB_URL")) { Set-EnvValue $DifyEnv $k $baseUrl }

# Conecta os serviços do Dify que chamam modelos à rede dos Ollama
$netName = Get-Cfg "SHARED_NETWORK_NAME" "dify-local-gpu-net"
$override = @"
# Gerado por dify-local-gpu/scripts/bootstrap — conecta o Dify à rede dos Ollama.
services:
  api:
    networks: [ollama_net]
  worker:
    networks: [ollama_net]
  plugin_daemon:
    networks: [ollama_net]
networks:
  ollama_net:
    external: true
    name: $netName
"@
[System.IO.File]::WriteAllText((Join-Path (Resolve-Path $DifyDocker) "docker-compose.override.yaml"), $override, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "==> Subindo os Ollama (GPU0 = código, GPU1 = conversa + embedding)..."
& "$PSScriptRoot\up.ps1"
if ($LASTEXITCODE -ne 0) { throw "Falha ao subir os Ollama." }

Write-Host "==> Baixando os modelos definidos no .env..."
& "$PSScriptRoot\pull-models.ps1"

Write-Host "==> Baixando as imagens do Dify (uma por vez, com novas tentativas)..."
# Pull paralelo do compose falha com 403 atrás de alguns proxies corporativos.
Push-Location $DifyDocker
foreach ($img in (docker compose config --images | Sort-Object -Unique)) {
    for ($try = 1; $try -le 4; $try++) {
        Write-Host "    $img (tentativa $try)"
        docker pull -q $img | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        if ($try -eq 4) { Pop-Location; throw "Falha ao baixar $img. Veja docs/troubleshooting.md" }
        Start-Sleep -Seconds 5
    }
}

Write-Host "==> Subindo o Dify..."
docker compose up -d
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) { throw "Falha ao subir o Dify." }

Write-Host ""
Write-Host "============================================================"
Write-Host " Stack no ar."
Write-Host "  Dify:  http://localhost:$httpPort/install   (crie a conta admin)"
Write-Host ""
Write-Host " No Dify, instale o plugin Ollama e cadastre os modelos com:"
Write-Host "  código   (GPU0): http://ollama-gpu0:11434"
Write-Host "  conversa (GPU1): http://ollama-gpu1:11434"
Write-Host "  embedding(GPU1): http://ollama-gpu1:11434"
Write-Host " Passo a passo: docs/dify-setup.md"
Write-Host ""
Write-Host " Confira a alocação de GPU: .\scripts\check-gpu-affinity.ps1"
Write-Host "============================================================"
