#!/bin/sh
# Dangling-DNS scanner (big providers) — POSIX /bin/sh
# Adds CSV and NDJSON export options.
# Providers: AWS S3, GitHub Pages, Heroku, Fastly, Netlify, Vercel,
#            Shopify, Squarespace, Tumblr, WordPress.com, Azure App Service, Azure Storage, CloudFront
# Output (console): "Provider | STATUS | Reason"
# Options:
#   --csv <path>     Append CSV rows: domain,cname_target,provider,status,reason
#   --ndjson <path>  Append NDJSON objects per finding

set -eu

# ---------- args ----------
if [ "${1:-}" = "" ]; then
  echo "Usage: $0 domains.txt [--csv results.csv] [--ndjson results.ndjson]"
  exit 1
fi

DOMAINS_FILE=""
CSV_PATH=""
NDJSON_PATH=""

# Simple arg parser
DOMAINS_FILE="$1"; shift || true
while [ "${1:-}" != "" ]; do
  case "$1" in
    --csv)
      shift
      [ "${1:-}" = "" ] && { echo "--csv requires a path"; exit 1; }
      CSV_PATH="$1"
      ;;
    --ndjson)
      shift
      [ "${1:-}" = "" ] && { echo "--ndjson requires a path"; exit 1; }
      NDJSON_PATH="$1"
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 domains.txt [--csv results.csv] [--ndjson results.ndjson]"
      exit 1
      ;;
  esac
  shift || true
done

# ---------- helpers ----------
normalize_host() {
  # lowercase + strip trailing dot
  printf %s "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//'
}

http_head() {
  d="$1"
  h="$(curl -sI --max-time 6 "http://$d" 2>/dev/null || true)"
  [ -z "$h" ] && h="$(curl -sI --max-time 6 "https://$d" 2>/dev/null || true)"
  printf %s "$h"
}

http_body() {
  d="$1"
  b="$(curl -sL --max-time 8 "http://$d" 2>/dev/null || true)"
  [ -z "$b" ] && b="$(curl -sL --max-time 8 "https://$d" 2>/dev/null || true)"
  printf %s "$b"
}

extract_s3_bucket() {
  host="$1"
  b=$(printf %s "$host" | sed -n 's/^\([a-z0-9.-]\+\)\.s3\.amazonaws\.com$/\1/p'); [ -n "$b" ] && { printf %s "$b"; return; }
  b=$(printf %s "$host" | sed -n 's/^\([a-z0-9.-]\+\)\.s3\.[a-z0-9-]\+\.amazonaws\.com$/\1/p'); [ -n "$b" ] && { printf %s "$b"; return; }
  b=$(printf %s "$host" | sed -n 's/^\([a-z0-9.-]\+\)\.s3-website-[a-z0-9-]\+\.amazonaws\.com$/\1/p'); [ -n "$b" ] && { printf %s "$b"; return; }
  b=$(printf %s "$host" | sed -n 's/^\([a-z0-9.-]\+\)\.s3-website\.[a-z0-9-]\+\.amazonaws\.com$/\1/p'); [ -n "$b" ] && { printf %s "$b"; return; }
  b=$(printf %s "$host" | sed -n 's/^\([a-z0-9.-]\+\)\.s3\.dualstack\.[a-z0-9-]\+\.amazonaws\.com$/\1/p'); [ -n "$b" ] && { printf %s "$b"; return; }
  printf ""
}

detect_provider() {
  tgt="$1"
  case "$tgt" in
    *.s3.amazonaws.com|*.s3.*.amazonaws.com|*.s3-website-*.*.amazonaws.com|*.s3-website.*.amazonaws.com|*.s3.dualstack.*.amazonaws.com)
      echo "AWS_S3"; return;;
    *.github.io)
      echo "GITHUB_PAGES"; return;;
    *.herokuapp.com|*.herokudns.com)
      echo "HEROKU"; return;;
    *.fastly.net)
      echo "FASTLY"; return;;
    *.netlify.com|*.netlify.app|*.netlifyglobalcdn.com|apex-loadbalancer.netlify.com)
      echo "NETLIFY"; return;;
    *.vercel.app|*.vercel-dns.com|*.zeit.world)
      echo "VERCEL"; return;;
    *.myshopify.com|shops.myshopify.com)
      echo "SHOPIFY"; return;;
    *.squarespace.com|ext-cust.squarespace.com)
      echo "SQUARESPACE"; return;;
    domains.tumblr.com|*.domains.tumblr.com|tumblr.map.fastly.net)
      echo "TUMBLR"; return;;
    lb.wordpress.com|*.wordpress.com)
      echo "WORDPRESS_COM"; return;;
    *.azurewebsites.net)
      echo "AZURE_APPSERVICE"; return;;
    *.blob.core.windows.net|*.web.core.windows.net)
      echo "AZURE_STORAGE_STATIC"; return;;
    *.cloudfront.net)
      echo "CLOUDFRONT"; return;;
    *)
      echo "OTHER"; return;;
  esac
}

print_human() {
  provider="$1"; status="$2"; reason="$3"
  printf "       -> Provider: %s | %s | %s\n" "$provider" "$status" "$reason"
}

csv_escape() {
  # escape " by doubling, wrap whole field in quotes
  printf %s "$1" | sed 's/"/""/g' | sed 's/^/"/; s/$/"/'
}

emit_csv() {
  [ -z "$CSV_PATH" ] && return
  domain="$1"; cname="$2"; provider="$3"; status="$4"; reason="$5"
  # write header once
  if [ ! -f "$CSV_PATH" ]; then
    printf "domain,cname_target,provider,status,reason\n" > "$CSV_PATH"
  fi
  printf "%s,%s,%s,%s,%s\n" \
    "$(csv_escape "$domain")" \
    "$(csv_escape "$cname")" \
    "$(csv_escape "$provider")" \
    "$(csv_escape "$status")" \
    "$(csv_escape "$reason")" >> "$CSV_PATH"
}

json_escape() {
  # Escape backslash and double-quote, strip newlines/tabs
  printf %s "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[\r\n\t]/ /g'
}

emit_ndjson() {
  [ -z "$NDJSON_PATH" ] && return
  domain_e=$(json_escape "$1")
  cname_e=$(json_escape "$2")
  provider_e=$(json_escape "$3")
  status_e=$(json_escape "$4")
  reason_e=$(json_escape "$5")
  printf '{"domain":"%s","cname_target":"%s","provider":"%s","status":"%s","reason":"%s"}\n' \
    "$domain_e" "$cname_e" "$provider_e" "$status_e" "$reason_e" >> "$NDJSON_PATH"
}

emit_result() {
  # fan-out to console + CSV + NDJSON
  domain="$1"; cname="$2"; provider="$3"; status="$4"; reason="$5"
  print_human "$provider" "$status" "$reason"
  emit_csv "$domain" "$cname" "$provider" "$status" "$reason"
  emit_ndjson "$domain" "$cname" "$provider" "$status" "$reason"
}

# ---------- main ----------
echo "🔍 Starting scan for dangling DNS records..."
echo "----------------------------------------"

# shellcheck disable=SC2162
while IFS= read -r DOMAIN || [ -n "$DOMAIN" ]; do
  DOMAIN=$(printf %s "$DOMAIN" | tr -d '[:space:]')
  [ -z "$DOMAIN" ] && continue
  case "$DOMAIN" in \#*) continue ;; esac

  echo "[*] Checking domain: $DOMAIN"

  CNAMES=$(dig +time=2 +tries=1 +short CNAME "$DOMAIN" 2>/dev/null | sed 's/\.$//')
  if [ -z "$CNAMES" ]; then
    echo "    -> No CNAME record found. Skipping."
    echo "----------------------------------------"
    continue
  fi

  echo "$CNAMES" | while IFS= read -r TARGET || [ -n "$TARGET" ]; do
    [ -z "$TARGET" ] && continue
    NORM_TGT=$(normalize_host "$TARGET")
    echo "    -> CNAME target: $NORM_TGT"

    provider=$(detect_provider "$NORM_TGT")

    case "$provider" in
      AWS_S3)
        bucket="$(extract_s3_bucket "$NORM_TGT")"
        if [ -z "$bucket" ]; then
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "UNKNOWN" "Could not extract bucket from target"
        else
          AWS_OUTPUT=$(aws s3 ls "s3://$bucket" --no-sign-request 2>&1 || true)
          if echo "$AWS_OUTPUT" | grep -qi 'NoSuchBucket'; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "Bucket '$bucket' does not exist and may be claimable"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT VULNERABLE" "Bucket '$bucket' exists (or not listable anonymously)"
          fi
          if command -v curl >/dev/null 2>&1; then
            HDRS=$(http_head "$DOMAIN")
            printf %s "$HDRS" | grep -qiE 'NoSuchBucket|NoSuchWebsiteConfiguration' && \
              echo "       -> HTTP hint: S3 error visible on $DOMAIN"
          fi
        fi
        ;;

      GITHUB_PAGES)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "There isn't a GitHub Pages site here"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "GitHub Pages default 'no site' page"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "GitHub Pages present; check repo/user ownership"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Needs HTTP probe (curl not found)"
        fi
        ;;

      HEROKU)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "No such app"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "Heroku shows 'No such app' for this hostname"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Heroku present; verify domain binding"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Needs HTTP probe (curl not found)"
        fi
        ;;

      FASTLY)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "Fastly error: unknown domain"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "Fastly reports unknown domain (no service bound)"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Fastly present; no default unknown-domain response"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTP probe (curl not found)"
        fi
        ;;

      NETLIFY)
        if command -v curl >/dev/null 2>&1; then
          HDRS=$(http_head "$DOMAIN"); BODY=$(http_body "$DOMAIN")
          if echo "$HDRS$BODY " | tr -d '\r' | grep -qi "not found"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Netlify returns 404; modern Netlify requires DNS verification"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Netlify present; manual check needed"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTP probe (curl not found)"
        fi
        ;;

      VERCEL)
        if command -v curl >/dev/null 2>&1; then
          HDRS=$(http_head "$DOMAIN"); BODY=$(http_body "$DOMAIN")
          if printf %s "$HDRS" | grep -qi "x-vercel-id"; then
            if echo "$BODY" | grep -qiE "DEPLOYMENT_NOT_FOUND|PROJECT_NOT_FOUND"; then
              emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Vercel default error; check if project unclaimed"
            else
              emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Vercel present; non-default content"
            fi
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Could not fingerprint Vercel headers"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTP probe (curl not found)"
        fi
        ;;

      SHOPIFY)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "Sorry, this shop is currently unavailable"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "EDGE CASE" "Legacy Shopify page; modern takeover usually not possible"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT VULNERABLE" "Shopify requires merchant portal control"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTP probe (curl not found)"
        fi
        ;;

      SQUARESPACE)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "No Such Site at This Address"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "Squarespace default 'no such site' page"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Squarespace present; verify if domain unbound"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Needs HTTP probe (curl not found)"
        fi
        ;;

      TUMBLR)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "There's nothing here"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "VULNERABLE" "Tumblr default unconfigured page"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Tumblr present; manual verification needed"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Needs HTTP probe (curl not found)"
        fi
        ;;

      WORDPRESS_COM)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "Do you want to register"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "WordPress.com domain not registered message"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "WordPress.com present; usually requires site ownership"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTP probe (curl not found)"
        fi
        ;;

      AZURE_APPSERVICE)
        if command -v curl >/dev/null 2>&1; then
          BODY=$(http_body "$DOMAIN")
          if echo "$BODY" | grep -qi "404 Web Site not found"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Default App Service 404; if app name free, could be claimed"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "App Service present; no default 404"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "POTENTIALLY VULNERABLE" "Needs HTTP probe (curl not found)"
        fi
        ;;

      AZURE_STORAGE_STATIC)
        if command -v curl >/dev/null 2>&1; then
          H2=$(curl -sI --max-time 6 "https://$NORM_TGT" 2>/dev/null || true)
          if echo "$H2 " | tr -d '\r' | grep -qi "x-ms-error-code: ResourceNotFound"; then
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT VULNERABLE" "Storage account exists (resource missing)"
          else
            emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Account existence unclear; check in Azure"
          fi
        else
          emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "Needs HTTPS probe (curl not found)"
        fi
        ;;

      CLOUDFRONT)
        emit_result "$DOMAIN" "$NORM_TGT" "$provider" "NOT CLEAR" "CloudFront uses distributions; dangling CNAME alone isn't enough—manual review required (need distribution ownership)"
        ;;

      *)
        emit_result "$DOMAIN" "$NORM_TGT" "$provider" "UNKNOWN" "Unrecognized provider or pattern; add a matcher"
        ;;
    esac
  done

  echo "----------------------------------------"
done < "$DOMAINS_FILE"

echo "✅ Scan complete."