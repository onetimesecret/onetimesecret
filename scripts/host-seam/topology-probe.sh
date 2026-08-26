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
# scripts/host-seam/seed-tenant.rb. A direct-request control detects the
# missing fixture (a request with Host: --custom and no forwarded headers has
# no seam, so NO_CONFIG there means nothing is configured) and reports
# FIXTURE_MISSING instead of SEAM_SPLIT; only the header columns are
# meaningful in that state (still enough to bisect DetectHost/DomainStrategy
# changes).
#
# Usage:
#   scripts/host-seam/topology-probe.sh \
#     --base http://127.0.0.1:7143 \
#     --canonical dev.onetime.dev \
#     --custom local-secrets1.afb.pet \
#     [--origin origin-target.internal] \
#     [--tenant-id host-seam-tenant] \
#     [--label v0.26.5] \
#     [--tsv]
#
# --tenant-id must match the SsoConfig the fixture seeded. It is what separates
# TENANT_OK from PLATFORM_FALLBACK: both redirect to login.microsoftonline.com,
# and only the tenant id in the authorize path says whose credentials were
# injected.
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
TENANT_ID="host-seam-tenant"
EVIL="evil.attacker.example"

usage() { sed -n '2,56p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
# NOTE: usage() prints the header comment block; keep its sed range in sync
# when the block above grows or shrinks.

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)      BASE="$2"; shift 2 ;;
    --canonical) CANONICAL="$2"; shift 2 ;;
    --custom)    CUSTOM="$2"; shift 2 ;;
    --origin)    ORIGIN="$2"; shift 2 ;;
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --label)     LABEL="$2"; shift 2 ;;
    --tsv)       TSV=1; shift ;;
    -h|--help)   usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$BASE"      ]] || { echo "FATAL: --base is required" >&2; exit 2; }
[[ -n "$CANONICAL" ]] || { echo "FATAL: --canonical is required" >&2; exit 2; }
[[ -n "$CUSTOM"    ]] || { echo "FATAL: --custom is required" >&2; exit 2; }

# Fast preflight so an unreachable base fails once with a clear message,
# instead of repeating NO_REDIRECT(000) / <absent> across every topology.
base_probe_code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "${BASE}/" 2>/dev/null || true)"
if [[ "$base_probe_code" == "000" ]]; then
  echo "FATAL: cannot reach --base ${BASE} (curl status 000)" >&2
  echo "hint: check app is running, scheme/port are correct, and local networking/proxy/TLS setup" >&2
  exit 2
fi

# The authority a Host-rewriting proxy (Approximated) leaves in `Host:` — the
# "inbound target". In production this is a real platform host such as
# `nz.onetime.co`; the default here is deliberately a domain the app has never
# heard of, because that is the reproducible case. T8 covers the variant where
# the inbound target happens to BE the canonical host, which routes differently.
ORIGIN="${ORIGIN:-origin-target.internal}"

# ---------------------------------------------------------------------------
# Topologies
#
# Fields: name|Host|Apx-Incoming-Host|X-Forwarded-Host|X-Original-Host|Forwarded|expected strategy
# "-" means the header is not sent. Expected strategy is what DomainStrategy
# SHOULD resolve when the probe source is inside the trusted-proxy set.
#
# All four forwarded carriers are covered because production demonstrably uses
# more than one: the 2026-08-20 capture shows DetectHost resolving one host
# `via HTTP_APX_INCOMING_HOST` and another `via HTTP_X_ORIGINAL_HOST` in the
# same window. A harness that only exercised Apx-Incoming-Host would miss half
# the live ingress paths.
#
# DetectHost precedence (detect_host.rb HEADER_PRECEDENCE) is:
#   X-Forwarded-Host > Apx-Incoming-Host > X-Original-Host > Forwarded > Host
# ---------------------------------------------------------------------------
TOPOLOGIES=(
  "T1-direct-canonical|${CANONICAL}|-|-|-|-|canonical"
  "T2-direct-custom|${CUSTOM}|-|-|-|-|custom"
  # T3 is the production shape: Host rewritten to a non-canonical inbound
  # target, real host in Apx-Incoming-Host. This is the #4224 reproduction.
  "T3-apx-rewrite|${ORIGIN}|${CUSTOM}|-|-|-|custom"
  "T4-apx-rewrite-xfh|${ORIGIN}|${CUSTOM}|${CUSTOM}|-|-|custom"
  "T5-xfh-only|${ORIGIN}|-|${CUSTOM}|-|-|custom"
  "T6-xoh-only|${ORIGIN}|-|-|${CUSTOM}|-|custom"
  "T7-forwarded-only|${ORIGIN}|-|-|-|${CUSTOM}|custom"
  # T8: the inbound target IS the canonical host. A consumer reading the raw
  # Host header lands in the `canonical_domain?` branch of the omniauth setup
  # hook (platform-level request) instead of the tenant-fallback branch, so it
  # fails QUIETLY — platform credentials rather than `sso_not_configured`.
  # Only the tenant id in the authorize URL distinguishes the two.
  "T8-apx-onto-canonical|${CANONICAL}|${CUSTOM}|-|-|-|custom"
  # T9: legitimate Apx-Incoming-Host from the edge, attacker-supplied
  # X-Forwarded-Host riding along. XFH outranks Apx in HEADER_PRECEDENCE and
  # DetectHost breaks on the first SYNTACTICALLY valid domain name — it does
  # not check whether the domain is known — so `evil.attacker.example` wins the
  # carrier race and Apx-Incoming-Host is never read.
  #
  # DomainStrategy then rejects the unknown domain and falls back to canonical,
  # so the attacker does NOT get to impersonate a tenant. What they get is
  # DENIAL: the tenant's own SSO silently degrades to canonical for as long as
  # they can attach the header. Expected strategy is therefore `canonical` —
  # correct app behaviour, and a finding about the EDGE, which must strip
  # inbound X-Forwarded-Host. This is the carrier-sanitization half of #4223.
  #
  # If display_domain ever comes back as the evil host instead, that is
  # SPOOF_ACCEPTED and a different, worse bug.
  "T9-xfh-shadows-apx|${ORIGIN}|${CUSTOM}|${EVIL}|-|-|canonical"
  "T10-xfh-spoof|${CANONICAL}|-|${EVIL}|-|-|canonical"
  "T11-apx-spoof|${CANONICAL}|${EVIL}|-|-|-|canonical"
)

# Build the curl header args for a topology row into the global HARGS array.
# A global rather than a subshell so header VALUES containing spaces survive
# without null-delimiter gymnastics that need bash 4.4+.
HARGS=()
hdr_args() {
  local host="$1" apx="$2" xfh="$3" xoh="$4" fwd="$5"
  HARGS=("-H" "Host: ${host}")
  [[ "$apx" != "-" ]] && HARGS+=("-H" "Apx-Incoming-Host: ${apx}")
  [[ "$xfh" != "-" ]] && HARGS+=("-H" "X-Forwarded-Host: ${xfh}")
  [[ "$xoh" != "-" ]] && HARGS+=("-H" "X-Original-Host: ${xoh}")
  [[ "$fwd" != "-" ]] && HARGS+=("-H" "Forwarded: host=${fwd}")
  return 0
}

# Classify the tenant-SSO POST outcome into a stable, version-independent
# bucket. The Location shape is the contract; the wording of the error is not.
#
# TENANT_OK requires the fixture's TENANT ID in the authorize path, not merely
# the IdP hostname. The platform fallback redirects to login.microsoftonline.com
# too — with the platform tenant. Matching on the hostname alone would score the
# T8 failure (Host rewritten onto the canonical host, hook takes the
# platform-level branch) as clean.
classify_sso() {
  local status="$1" location="$2"
  if [[ "$location" == *"login.microsoftonline.com/${TENANT_ID}/"* ]]; then
    echo "TENANT_OK"
  elif [[ "$location" == *"login.microsoftonline.com"* ]]; then
    echo "PLATFORM_FALLBACK"
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

# --- Fixture control --------------------------------------------------------
# A DIRECT request to the custom host has no seam: Host and public host are
# the same string, so the tenant lookup finds the SsoConfig regardless of
# which side of the seam it reads. If it still answers sso_not_configured
# here, no enabled SsoConfig exists for --custom and every would-be SEAM_SPLIT
# in the matrix is fixture absence, not the #4224 split. Report that state as
# FIXTURE_MISSING so it cannot masquerade as the production finding.
FIXTURE_MISSING=0
control_out="$(curl -sS -m 15 -o /dev/null -w '%{http_code}\t%{redirect_url}' \
  -X POST -H "Host: ${CUSTOM}" "${BASE}/auth/sso/entra" 2>/dev/null)"
control_sso="$(classify_sso "${control_out%%$'\t'*}" "${control_out#*$'\t'}")"
if [[ "$control_sso" == "NO_CONFIG" ]]; then
  FIXTURE_MISSING=1
  echo "WARN: no enabled SsoConfig answers for ${CUSTOM} on a direct request." >&2
  echo "      SSO seam verdicts are reported as FIXTURE_MISSING. Seed with:" >&2
  echo "      HOST_SEAM_DOMAIN=${CUSTOM} bin/ots console < scripts/host-seam/seed-tenant.rb" >&2
fi

# --- Strategy control --------------------------------------------------------
# DomainStrategy must classify that same direct request as `custom`. When it
# does not, every strategy expectation in the matrix grades a side of the seam
# that cannot answer: either --custom is not a registered CustomDomain, or the
# domains feature is off in the app under test (DOMAINS_ENABLED defaults to
# false). The SSO control above disambiguates — a lookup that found tenant
# credentials proves the domain is registered, leaving only the feature toggle.
STRATEGY_UNTESTABLE=0
control_strategy="$(curl -sS -m 15 -o /dev/null -D - -H "Host: ${CUSTOM}" "${BASE}/" 2>/dev/null \
  | awk -F': ' 'tolower($1)=="o-domain-strategy"{gsub(/\r/,"",$2); print $2}' | tail -1)"
if [[ "${control_strategy:-<absent>}" != "custom" ]]; then
  STRATEGY_UNTESTABLE=1
  echo "WARN: a direct request to ${CUSTOM} resolved strategy '${control_strategy:-<absent>}', not 'custom'." >&2
  if [[ "$control_sso" == "TENANT_OK" ]]; then
    echo "      The SSO lookup found tenant credentials for it, so the domain IS registered:" >&2
    echo "      the domains feature is off in the app under test. Set DOMAINS_ENABLED=true." >&2
  else
    echo "      Either ${CUSTOM} is not a registered CustomDomain, or the domains feature" >&2
    echo "      is off in the app under test (DOMAINS_ENABLED)." >&2
  fi
  echo "      Strategy/seam verdicts are reported as UNTESTABLE(strategy_control)." >&2
fi

ROW_FMT='%-24s %-12s %-12s %-28s %-22s %s\n'
print_sep() {
  printf -- '---------------------------------------------------------------------------------------------------------------------\n' >&2
}

printf "$ROW_FMT" "topology" "strategy" "want" "display_domain" "sso" "verdict" >&2
print_sep

rc=0

for row in "${TOPOLOGIES[@]}"; do
  IFS='|' read -r name host apx xfh xoh fwd want_strategy <<<"$row"

  hdr_args "$host" "$apx" "$xfh" "$xoh" "$fwd"

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
  if [[ "$STRATEGY_UNTESTABLE" -eq 1 ]]; then
    # The control proved DomainStrategy cannot say `custom` for --custom at
    # all, so grading rows against custom/canonical expectations would report
    # drift (or vacuous passes) about a switched-off feature.
    verdict="UNTESTABLE(strategy_control)"
    rc=1
  elif [[ "$strategy" != "$want_strategy" ]]; then
    verdict="STRATEGY_DRIFT(want=${want_strategy})"
    rc=1
  fi
  # Two ways the split shows up, depending on what the inbound target is:
  #   NO_CONFIG          the raw Host is an unknown domain -> tenant-fallback
  #                      branch (the loud failure, and the production one:
  #                      `omniauth_tenant_no_config` on nz.onetime.co while the
  #                      same request's DomainStrategy said custom/secret.asi.nz)
  #   PLATFORM_FALLBACK  the raw Host is the canonical host -> the hook's
  #                      `canonical_domain?` branch injects PLATFORM credentials
  #                      and the user reaches an IdP, just the wrong one. Silent
  #                      unless the tenant id is checked.
  if [[ "$STRATEGY_UNTESTABLE" -eq 0 && "$strategy" == "custom" && ( "$sso" == "NO_CONFIG" || "$sso" == "PLATFORM_FALLBACK" ) ]]; then
    if [[ "$FIXTURE_MISSING" -eq 1 ]]; then
      # The direct-request control already proved nothing is configured for
      # --custom, so this row's SSO outcome is uninterpretable — it cannot
      # distinguish "seam broken" from "nothing seeded".
      verdict="FIXTURE_MISSING"
    else
      verdict="SEAM_SPLIT(${sso})"
    fi
    rc=1
  fi
  # An untrusted forwarded host must never surface as the display domain.
  if [[ "$display" == "$EVIL" ]]; then
    verdict="SPOOF_ACCEPTED"
    rc=1
  fi

  printf "$ROW_FMT" "$name" "$strategy" "$want_strategy" "$display" "$sso" "$verdict" >&2
  [[ "$TSV" -eq 1 ]] && printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$LABEL" "$name" "$strategy" "$display" "$sso" "$verdict"
done

print_sep
if [[ $rc -eq 0 ]]; then
  printf '%s: all topologies clean\n' "$LABEL" >&2
else
  printf '%s: FINDINGS (see verdict column)\n' "$LABEL" >&2
fi

exit $rc
