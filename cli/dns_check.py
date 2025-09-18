#!/usr/bin/env python3
import sys, json, urllib.parse, urllib.request

def build_url(domain, typ, provider):
    if provider == "google":
        return f"https://dns.google/resolve?name={urllib.parse.quote(domain)}&type={typ}"
    return f"https://cloudflare-dns.com/dns-query?name={urllib.parse.quote(domain)}&type={typ}"

def fetch(url):
    req = urllib.request.Request(url, headers={"accept":"application/dns-json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())

def main():
    args=sys.argv[1:]
    typ="A"; provider="google"; raw=False
    domain=None
    i=0
    while i < len(args):
        a=args[i]
        if a=="--type": typ=args[i+1].upper(); i+=2
        elif a=="--provider": provider=args[i+1].lower(); i+=2
        elif a=="--json": raw=True; i+=1
        else: domain=a; i+=1
    if not domain:
        print("Usage: dns_check.py [--type TYPE] [--provider google|cloudflare] [--json] DOMAIN"); return
    if "://" in domain:
        domain = urllib.parse.urlparse(domain).hostname or domain
    try:
        data = fetch(build_url(domain, typ, provider))
    except Exception:
        provider = "cloudflare" if provider=="google" else "google"
        data = fetch(build_url(domain, typ, provider))
    if raw:
        print(json.dumps(data, ensure_ascii=False, indent=2)); return
    ans=data.get("Answer") or []
    if not ans: print(f"нет записей ({typ})"); return
    for a in ans:
        print(f"{a['name'].rstrip('.')} → {a['data']} (TTL {a['TTL']})")

if __name__=="__main__": main()
