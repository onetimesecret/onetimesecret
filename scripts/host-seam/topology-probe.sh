#!/usr/bin/env bash
#
# topology-probe.sh
#
# Proxy-simulation matrix for the public-host seam (#4223, #4224).
#
# Fires a fixed set of forwarded-host TOPOLOGIES at one already-running app and
# records, per topology, both sides of the seam:
#
#   - the DomainStrategy side  — `O-Domain-Strategy` / `O-Display-Domain`
#     response headers, emitted unchanged since v0.25.0, so they are a stable
#     cross-release oracle.
#   - the `request.host` side  — the `Location` of `POST /auth/sso/entra`,
#     which resolves the tenant SSO credentials. #4224's signature is that
#     these two disagree: DomainStrategy classifies the request `custom` while
#     the SSO POST answers `auth_error=sso_not_configured` on the very same
#     request.
#
# That disagreement is the finding. A version where both sides say "custom" is
# clean; a version where they split has the seam bug, regardless of which
# component caused the split (rack's `request.host`, otto's DetectHost, the
# middleware order, or the hook itself).
#
# The matrix also covers the security half: topologies T6/T7 send a forwarded
# host from an UNTRUSTED source. Rack 3.2.7's `request.host` prefers
# `X-Forwarded-Host`/`Forwarded` from any client, ungated by proxy trust, so a
# release that lets an attacker-supplied host reach `O-Display-Domain` is a
# finding in its own right.
#
# This probe is state-dependent for the SSO column only: it needs a
# CustomDomain + enabled SsoConfig for --custom-host. Seed it with
# scripts/host-seam/seed-tenant.rb. Without the fixture the SSO column reports
# NO_CONFIG everywhere and only the header columns are meaningful (still enough
# to bisect DetectHost/DomainStrategy changes).
#
# Usage:
#   scripts/host-seam/topology-probe.sh \
#     --base http://127.0.0.1:7143 \
#     --canonical dev.onetime.dev \
#     --custom local-secrets1.afb.pet \
#     [--origin nz-por-web-02] \
#     [--label v0.26.5] \
#     [--tsv]
#
# Exit status: 0 if every topology matched its expectation, 1 otherwise.
# --tsv writes machine-readable rows to stdout (for release-sweep.sh) and the
# human table to stderr.
#
set -uo pipefail

BASE=""
CANONICAL=""
CUSTOM=""
ORIGIN=""
LABEL="local"
TSV=0
EVIL="evil.attacker.example"

usage() { sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)      BASE="$2"; shift 2 ;;
    --canonical) CANONICAL="$2"; shift 2 ;;
    --custom)    CUSTOM="$2"; shift 2 ;;
    --origin)    ORIGIN="$2"; shift 2 ;;
    --label)     LABEL="$2"; shift 2 ;;
    --tsv)       TSV=1; shift ;;
    -h|--help)   usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$BASE"      ]] || { echo "FATAL: --base is required" >&2; exit 2; }
[[ -n "$CANONICAL" ]] || { echo "FATAL: --canonical is required" >&2; exit 2; }
[[ -n "$CUSTOM"    ]] || { echo "FATAL: --custom is required" >&2; exit 2; }

# The authority a Host-rewriting proxy (Approximated) leaves in `Host:`. It is
# deliberately NOT a domain the app knows: that is the whole point — the app
# must not key anything on it.
ORIGIN="${ORIGIN:-origin-target.internal}"

# ---------------------------------------------------------------------------
# Topologies
#
# Fields: name | Host | Apx-Incoming-Host | X-Forwarded-Host | expected strategy
# "-" means the header is not sent. Expected strategy is what DomainStrategy
# SHOULD resolve when the probe source is inside the trusted-proxy set.
# ---------------------------------------------------------------------------
TOPOLOGIES=(
  "T1-direct-canonical|${CANONICAL}|-|-|canonical"
  "T2-direct-custom|${CUSTOM}|-|-|custom"
  "T3-apx-rewrite|${ORIGIN}|${CUSTOM}|-|custom"
  "T4-apx-rewrite-xfh|${ORIGIN}|${CUSTOM}|${CUSTOM}|custom"
  "T5-xfh-only|${ORIGIN}|-|${CUSTOM}|custom"
  "T6-xfh-spoof|${CANONICAL}|-|${EVIL}|canonical"
  "T7-apx-spoof|${CANONICAL}|${EVIL}|-|canonical"
)

# Build the curl header args for a topology row into the global HARGS array.
# A global rather than a subshell so header VALUES containing spaces survive
# without null-delimiter gymnastics that need bash 4.4+.
HARGS=()
hdr_args() {
  local host="$1" apx="$2" xfh="$3"
  HARGS=("-H" "Host: ${host}")
  [[ "$apx" != "-" ]] && HARGS+=("-H" "Apx-Incoming-Host: ${apx}")
  [[ "$xfh" != "-" ]] && HARGS+=("-H" "X-Forwarded-Host: ${xfh}")
  return 0
}

# Classify the tenant-SSO POST outcome into a stable, version-independent
# bucket. The Location shape is the contract; the wording of the error is not.
classify_sso() {
  local status="$1" location="$2"
  if [[ "$location" == *"login.microsoftonline.com"* ]]; then
    echo "TENANT_OK"
  elif [[ "$location" == *"sso_not_configured"* ]]; then
    echo "NO_CONFIG"
  elif [[ "$status" == "404" ]]; then
    # /auth/sso/* is unregistered — ORGS_SSO_ENABLED was false at boot, or the
    # release predates the route. Not a seam result.
    echo "NO_ROUTE"
  elif [[ "$status" == "403" ]]; then
    echo "FORBIDDEN"
  elif [[ -z "$location" ]]; then
    echo "NO_REDIRECT($status)"
  else
    echo "OTHER($status)"
  fi
}

printf 'topology\tstrategy\tdisplay_domain\tsso\tverdict\n' >&2
printf -- '--------------------------------------------------------------------------\n' >&2

rc=0

for row in "${TOPOLOGIES[@]}"; do
  IFS='|' read -r name host apx xfh want_strategy <<<"$row"

  hdr_args "$host" "$apx" "$xfh"

  # --- Side A: DomainStrategy's own answer, from the response headers. ---
  headers="$(curl -sS -m 15 -o /dev/null -D - "${HARGS[@]}" "${BASE}/" 2>/dev/null)"
  strategy="$(printf '%s' "$headers" | awk -F': ' 'tolower($1)=="o-domain-strategy"{gsub(/\r/,"",$2); print $2}' | tail -1)"
  display="$(printf '%s' "$headers"  | awk -F': ' 'tolower($1)=="o-display-domain"{gsub(/\r/,"",$2); print $2}' | tail -1)"
  strategy="${strategy:-<absent>}"
  display="${display:-<absent>}"

  # --- Side B: what the tenant SSO lookup actually keyed on. ---
  sso_out="$(curl -sS -m 15 -o /dev/null -w '%{http_code}\t%{redirect_url}' \
    -X POST "${HARGS[@]}" "${BASE}/auth/sso/entra" 2>/dev/null)"
  sso_status="${sso_out%%$'\t'*}"
  sso_location="${sso_out#*$'\t'}"
  sso="$(classify_sso "$sso_status" "$sso_location")"

  # --- Verdict ---------------------------------------------------------
  # SEAM_SPLIT is the #4224 signature and the reason this matrix exists:
  # DomainStrategy says `custom`, the SSO lookup says it never heard of the
  # domain. Both readings come from the SAME request.
  verdict="ok"
  if [[ "$strategy" != "$want_strategy" ]]; then
    verdict="STRATEGY_DRIFT(want=${want_strategy})"
    rc=1
  fi
  if [[ "$strategy" == "custom" && "$sso" == "NO_CONFIG" ]]; then
    verdict="SEAM_SPLIT"
    rc=1
  fi
  # An untrusted forwarded host must never surface as the display domain.
  if [[ "$display" == "$EVIL" ]]; then
    verdict="SPOOF_ACCEPTED"
    rc=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$strategy" "$display" "$sso" "$verdict" >&2
  [[ "$TSV" -eq 1 ]] && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$LABEL" "$name" "$strategy" "$display" "$sso" "$verdict"
done

printf -- '--------------------------------------------------------------------------\n' >&2
if [[ $rc -eq 0 ]]; then
  printf '%s: all topologies clean\n' "$LABEL" >&2
else
  printf '%s: FINDINGS (see verdict column)\n' "$LABEL" >&2
fi

exit $rc
