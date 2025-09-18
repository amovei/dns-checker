#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <domain|url>"
  exit 1
fi

# Нормализуем: урезаем схему/путь/маску, приводим к нижнему регистру
host="$(sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s/^\*\.//' <<<"$1" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$host" ]]; then
  echo "Не удалось распознать домен из: $1" >&2
  exit 1
fi

have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || { echo "Нужна утилита: $1" >&2; exit 1; }; }

need dig
have nc || echo "(нет 'nc' — проверка 80/443 пропущена)" >&2

echo "Хост: $host"

print_rr() {
  local type="$1"
  local out
  out="$(dig +short "$host" "$type" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    echo
    echo "## $type"
    sed 's/^/  - /' <<<"$out"
  fi
}

print_rr A
print_rr AAAA
print_rr CNAME
print_rr MX
print_rr NS
print_rr TXT
print_rr SOA

# Быстрый тест доступности портов на IP из A/AAAA
ips="$(dig +short "$host" A; dig +short "$host" AAAA)"
if [[ -n "${ips//$'\n'/}" && $(have nc; echo $?) -eq 0 ]]; then
  echo
  echo "## Порты (nc -zw2):"
  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    for p in 80 443; do
      if nc -zw2 "$ip" "$p" 2>/dev/null; then
        echo "  $ip:$p open"
      else
        echo "  $ip:$p closed"
      fi
    done
  done <<<"$ips"
fi
