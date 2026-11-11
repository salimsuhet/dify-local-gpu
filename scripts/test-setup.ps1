# ============================================================================
# test-setup.ps1 — teste de ponta a ponta do stack.
#
#   1. Serviços: Ollama no ar, Dify respondendo, Dify ligado à rede dos Ollama
#   2. Carga em paralelo: modelo de código (GPU0) e de conversa (GPU1) gerando
#      ao mesmo tempo, mais embeddings na GPU1, medindo a utilização de cada
#      GPU durante a execução
#   3. Resultado: tokens/s por modelo, pico de uso por GPU e se cada modelo
#      está 100% na GPU
#
# Uso (na raiz do projeto):  .\scripts\test-setup.ps1     ou     make test
# ============================================================================

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$cfg = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#=\s][^=]*)=(.*)$') { $cfg[$matches[1].Trim()] = $matches[2].Trim() }
}
function Cfg($k, $d) { if ($cfg[$k]) { $cfg[$k] } else { $d } }

$Gpu0Url   = "http://localhost:$(Cfg 'OLLAMA_GPU0_PORT' '11434')"
$Gpu1Url   = "http://localhost:$(Cfg 'OLLAMA_GPU1_PORT' '11435')"
$CodeModel = Cfg 'GPU0_CODE_MODEL' ''
$ChatModel = Cfg 'GPU1_CHAT_MODEL' ''
$EmbModel  = Cfg 'GPU1_EMBED_MODEL' ''
$DifyUrl   = "http://localhost:$(Cfg 'DIFY_HTTP_PORT' '80')"
$NetName   = Cfg 'SHARED_NETWORK_NAME' 'dify-local-gpu-net'

$script:Fails = 0
function Check([string]$Label, [bool]$Ok, [string]$Detail = "") {
    if ($Ok) { Write-Host "  [OK]    $Label $Detail" -ForegroundColor Green }
    else     { Write-Host "  [FALHA] $Label $Detail" -ForegroundColor Red; $script:Fails++ }
}

# ---------------------------------------------------------------- 1. serviços
Write-Host "==> 1. Serviços"
foreach ($u in @($Gpu0Url, $Gpu1Url)) {
    $ok = $false; try { Invoke-RestMethod "$u/api/version" -TimeoutSec 5 | Out-Null; $ok = $true } catch {}
    Check "Ollama em $u" $ok
}
$ok = $false; try { $ok = (Invoke-WebRequest "$DifyUrl/install" -UseBasicParsing -TimeoutSec 15).StatusCode -eq 200 } catch {}
Check "Dify em $DifyUrl" $ok
$members = (docker network inspect $NetName --format '{{range .Containers}}{{.Name}} {{end}}' 2>$null) -join ' '
foreach ($svc in @("api", "worker", "plugin_daemon")) {
    Check "Dify '$svc' na rede $NetName" ($members -match "[-_]$svc[-_]")
}

# ------------------------------------------------------ 2. carga em paralelo
Write-Host ""
Write-Host "==> 2. Carga em paralelo nas duas GPUs (cerca de 30 s)"
Write-Host "    Dica: rode 'nvidia-smi -l 1' em outro terminal para acompanhar ao vivo."

$genJob = {
    param($url, $model, $prompt)
    $body = @{ model = $model; prompt = $prompt; stream = $false; options = @{ num_predict = 400 } } | ConvertTo-Json
    $r = Invoke-RestMethod "$url/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 600
    [pscustomobject]@{ model = $model; tokens = $r.eval_count; seconds = $r.eval_duration / 1e9 }
}
$embJob = {
    param($url, $model)
    $texts = 1..32 | ForEach-Object { "def funcao_$_(x): return x * $_  # trecho de código número $_ para indexação" }
    $sw = [Diagnostics.Stopwatch]::StartNew(); $n = 0
    for ($i = 0; $i -lt 8; $i++) {
        $body = @{ model = $model; input = $texts } | ConvertTo-Json
        $r = Invoke-RestMethod "$url/api/embed" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 300
        $n += $r.embeddings.Count
    }
    [pscustomobject]@{ model = $model; vectors = $n; dims = $r.embeddings[0].Count; seconds = $sw.Elapsed.TotalSeconds }
}

# Aquecimento: garante os modelos carregados para não medir o tempo de carga
foreach ($p in @(@($Gpu0Url, $CodeModel), @($Gpu1Url, $ChatModel))) {
    if ($p[1]) { try { Invoke-RestMethod "$($p[0])/api/generate" -Method Post -ContentType "application/json" -TimeoutSec 300 -Body (@{ model = $p[1]; prompt = "oi"; stream = $false; options = @{ num_predict = 1 } } | ConvertTo-Json) | Out-Null } catch {} }
}

$jobs = @()
if ($CodeModel) { $jobs += Start-Job $genJob -ArgumentList $Gpu0Url, $CodeModel, "Escreva em Python uma classe Pilha com push, pop, peek e testes pytest completos." }
if ($ChatModel) { $jobs += Start-Job $genJob -ArgumentList $Gpu1Url, $ChatModel, "Explique em detalhes, em português, a diferença entre processos e threads." }
if ($EmbModel)  { $jobs += Start-Job $embJob -ArgumentList $Gpu1Url, $EmbModel }

# Amostra a utilização de cada GPU enquanto os jobs rodam
$peak = @{}; $samples = 0
while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -gt 0) {
    nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader,nounits | ForEach-Object {
        $idx, $util = $_ -split ',\s*'
        if (-not $peak.ContainsKey($idx) -or [int]$util -gt $peak[$idx]) { $peak[$idx] = [int]$util }
    }
    $samples++
    Start-Sleep -Milliseconds 500
}
$results = $jobs | Receive-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job -Force

# ---------------------------------------------------------------- 3. resultado
Write-Host ""
Write-Host "==> 3. Resultado"
foreach ($r in $results) {
    if ($r.PSObject.Properties.Name -contains 'tokens') {
        $tps = [math]::Round($r.tokens / $r.seconds, 1)
        Check "$($r.model)" ($tps -gt 15) "-> $tps tokens/s ($($r.tokens) tokens)"
    } else {
        $vps = [math]::Round($r.vectors / $r.seconds, 0)
        Check "$($r.model)" ($r.vectors -gt 0) "-> $($r.vectors) vetores de $($r.dims) dimensões, $vps vetores/s"
    }
}
if ($results.Count -lt $jobs.Count) { Check "requisições de carga" $false "(algum job falhou; veja docker logs ollama-gpu0/1)" }

foreach ($idx in ($peak.Keys | Sort-Object)) {
    Check "GPU $idx trabalhou durante o teste" ($peak[$idx] -ge 30) "-> pico de $($peak[$idx])% de utilização"
}

foreach ($c in @("ollama-gpu0", "ollama-gpu1")) {
    docker exec $c ollama ps | Select-Object -Skip 1 | Where-Object { $_.Trim() } | ForEach-Object {
        $name = ($_ -split '\s+')[0]
        Check "$c / $name 100% na GPU" ($_ -match '100% GPU') "-> $(($_ -split '\s{2,}')[3])"
    }
}

Write-Host ""
if ($script:Fails -eq 0) {
    Write-Host "Tudo certo: as duas GPUs trabalharam em paralelo, cada uma com seus modelos." -ForegroundColor Green
} else {
    Write-Host "$($script:Fails) verificação(ões) falharam. Veja docs/troubleshooting.md." -ForegroundColor Red
}
exit $script:Fails
