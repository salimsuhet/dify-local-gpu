#!/usr/bin/env bash
# ============================================================================
# test-setup.sh — teste de ponta a ponta do stack.
#
#   1. Serviços: Ollama no ar, Dify respondendo, Dify ligado à rede dos Ollama
#   2. Carga em paralelo: modelo de código (GPU0) e de conversa (GPU1) gerando
#      ao mesmo tempo, mais embeddings na GPU1, medindo a utilização de cada
#      GPU durante a execução
#   3. Resultado: tokens/s por modelo, pico de uso por GPU e se cada modelo
#      está 100% na GPU
#
# Uso (na raiz do projeto):  ./scripts/test-setup.sh     ou     make test
# ============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck disable=SC1091
source .env

GPU0_URL="http://localhost:${OLLAMA_GPU0_PORT:-11434}"
GPU1_URL="http://localhost:${OLLAMA_GPU1_PORT:-11435}"
DIFY_URL="http://localhost:${DIFY_HTTP_PORT:-80}"
NET="${SHARED_NETWORK_NAME:-dify-local-gpu-net}"
CURL=(curl -s --noproxy '*')
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
FAILS=0

check() { # check <ok:0|1> <rótulo> [detalhe]
  if [ "$1" -eq 0 ]; then printf '  \033[32m[OK]\033[0m    %s %s\n' "$2" "${3:-}"
  else printf '  \033[31m[FALHA]\033[0m %s %s\n' "$2" "${3:-}"; FAILS=$((FAILS + 1)); fi
}
json_num() { grep -o "\"$1\":[0-9.e+]*" | head -n1 | cut -d: -f2; }

# ---------------------------------------------------------------- 1. serviços
echo "==> 1. Serviços"
for u in "$GPU0_URL" "$GPU1_URL"; do
  "${CURL[@]}" --max-time 5 "$u/api/version" >/dev/null; check $? "Ollama em $u"
done
code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' --max-time 15 "$DIFY_URL/install")
[ "$code" = "200" ]; check $? "Dify em $DIFY_URL" "(HTTP $code)"
members=$(docker network inspect "$NET" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
for svc in api worker plugin_daemon; do
  echo "$members" | grep -Eq "[-_]${svc}[-_]"; check $? "Dify '$svc' na rede $NET"
done

# ------------------------------------------------------ 2. carga em paralelo
echo ""
echo "==> 2. Carga em paralelo nas duas GPUs (cerca de 30 s)"
echo "    Dica: rode 'nvidia-smi -l 1' em outro terminal para acompanhar ao vivo."

gen() { # gen <url> <modelo> <prompt> <arquivo-saída>
  "${CURL[@]}" --max-time 600 "$1/api/generate" \
    -d "{\"model\":\"$2\",\"prompt\":\"$3\",\"stream\":false,\"options\":{\"num_predict\":400}}" > "$4"
}
emb() { # emb <url> <modelo> <arquivo-saída>
  local texts start n=0
  texts=$(for i in $(seq 1 32); do printf '"def funcao_%s(x): return x * %s",' "$i" "$i"; done)
  start=$(date +%s.%N)
  for _ in $(seq 1 8); do
    "${CURL[@]}" --max-time 300 "$1/api/embed" -d "{\"model\":\"$2\",\"input\":[${texts%,}]}" > "$3.last" && n=$((n + 32))
  done
  echo "$n $(awk -v a="$(date +%s.%N)" -v b="$start" 'BEGIN { printf "%.1f", a - b }')" > "$3"
}

# Aquecimento: garante os modelos carregados para não medir o tempo de carga
[ -n "${GPU0_CODE_MODEL:-}" ] && gen "$GPU0_URL" "$GPU0_CODE_MODEL" "oi" /dev/null
[ -n "${GPU1_CHAT_MODEL:-}" ] && gen "$GPU1_URL" "$GPU1_CHAT_MODEL" "oi" /dev/null

pids=()
[ -n "${GPU0_CODE_MODEL:-}" ] && { gen "$GPU0_URL" "$GPU0_CODE_MODEL" "Escreva em Python uma classe Pilha com push, pop, peek e testes pytest completos." "$TMPD/code" & pids+=($!); }
[ -n "${GPU1_CHAT_MODEL:-}" ] && { gen "$GPU1_URL" "$GPU1_CHAT_MODEL" "Explique em detalhes, em portugues, a diferenca entre processos e threads." "$TMPD/chat" & pids+=($!); }
[ -n "${GPU1_EMBED_MODEL:-}" ] && { emb "$GPU1_URL" "$GPU1_EMBED_MODEL" "$TMPD/emb" & pids+=($!); }

declare -A PEAK
while kill -0 "${pids[@]}" 2>/dev/null; do
  while IFS=', ' read -r idx util; do
    [ "${util:-0}" -gt "${PEAK[$idx]:-0}" ] && PEAK[$idx]=$util
  done < <(nvidia-smi --query-gpu=index,utilization.gpu --format=csv,noheader,nounits)
  sleep 0.5
done
wait

# ---------------------------------------------------------------- 3. resultado
echo ""
echo "==> 3. Resultado"
for k in code chat; do
  f="$TMPD/$k"; [ -s "$f" ] || continue
  model=$(grep -o '"model":"[^"]*"' "$f" | head -n1 | cut -d'"' -f4)
  tok=$(json_num eval_count < "$f"); dur=$(json_num eval_duration < "$f")
  tps=$(awk -v t="$tok" -v d="$dur" 'BEGIN { printf "%.1f", t / (d / 1e9) }')
  awk -v x="$tps" 'BEGIN { exit !(x > 15) }'; check $? "$model" "-> $tps tokens/s ($tok tokens)"
done
if [ -s "$TMPD/emb" ]; then
  read -r n secs < "$TMPD/emb"
  [ "$n" -gt 0 ]; check $? "${GPU1_EMBED_MODEL}" "-> $n vetores em ${secs%.*} s"
fi

for idx in $(printf '%s\n' "${!PEAK[@]}" | sort); do
  [ "${PEAK[$idx]}" -ge 30 ]; check $? "GPU $idx trabalhou durante o teste" "-> pico de ${PEAK[$idx]}% de utilização"
done

for c in ollama-gpu0 ollama-gpu1; do
  while read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | grep -q '100% GPU'; check $? "$c / ${line%% *} 100% na GPU"
  done < <(docker exec "$c" ollama ps | tail -n +2)
done

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "Tudo certo: as duas GPUs trabalharam em paralelo, cada uma com seus modelos."
else
  echo "$FAILS verificação(ões) falharam. Veja docs/troubleshooting.md."
fi
exit "$FAILS"
