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
# recorded in .github/workflows/resolved-derive-gate.yml (PINNED_RULES_REF) — the
# exact same pin the CI derive gate uses, so local and CI output match.
#
# Usage:
#   locales/scripts/derive-governance.sh [RULES_DIR]
#
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
RULES_DIR="${1:-.translation-rules}"
RULES_REPO="${RULES_REPO:-https://github.com/onetimesecret/translation-rules.git}"
EMIT_DIR="$ROOT/generated/i18n"

# --- read the single canonical pin from the derive gate ----------------------
[ -f "$GATE" ] || { echo "error: $GATE not found (run from the app repo)" >&2; exit 1; }
PIN="$(grep -oE 'PINNED_RULES_REF:[[:space:]]*[0-9a-f]{40}' "$GATE" | grep -oE '[0-9a-f]{40}' || true)"
[ -n "$PIN" ] || { echo "error: could not read PINNED_RULES_REF from $GATE" >&2; exit 1; }
echo "derive-governance: canonical pin = $PIN (from $GATE)"

# --- ensure a translation-rules authority checkout at the pin ----------------
if [ ! -e "$RULES_DIR/.git" ]; then
  echo "derive-governance: cloning translation-rules -> $RULES_DIR"
  git clone --quiet "$RULES_REPO" "$RULES_DIR"
fi
# Best-effort fetch (an already-local pin still resolves offline).
git -C "$RULES_DIR" fetch --quiet origin "$PIN" 2>/dev/null \
  || git -C "$RULES_DIR" fetch --quiet --tags 2>/dev/null || true
git -C "$RULES_DIR" checkout --quiet --detach "$PIN" 2>/dev/null || {
  echo "error: pin $PIN unavailable in $RULES_DIR (fetch failed and commit absent)" >&2; exit 1; }

# --- deterministic generated_at (committer date of the pin, UTC) -------------
# Matches the CI derive action / old sync-resolved.sh byte-for-byte (TZ=UTC +
# format-local avoids the git %cI +00:00-vs-Z version skew).
GEN_AT="$(TZ=UTC git -C "$RULES_DIR" show -s \
  --date=format-local:'%Y-%m-%dT%H:%M:%S+00:00' --format=%cd "$PIN")"

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
    --source-commit "$PIN" --generated-at "$GEN_AT" \
    --index-path "$EMIT_DIR/index.json" --lint )

n=$(find "$EMIT_DIR/.resolved" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
echo "derive-governance: derived ${n} locale(s) into ${EMIT_DIR#"$ROOT/"}/ (.resolved/ + guides/for-translators/)"
