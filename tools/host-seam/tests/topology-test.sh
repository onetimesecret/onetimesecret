#!/usr/bin/env bash
# The topology probe's matrix loader, origin expectation and grading.
#
# Whether the expectations in tools/host-seam/topologies.psv match what the
# application does is not tested here: host_proxy_matrix_spec.rb sends the same
# file through the mounted stack. This file covers the shell around it, and
# runs the probe end to end against a stand-in curl, because the probe itself
# needs a running app and does not run in CI.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"
# shellcheck source=tools/testsuite/lib/assert.sh
source "${REPO_ROOT}/tools/testsuite/lib/assert.sh"
# shellcheck source=tools/host-seam/topology-lib.sh
source "${REPO_ROOT}/tools/host-seam/topology-lib.sh"

PROBE="${REPO_ROOT}/tools/host-seam/topology-probe.sh"
CANONICAL="canonical.example.com"
CUSTOM="tenant.example.net"
EVIL="evil.attacker.example"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

row_named() {
  local row
  for row in "${TOPOLOGIES[@]}"; do
    [[ "$row" == "$1|"* ]] && printf '%s' "$row"
  done
}

assert_spoof() {
  local label="$1" expected="$2" display="$3" xfh="$4" actual="no"
  spoof_accepted "$display" "$xfh" "$EVIL" && actual="yes"
  assert_eq "$label" "$expected" "$actual"
}

printf '%s\n' "$ASSERT_SUITE"

printf '\nmatrix loader\n'
protects "the probe, this test and the matrix spec read one matrix file; a row the loader drops or leaves half-filled is a topology nobody sends"
TOPOLOGIES=()
load_topologies "$CANONICAL" "$CUSTOM" "origin.example.org" "$EVIL" invalid
assert_eq "the shipped matrix loads" "0" "$?"
assert_eq "all twelve topologies are loaded" "12" "${#TOPOLOGIES[@]}"
assert_eq "no placeholder survives" "" "$(printf '%s\n' "${TOPOLOGIES[@]}" | grep -F '{' || true)"
assert_eq "names are unique" "12" "$(printf '%s\n' "${TOPOLOGIES[@]}" | cut -d'|' -f1 | sort -u | wc -l | tr -d ' ')"
assert_eq "{origin} and {origin_strategy} are filled separately" \
  "T3-apx-only|origin.example.org|${CUSTOM}|-|-|-|invalid" "$(row_named T3-apx-only)"
assert_eq "a header value with a comma and a space survives" \
  "T12-xfh-multi|origin.example.org|-|${CUSTOM}, ${EVIL}|-|-|invalid" "$(row_named T12-xfh-multi)"

protects "the matrix is data: a line that is not a seven-field row stops the probe instead of being run or skipped"
printf 'T1-ok|a|-|-|-|-|canonical\nT2-short|a|-|-|canonical\n' >"${WORK}/short.txt"
load_topologies a b c d invalid "${WORK}/short.txt" 2>/dev/null
assert_eq "a row with too few fields is refused" "1" "$?"
printf 'T1-typo|{cannonical}|-|-|-|-|canonical\n' >"${WORK}/typo.txt"
load_topologies a b c d invalid "${WORK}/typo.txt" 2>/dev/null
assert_eq "an unknown placeholder is refused" "1" "$?"
printf '# only a comment\n\n' >"${WORK}/empty.txt"
load_topologies a b c d invalid "${WORK}/empty.txt" 2>/dev/null
assert_eq "a matrix with no rows is refused" "1" "$?"
load_topologies a b c d invalid "${WORK}/absent.txt" 2>/dev/null
assert_eq "a missing matrix file is refused" "1" "$?"
# shellcheck disable=SC2016
printf 'T1-inert|$(touch "%s/executed")|-|-|-|-|canonical\n' "$WORK" >"${WORK}/inert.txt"
load_topologies a b c d invalid "${WORK}/inert.txt"
assert_eq "a row holding shell syntax is not executed" "no" "$([[ -e "${WORK}/executed" ]] && echo yes || echo no)"

printf '\norigin expectation\n'
protects "a --origin that is the canonical host in another spelling must expect canonical, and an unknown one invalid"
assert_eq "same string" "canonical" "$(predicted_origin_strategy "$CANONICAL" "$CANONICAL")"
assert_eq "different case" "canonical" "$(predicted_origin_strategy "Canonical.Example.COM" "$CANONICAL")"
assert_eq "with a port" "canonical" "$(predicted_origin_strategy "${CANONICAL}:8443" "$CANONICAL")"
assert_eq "with a trailing dot" "canonical" "$(predicted_origin_strategy "${CANONICAL}." "$CANONICAL")"
assert_eq "port on the canonical side" "canonical" "$(predicted_origin_strategy "$CANONICAL" "${CANONICAL}:7143")"
assert_eq "an unrelated host" "invalid" "$(predicted_origin_strategy "origin-target.internal" "$CANONICAL")"
assert_eq "www. is not decided from the name" "invalid" "$(predicted_origin_strategy "www.${CANONICAL}" "$CANONICAL")"

printf '\nspoof verdict\n'
protects "a single X-Forwarded-Host is the carrier the app selects, so only an evil host from an unread carrier is a spoof"
assert_spoof "T9/T10: evil host from the single X-Forwarded-Host" no "$EVIL" "$EVIL"
assert_spoof "T11: evil host from Apx-Incoming-Host" yes "$EVIL" "-"
assert_spoof "T12: evil host from a comma-joined X-Forwarded-Host" yes "$EVIL" "${CUSTOM}, ${EVIL}"
assert_spoof "canonical display is never a spoof" no "$CANONICAL" "-"

# --- The probe, end to end, against a stand-in curl ---------------------------
# The stand-in answers the way the #4384 contract says the app does: a single
# X-Forwarded-Host wins, otherwise Host; the canonical host and its subdomains
# classify canonical, the tenant custom, anything else invalid. STUB_READS_APX=1
# makes it read Apx-Incoming-Host first, the pre-#4384 behaviour.
mkdir -p "${WORK}/bin"
cat >"${WORK}/bin/curl" <<'STUB'
#!/usr/bin/env bash
host="" xfh="" apx="" mode="code"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H)
      case "$2" in
        "Host: "*) host="${2#Host: }" ;;
        "X-Forwarded-Host: "*) xfh="${2#X-Forwarded-Host: }" ;;
        "Apx-Incoming-Host: "*) apx="${2#Apx-Incoming-Host: }" ;;
      esac
      shift 2 ;;
    -D) mode="headers"; shift 2 ;;
    -X) mode="sso"; shift 2 ;;
    -m | -o | -w) shift 2 ;;
    *) shift ;;
  esac
done
resolved="$host"
[[ -n "$xfh" && "$xfh" != *,* ]] && resolved="$xfh"
[[ "${STUB_READS_APX:-0}" == "1" && -n "$apx" ]] && resolved="$apx"
resolved="$(printf '%s' "${resolved%%:*}" | tr '[:upper:]' '[:lower:]')"
case "$resolved" in
  "$STUB_CANONICAL" | *".$STUB_CANONICAL") strategy="canonical" ;;
  "$STUB_CUSTOM") strategy="custom" ;;
  *) strategy="invalid" ;;
esac
case "$mode" in
  headers) printf 'HTTP/1.1 200 OK\r\nO-Domain-Strategy: %s\r\nO-Display-Domain: %s\r\n\r\n' "$strategy" "$resolved" ;;
  sso)
    case "$strategy" in
      custom) printf '302\thttps://login.microsoftonline.com/host-seam-tenant/oauth2/v2.0/authorize' ;;
      canonical) printf '302\thttps://login.microsoftonline.com/platform/oauth2/v2.0/authorize' ;;
      *) printf '302\thttps://%s/signin?auth_error=sso_not_configured' "$resolved" ;;
    esac ;;
  *) printf '200' ;;
esac
STUB
chmod +x "${WORK}/bin/curl"

run_probe() { # [VAR=value ...] -- <probe args>; sets PROBE_OUT and PROBE_RC
  local -a env_args=()
  while [[ "$1" != "--" ]]; do env_args+=("$1"); shift; done
  shift
  PROBE_OUT="$(env PATH="${WORK}/bin:${PATH}" STUB_CANONICAL="$CANONICAL" STUB_CUSTOM="$CUSTOM" \
    "${env_args[@]}" bash "$PROBE" --base http://stub.invalid --canonical "$CANONICAL" --custom "$CUSTOM" "$@" 2>&1)"
  PROBE_RC=$?
}

verdict_of() { printf '%s\n' "$PROBE_OUT" | awk -v name="$1" '$1==name {print $NF}'; }
want_of() { printf '%s\n' "$PROBE_OUT" | awk -v name="$1" '$1==name {print $3}'; }

printf '\nprobe against a contract-following app\n'
protects "the probe must exit 0 on an app that follows the single-header contract, or a clean release reads as a finding"
run_probe --
assert_eq "exit status, default origin" "0" "$PROBE_RC"
assert_contains "summary line" "all topologies clean" "$PROBE_OUT"
assert_eq "T3 expects invalid for the default origin" "invalid" "$(want_of T3-apx-only)"
assert_eq "T9 is ok with the evil host displayed" "ok" "$(verdict_of T9-xfh-shadows-apx)"

protects "an --origin that is the canonical host in another spelling, or a host the app classifies canonical, must not report drift"
run_probe -- --origin "Canonical.Example.COM:8443"
assert_eq "exit status, canonical origin in another case with a port" "0" "$PROBE_RC"
assert_eq "T3 expects canonical" "canonical" "$(want_of T3-apx-only)"
run_probe -- --origin "www.${CANONICAL}"
assert_eq "exit status, www. origin" "0" "$PROBE_RC"
assert_eq "T3 expects what the direct request to www. resolved" "canonical" "$(want_of T3-apx-only)"
assert_contains "the measured expectation is announced" "resolved 'canonical'" "$PROBE_OUT"
run_probe -- --origin "other-origin.example.org"
assert_eq "exit status, explicit unregistered origin" "0" "$PROBE_RC"
assert_eq "T12 expects invalid" "invalid" "$(want_of T12-xfh-multi)"

printf '\nprobe against an app that reads Apx-Incoming-Host\n'
protects "measuring the origin must not hide a carrier that is read: the row moves away from what the bare Host resolves to"
run_probe STUB_READS_APX=1 -- --origin "www.${CANONICAL}"
assert_eq "exit status" "1" "$PROBE_RC"
assert_eq "T3 drifts to custom" "STRATEGY_DRIFT(want=canonical)" "$(verdict_of T3-apx-only)"
assert_eq "T11 reports the spoof" "SPOOF_ACCEPTED" "$(verdict_of T11-apx-spoof)"
assert_eq "T5 is unaffected" "ok" "$(verdict_of T5-xfh-only)"

finish
