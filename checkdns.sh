#!/usr/bin/env bash
set -euo pipefail

# --- config / defaults ---
TYPES=(A AAAA CNAME MX NS TXT SOA)
RESOLVERS=(google cloudflare)   # в таком порядке пробуем

usage() {
  cat <<'EOF'
checkdns.sh — быстрый DNS-чекер через DNS-over-HTTPS (Google/Cloudflare)

Использование:
  checkdns.sh [-t TYPE ...] <domain|url>

Опции:
  -t TYPE      Тип записи (можно несколько раз или через запятую), по умолчанию: A,AAAA,CNAME,MX,NS,TXT,SOA
  -h           Показать помощь и выйти

Примеры:
  checkdns.sh example.com
  checkdns.sh -t A,MX example.com
  checkdns.sh -t TXT https://sub.site.tld/page
EOF
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Требуется 'jq'. Установи: sudo apt install -y jq" >&2
    exit 1
  fi
}

# Нормализуем вход: убираем схему, путь, маски, приводим к нижнему регистру
normalize_domain() {
  printf "%s" "$1" \
    | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s/^\*\.//' \
    | tr '[:upper:]' '[:lower:]'
}

# Строим URL DoH запроса
build_url() {
  local resolver="$1" domain="$2" rtype="$3"
  case "$resolver" in
    google)
      printf "https://dns.google/resolve?name=%s&type=%s" \
        "$(printf %s "$domain" | jq -sRr @uri)" \
        "$(printf %s "$rtype"  | jq -sRr @uri)"
      ;;
    cloudflare)
      printf "https://cloudflare-dns.com/dns-query?name=%s&type=%s" \
        "$(printf %s "$domain" | jq -sRr @uri)" \
        "$(printf %s "$rtype"  | jq -sRr @uri)"
      ;;
    *)
      return 1
      ;;
  esac
}

# Один запрос (с фолбэком по резолверам)
doh_query() {
  local domain="$1" rtype="$2" url
  local last_err=""
  for r in "${RESOLVERS[@]}"; do
    url="$(build_url "$r" "$domain" "$rtype")"
    if out="$(curl -fsS -H 'accept: application/dns-json' "$url" 2>/dev/null)"; then
      printf "%s" "$out"
      return 0
    else
      last_err="resolver=$r failed"
    fi
  done
  echo "$last_err" >&2
  return 1
}

print_answers() {
  local json="$1" rtype="$2"
  # Нет ответов?
  if ! jq -e '.Answer' >/dev/null 2>&1 <<<"$json"; then
    echo "нет записей"
    return 0
  fi

  # Красивый вывод
  jq -r '.Answer[] | .name as $n | .data as $d | .TTL as $t
         | "\($n) → \($d) (TTL \($t))"' <<<"$json"
}

# --- parse args ---
declare -a user_types=()
while getopts ":t:h" opt; do
  case "$opt" in
    t)
      # поддержим "A,MX,TXT" и множественные -t
      IFS=',' read -r -a parts <<<"$OPTARG"
      for p in "${parts[@]}"; do
        p_trim="$(echo "$p" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
        [[ -n "$p_trim" ]] && user_types+=("$p_trim")
      done
      ;;
    h) usage; exit 0 ;;
    \?) echo "Неизвестная опция: -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Опция -$OPTARG требует аргумент" >&2; usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

if [[ $# -lt 1 ]]; then
  usage; exit 1
fi

need_jq

DOMAIN_RAW="$1"
DOMAIN="$(normalize_domain "$DOMAIN_RAW")"
if [[ -z "$DOMAIN" ]]; then
  echo "Не удалось распознать домен из: $DOMAIN_RAW" >&2
  exit 1
fi

if [[ ${#user_types[@]} -gt 0 ]]; then
  TYPES=("${user_types[@]}")
fi

# --- run ---
echo "Домен: $DOMAIN"
for t in "${TYPES[@]}"; do
  echo
  echo "## $t"
  if json="$(doh_query "$DOMAIN" "$t")"; then
    print_answers "$json" "$t"
  else
    echo "ошибка запроса ($t)"
  fi
done
