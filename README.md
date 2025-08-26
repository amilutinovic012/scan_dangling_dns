# Dangling DNS Scanner

POSIX-compatible shell script to detect **dangling DNS** CNAMEs across common providers.  
Identifies targets like **AWS S3, CloudFront, GitHub Pages, Heroku, Fastly, Netlify, Vercel, Shopify, Squarespace, Tumblr, WordPress.com, and Azure**, prints a clear **status**, and can export **CSV** / **NDJSON** for reporting.

---

## Features
- POSIX `/bin/sh` compatible (no bashisms)
- DNS → Provider fingerprinting with lightweight HTTP probes
- S3 existence check via `aws s3 ls --no-sign-request` (flags *NoSuchBucket* as claimable)
- Structured outputs: `--csv` and `--ndjson`
- Clear statuses: **VULNERABLE**, **POTENTIALLY VULNERABLE**, **NOT VULNERABLE**, **NOT CLEAR**, **EDGE CASE**, **UNKNOWN**

---

## Supported Providers (fingerprints)
- **AWS S3**: `*.s3*.amazonaws.com` (checks bucket existence)
- **Amazon CloudFront**: `*.cloudfront.net` → *not directly claimable*; **needs distribution ownership**, manual review recommended
- **GitHub Pages**: `*.github.io`
- **Heroku**: `*.herokuapp.com`, `*.herokudns.com`
- **Fastly**: `*.fastly.net`
- **Netlify**: `*.netlify.app`, `*.netlify.com` (modern flows require DNS verification)
- **Vercel**: `*.vercel.app`, `*.vercel-dns.com`, `*.zeit.world`
- **Shopify**: `*.myshopify.com`, `shops.myshopify.com`
- **Squarespace**: `*.squarespace.com`, `ext-cust.squarespace.com`
- **Tumblr**: `domains.tumblr.com`, `*.domains.tumblr.com`, `tumblr.map.fastly.net`
- **WordPress.com**: `lb.wordpress.com`, `*.wordpress.com`
- **Azure App Service**: `*.azurewebsites.net`
- **Azure Storage Static Website**: `*.web.core.windows.net`, `*.blob.core.windows.net`

> Fingerprints draw on the community-maintained research in *can-i-take-over-xyz* and common default error pages. Providers change over time; treat **POTENTIALLY VULNERABLE / NOT CLEAR** as prompts for manual validation.

---

## Requirements
- `dig` (macOS: `brew install bind`; Debian/Ubuntu: `sudo apt-get install dnsutils`)
- `curl`
- `aws` CLI (only needed for S3 existence checks; uses `--no-sign-request`)

---

## Usage
```bash
./scan_dangling_dns.sh domains.txt [--csv results.csv] [--ndjson results.ndjson]

Input: domains.txt with one domain per line (blank lines and # comments allowed).
Output (console): Lines like:

[*] Checking domain: example.com
    -> CNAME target: foo.s3.amazonaws.com
       -> Provider: AWS_S3 | VULNERABLE | Bucket 'foo' does not exist and may be claimable

Options
	•	--csv <file>   Append rows domain,cname_target,provider,status,reason
	•	--ndjson <file> Append JSON per finding on separate lines

Examples

# basic run
./scan_dangling_dns.sh domains.txt

# with exports
./scan_dangling_dns.sh domains.txt --csv out.csv --ndjson out.ndjson


⸻

Status meanings (quick guide)
	•	VULNERABLE: Strong indicator of claimability (e.g., S3 NoSuchBucket, Fastly “unknown domain”, certain default pages).
	•	POTENTIALLY VULNERABLE: Heuristic suggests risk; manual verification required (e.g., Vercel project not found).
	•	NOT VULNERABLE: Conditions indicate claim is not feasible (e.g., S3 bucket exists).
	•	NOT CLEAR: Fingerprint inconclusive; provider needs deeper review/config validation.
	•	EDGE CASE: Historically exploitable scenarios, now generally mitigated (e.g., legacy Shopify messages).
	•	UNKNOWN: Provider not recognized or pattern parsing failed.

⸻

Notes & Caveats
	•	CloudFront: a dangling *.cloudfront.net CNAME alone is not enough to take over; you’d need the distribution. Still review to ensure the distribution is owned/active and not exposing unintended origins.
	•	False positives/negatives are possible; many providers have changed flows to add verification steps.
	•	HTTP probes use short timeouts; network hiccups can affect detection—re-run if in doubt.

⸻

Triage / Remediation Tips
	1.	S3: Create the missing bucket (if appropriate) or remove the DNS record. Bucket names are global.
	2.	CloudFront: Confirm distribution ownership and configuration; remove stale CNAMEs not in use.
	3.	Heroku / GitHub Pages / Vercel / Netlify / Squarespace / Tumblr / WP.com: Verify that the domain is bound to a live project/site; otherwise remove or bind correctly.
	4.	Azure: Check App Service custom domain binding or Storage account existence; remove unused DNS.

⸻

Example domains.txt

# marketing sites
www.example.com
blog.example.com

# app endpoints
assets.example.com

