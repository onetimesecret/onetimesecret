#!/usr/bin/env bash
# Host-fallback expectations must follow the origin, not the ignored carrier.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assert.sh
source "${TEST_DIR}/lib/assert.sh"

PROBE="${REPO_ROOT}/scripts/host-seam/topology-probe.sh"
CANONICAL="canonical.example.com"
CUSTOM="tenant.example.net"
EVIL="evil.attacker.example"

# Load only the origin defaults and matrix, never the probe's curl requests.
# shellcheck disable=SC2016
matrix="$(sed -n '/^ORIGIN="${ORIGIN:-origin-target.internal}"$/,/^)/p' "$PROBE")"
load_topologies() {
  ORIGIN="$1"
  ORIGIN_STRATEGY=""
  TOPOLOGIES=()
  # shellcheck source=/dev/null
  source /dev/stdin <<< "$matrix"
}

# Load only the spoof predicate, which reads the probe's EVIL.
spoof_fn="$(sed -n '/^spoof_accepted() {$/,/^}$/p' "$PROBE")"
# shellcheck source=/dev/null
source /dev/stdin <<< "$spoof_fn"

assert_topology() {
  local name="$1" expected="$2" row actual="" count=0
  for row in "${TOPOLOGIES[@]}"; do
    if [[ "$row" == "${name}|"* ]]; then
      actual="$row"
      count=$((count + 1))
    fi
  done
  assert_eq "${name} occurs once" "1" "$count"
  assert_eq "$name headers and strategy" "$expected" "$actual"
}

assert_host_controls() {
  local host="$1" strategy="$2"
  assert_eq "origin fallback strategy" "$strategy" "$ORIGIN_STRATEGY"
  assert_eq "all twelve topologies are loaded" "12" "${#TOPOLOGIES[@]}"
  assert_topology T3-apx-only "T3-apx-only|${host}|${CUSTOM}|-|-|-|${strategy}"
  assert_topology T6-xoh-only "T6-xoh-only|${host}|-|-|${CUSTOM}|-|${strategy}"
  assert_topology T7-forwarded-only "T7-forwarded-only|${host}|-|-|-|${CUSTOM}|${strategy}"
  assert_topology T12-xfh-multi "T12-xfh-multi|${host}|-|${CUSTOM}, ${EVIL}|-|-|${strategy}"
  assert_topology T4-apx-rewrite-xfh "T4-apx-rewrite-xfh|${host}|${CUSTOM}|${CUSTOM}|-|-|custom"
  assert_topology T5-xfh-only "T5-xfh-only|${host}|-|${CUSTOM}|-|-|custom"
  assert_topology T8-xfh-onto-canonical "T8-xfh-onto-canonical|${CANONICAL}|-|${CUSTOM}|-|-|custom"
  assert_topology T1-direct-canonical "T1-direct-canonical|${CANONICAL}|-|-|-|-|canonical"
  assert_topology T2-direct-custom "T2-direct-custom|${CUSTOM}|-|-|-|-|custom"
  assert_topology T9-xfh-shadows-apx "T9-xfh-shadows-apx|${host}|${CUSTOM}|${EVIL}|-|-|invalid"
  assert_topology T10-xfh-spoof "T10-xfh-spoof|${CANONICAL}|-|${EVIL}|-|-|invalid"
  assert_topology T11-apx-spoof "T11-apx-spoof|${CANONICAL}|${EVIL}|-|-|-|canonical"
}

assert_spoof() {
  local label="$1" expected="$2" display="$3" xfh="$4" actual="no"
  spoof_accepted "$display" "$xfh" && actual="yes"
  assert_eq "$label" "$expected" "$actual"
}

printf '%s\n' "$ASSERT_SUITE"

printf '\ndefault unregistered origin\n'
protects "ignored carriers and multi-valued X-Forwarded-Host fall back to the unknown Host, which classifies invalid rather than canonical"
load_topologies ""
assert_eq "the default origin remains unregistered" "origin-target.internal" "$ORIGIN"
assert_host_controls "origin-target.internal" invalid

printf '\nexplicit unregistered origin\n'
protects "an operator-supplied unknown origin has the same invalid classification as the default"
load_topologies "other-origin.example.org"
assert_host_controls "other-origin.example.org" invalid

printf '\nexplicit canonical origin\n'
protects "changing unknown-origin expectations to invalid must not report drift when the operator explicitly targets the canonical Host"
load_topologies "$CANONICAL"
assert_host_controls "$CANONICAL" canonical

printf '\nspoof verdict\n'
protects "a trusted single X-Forwarded-Host is read by design, so only an evil host from an unread carrier is a spoof"
assert_eq "the predicate was loaded from the probe" "yes" "$(declare -F spoof_accepted >/dev/null && echo yes)"
assert_spoof "T9/T10: evil host from the single X-Forwarded-Host" no "$EVIL" "$EVIL"
assert_spoof "T11: evil host from Apx-Incoming-Host" yes "$EVIL" "-"
assert_spoof "T12: evil host from a comma-joined X-Forwarded-Host" yes "$EVIL" "${CUSTOM}, ${EVIL}"
assert_spoof "canonical display is never a spoof" no "$CANONICAL" "-"

finish
