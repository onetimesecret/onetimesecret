#!/usr/bin/env bash
#
# sync-resolved.sh — vendor the committed translation-rules artifacts into the
# app repo (SPEC.md §2.3 "Output commit policy"). For every GOVERNED locale in
# a translation-rules checkout, run the resolver to emit BOTH artifacts —
# .resolved/<locale>.json (machine governance) and guides/for-translators/<locale>.md
# (human guide) — pinned to that checkout's HEAD SHA, into this app repo's
# locales/ dir. The emitted files are what the §2.4 freshness gate
# (resolved-freshness.yml) later hash-checks; they are COMMITTED, not CI-only.
#
# GOVERNED = a translation-rules locale directory that contains a register.yaml.
# That file is the "resolved-only-ready" signal (see authoring/backfill-locale.md):
# without a register an agent gets no formality lock and no terminology, which
# re-opens the 2026-04-12 register-regression class. Ungoverned content locales
# are SKIPPED — emitting for them would clobber the hand-authored guide that
# lives at locales/guides/for-translators/<locale>.md with a base-only stub.
#
# Usage:
#   locales/scripts/sync-resolved.sh [RULES_DIR]
#
#   RULES_DIR  Path to a translation-rules checkout. Arg 1 overrides the
#              ${RULES_DIR} env var, which defaults to ".translation-rules"
#              (the read-only pinned checkout path used by the CI workflows).
#
# Idempotent: re-running against the same checkout reproduces byte-identical
# artifacts (the resolver pins _meta.source_commit to the SHA; pass
# --generated-at upstream if you also need a frozen timestamp). Safe to re-run.
#
# This script writes ONLY into the app repo's locales/ dir. It writes the
# resolver index to a throwaway temp path so the rules repo's
# resolver/index.json is never touched.

set -euo pipefail

# --- locate the translation-rules checkout -----------------------------------
RULES_DIR="${1:-${RULES_DIR:-.translation-rules}}"

if [ ! -d "$RULES_DIR" ]; then
  echo "error: translation-rules checkout not found at: $RULES_DIR" >&2
  echo "       pass it as arg 1 or set \$RULES_DIR (default: .translation-rules)" >&2
  exit 2
fi
# Absolute path — the resolver is invoked from inside $RULES_DIR (cd), so every
# path we hand it must be absolute to stay anchored to the app repo.
RULES_DIR="$(cd "$RULES_DIR" && pwd)"

if [ ! -f "$RULES_DIR/resolver/resolve.py" ]; then
  echo "error: $RULES_DIR does not look like a translation-rules checkout" >&2
  echo "       (missing resolver/resolve.py)" >&2
  exit 2
fi

# --- app repo locales/ dir (emit target) -------------------------------------
# This script lives at <app>/locales/scripts/sync-resolved.sh; its grandparent
# is <app>/locales. Resolve from the script's own location so cwd doesn't matter.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_LOCALES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$APP_LOCALES_DIR/content" ]; then
  echo "error: $APP_LOCALES_DIR does not look like the app repo's locales/ dir" >&2
  echo "       (missing content/)" >&2
  exit 2
fi

# --- pin to the checkout's HEAD ----------------------------------------------
SHA="$(git -C "$RULES_DIR" rev-parse HEAD)"

echo "sync-resolved: rules checkout = $RULES_DIR"
echo "sync-resolved: rules SHA      = $SHA"
echo "sync-resolved: emit target    = $APP_LOCALES_DIR"
echo

# --- emit per governed locale ------------------------------------------------
synced=()
skipped=()

# Sort for deterministic, reproducible ordering across runs.
for d in "$RULES_DIR"/locales/*/; do
  [ -d "$d" ] || continue
  locale="$(basename "$d")"

  # CRITICAL GUARD: only governed locales (those with register.yaml upstream)
  # are eligible. Anything else is a hand-authored content locale; emitting for
  # it would overwrite its hand-authored guide with a base-only stub.
  if [ ! -f "${d}register.yaml" ]; then
    echo "skip ${locale}: ungoverned (no register.yaml upstream) — leaving hand-authored guide untouched"
    skipped+=("$locale")
    continue
  fi

  echo "::sync ${locale}"
  # Run the resolver from inside the rules repo so it finds base.yaml, schema/,
  # locales/, retrospectives/ via its own defaults. Emit BOTH artifacts pinned
  # to $SHA. Write the index to a throwaway temp file so the rules repo's
  # committed resolver/index.json is left untouched.
  index_tmp="$(mktemp)"
  (
    cd "$RULES_DIR" && \
    uv run resolver/resolve.py "$locale" \
      --lint \
      --emit=md,json \
      --emit-dir "$APP_LOCALES_DIR" \
      --source-commit "$SHA" \
      --index-path "$index_tmp"
  )
  rm -f "$index_tmp"
  synced+=("$locale")
done

# --- summary -----------------------------------------------------------------
echo
echo "sync-resolved: done."
echo "  rules SHA: $SHA"
echo "  synced (${#synced[@]}): ${synced[*]:-<none>}"
echo "  skipped (${#skipped[@]}): ${skipped[*]:-<none>}"

if [ "${#synced[@]}" -eq 0 ]; then
  echo "sync-resolved: warning — no governed locales found under $RULES_DIR/locales" >&2
fi
