#!/usr/bin/env bash
# derive-governance.sh — derive translation governance ON DEMAND (no-vendor model;
# translation-rules ADR-005, onetimesecret #3510). Replaces the old, committing
# sync-resolved.sh.
#
# Emits the per-locale resolved governance (.resolved/<locale>.json) and the
# translator guides (guides/for-translators/<locale>.md) into the GITIGNORED cache
# generated/i18n/ — never committed. The translation orchestration reads
# generated/i18n/.resolved/<locale>.json; there is no vendored copy under locales/.
#
# Source of truth is onetimesecret/translation-rules at the SINGLE canonical pin
# recorded as TRANSLATION_RULES_REF in .github/workflows/resolved-derive-gate.yml
# — the exact same ref the CI derive gate resolves. We check it out and resolve it
# to a concrete commit, so local and CI output match byte-for-byte.
#
# Usage:
#   locales/scripts/derive-governance.sh [--print-ref] [RULES_DIR]
#
#   --print-ref  Print the canonical translation-rules ref this run would derive
#                at (from the gate, or RULES_REF) and exit — no clone, no derive.
#                A cheap, offline pin-readability check for CI and humans.
#   RULES_DIR  A translation-rules checkout used READ-ONLY as the authority
#              (default: .translation-rules, gitignored). Cloned if absent;
#              fetched + checked out (detached) to the pin if present. Treat it as
#              a throwaway authority checkout, not your working clone.
#   RULES_REPO Override the clone URL (default: the public translation-rules repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

GATE=.github/workflows/resolved-derive-gate.yml
PRINT_REF=0
if [ "${1:-}" = "--print-ref" ]; then PRINT_REF=1; shift; fi
RULES_DIR="${1:-.translation-rules}"
RULES_REPO="${RULES_REPO:-https://github.com/onetimesecret/translation-rules.git}"
EMIT_DIR="$ROOT/generated/i18n"

# --- read the single canonical pin (TRANSLATION_RULES_REF) from the gate ------
# The canonical data pin is the human-readable TRANSLATION_RULES_REF value (a
# vX.Y.Z release tag, or a 40-hex SHA), kept in lockstep across the derive gates
# by Renovate (#38) and resolved at run time by the CI derive action. (The `uses:`
# action digest is a separate supply-chain axis we don't read here.) An optional
# RULES_REF env var overrides it — parity with the gate's per-run dispatch/variable
# override — to dry-run a candidate translation-rules release locally.
[ -f "$GATE" ] || { echo "error: $GATE not found (run from the app repo)" >&2; exit 1; }
PIN="${RULES_REF:-}"
if [ -z "$PIN" ]; then
  # Read the first real (non-comment) assignment: anchoring at line start with
  # only leading whitespace skips commented-out examples (# TRANSLATION_RULES_REF:
  # ...); optional quotes match the Renovate customManager; the value is a vX.Y.Z
  # tag or a 40-hex SHA (either case, mirroring the shape-check below).
  PIN="$(grep -oE "^[[:space:]]*TRANSLATION_RULES_REF:[[:space:]]*[\"']?(v[0-9]+\.[0-9]+\.[0-9]+|[0-9a-fA-F]{40})" "$GATE" \
        | grep -oE "(v[0-9]+\.[0-9]+\.[0-9]+|[0-9a-fA-F]{40})" | head -n1 || true)"
fi
[ -n "$PIN" ] || { echo "error: could not read TRANSLATION_RULES_REF from $GATE (set RULES_REF to override)" >&2; exit 1; }
# Shape-check before use, mirroring the gate's resolve step: 40-hex SHA or vX.Y.Z.
[[ "$PIN" =~ ^([0-9a-fA-F]{40}|v[0-9]+\.[0-9]+\.[0-9]+)$ ]] \
  || { echo "error: invalid translation-rules ref '$PIN' (want 40-hex SHA or vX.Y.Z)" >&2; exit 1; }
if [ -n "${RULES_REF:-}" ]; then PIN_SRC="RULES_REF override"; else PIN_SRC="$GATE"; fi
# --print-ref: emit just the resolved ref on stdout and stop before any network.
if [ "$PRINT_REF" = 1 ]; then echo "$PIN"; exit 0; fi
echo "derive-governance: canonical ref = $PIN (from $PIN_SRC)"

# --- ensure a translation-rules authority checkout at the pin ----------------
if [ ! -e "$RULES_DIR/.git" ]; then
  echo "derive-governance: cloning translation-rules -> $RULES_DIR"
  git clone --quiet "$RULES_REPO" "$RULES_DIR"
fi
# Best-effort fetch (an already-local pin still resolves offline).
git -C "$RULES_DIR" fetch --quiet origin "$PIN" 2>/dev/null \
  || git -C "$RULES_DIR" fetch --quiet --tags 2>/dev/null || true
git -C "$RULES_DIR" checkout --quiet --detach "$PIN" 2>/dev/null || {
  echo "error: ref $PIN unavailable in $RULES_DIR (fetch failed and commit absent)" >&2; exit 1; }

# --- resolve the ref (tag or SHA) to the concrete checked-out commit ----------
# The shared CI derive action stamps _meta.source_commit / _meta.generated_at from
# this exact commit, so we derive from the resolved SHA (not the tag string) to
# keep local output byte-identical to CI.
SHA="$(git -C "$RULES_DIR" rev-parse HEAD)"
[ "$SHA" != "$PIN" ] && echo "derive-governance: resolved $PIN -> $SHA"

# --- deterministic generated_at (committer date of the pin, UTC) -------------
# Matches the CI derive action / old sync-resolved.sh byte-for-byte (TZ=UTC +
# format-local avoids the git %cI +00:00-vs-Z version skew).
GEN_AT="$(TZ=UTC git -C "$RULES_DIR" show -s \
  --date=format-local:'%Y-%m-%dT%H:%M:%S+00:00' --format=%cd "$SHA")"

# --- locate the resolver (rules-root layout uses lib/resolver) ----------------
if   [ -f "$RULES_DIR/lib/resolver/resolve.py" ]; then RESOLVER=lib/resolver/resolve.py
elif [ -f "$RULES_DIR/resolver/resolve.py" ];     then RESOLVER=resolver/resolve.py
else echo "error: resolver not found under $RULES_DIR" >&2; exit 1; fi

# --- derive all governed locales into the ignored cache ----------------------
rm -rf "$EMIT_DIR"
mkdir -p "$EMIT_DIR"
# Run from inside the authority checkout so the resolver finds rules/, base.yaml,
# schema/ via its defaults; write the index to the cache so the checkout stays clean.
( cd "$RULES_DIR" && uv run "$RESOLVER" --all \
    --emit=md,json --emit-dir "$EMIT_DIR" \
    --source-commit "$SHA" --generated-at "$GEN_AT" \
    --index-path "$EMIT_DIR/index.json" --lint )

n=$(find "$EMIT_DIR/.resolved" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
echo "derive-governance: derived ${n} locale(s) into ${EMIT_DIR#"$ROOT/"}/ (.resolved/ + guides/for-translators/)"
