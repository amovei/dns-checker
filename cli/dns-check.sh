#!/usr/bin/env bash
set -euo pipefail

PROVIDER="google"   # google | cloudflare
TYPE="A"
RAW_JSON=0
SILENT=0

usage() {
  cat <<EOF
DNS over HTTPS checker

Usage:
  $(basename "$0") [options] <domain>

Options:
  -t, --type <TYPE>       A|AAAA|CNAME|MX|NS|TXT|SOA|ANY (default: A)
  -p, --provider <NAME>   google|cloudflare (default: google)
  -j, --json              Print raw JSON
  -q, --quiet             Quiet (only values)
  -h, --help              Show this help
EOF
}

DOMAIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--type) TYPE="${2^^}"; shift 2;;
    -p|--provider) PROVIDER="${2,,}"; shift 2;;
    -j|--json) RAW_JSON=1; shift;;
    -q|--quiet) SILENT=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) echo "Unknown option: $1" >&2; usage; exit 1;;
    *) DOMAIN="$1"; shift;;
  esac
done

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Error: domain is required" >&2
  usage
  exit 1
fi

# если дали URL — достаем hostname
if [[ "$DOMAIN" =~ :// ]]; then
  DOMAIN=$(printf '%s\n' "$DOMAIN" | sed -E 's%^([a-z]+)://%%; s%/.*$%%')
fi

build_url() {
  case "$PROVIDER" in
    google)     echo "https://dns.google/resolve?name=$DOMAIN&type=$TYPE";;
    cloudflare) echo "https://cloudflare-dns.com/dns-query?name=$DOMAIN&type=$TYPE";;
  esac
}

URL=$(build_url)

JSON=$(curl -fsSL -H 'accept: application/dns-json' "$URL" || true)
if [[ -z "$JSON" ]]; then
  PROVIDER="cloudflare"
  URL=$(build_url)
  JSON=$(curl -fsSL -H 'accept: application/dns-json' "$URL")
fi

if [[ $RAW_JSON -eq 1 ]]; then
  jq . <<<"$JSON"
  exit 0
fi

if jq -e '.Answer' >/dev/null <<<"$JSON"; then
  jq -r '.Answer[] | "\(.name|sub("\\.$";"")) → \(.data) (TTL \(.TTL))"' <<<"$JSON"
else
  echo "нет записей ($TYPE)"
fi
