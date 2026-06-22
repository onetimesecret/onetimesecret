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
#   locales/scripts/sync-resolved.sh [RULES_DIR]              # refresh vendored set
#   LOCALES="de_AT fr_CA" locales/scripts/sync-resolved.sh    # vendor a specific set
#
#   RULES_DIR  Path to a translation-rules checkout. Arg 1 overrides the
#              ${RULES_DIR} env var, which defaults to ".translation-rules"
#              (the read-only pinned checkout path used by the CI workflows).
#   LOCALES    Optional space-separated allow-list. When set, vendor exactly these
#              locales (still subject to the governed guard); a requested locale
#              that is ungoverned or absent upstream is a hard error.
#
#              When UNSET, the default set is the locales ALREADY vendored in this
#              repo — i.e. the basenames of locales/.resolved/*.json. This is the
#              same set the §2.4 freshness gate audits, so a bare re-run refreshes
#              exactly what is committed and NOTHING ELSE. Critically, it will NOT
#              vendor an upstream-governed locale that is not yet part of the
#              committed set (e.g. fr/fr_CA pending native-speaker sign-off):
#              doing so would byte-lock unreviewed governance and clobber the
#              hand-authored locales/guides/for-translators/<locale>.md. Adding a
#              locale is therefore a deliberate `LOCALES=<new>` run, after which it
#              joins the committed set and subsequent bare runs keep it fresh.
#
#              Bootstrapping (no .resolved/ yet) with LOCALES unset vendors nothing
#              and tells you to name the locale explicitly.
#
# Idempotent and fully reproducible: re-running against the same checkout emits
# byte-identical artifacts. _meta.source_commit is pinned to the checkout SHA and
# _meta.generated_at is pinned to that commit's committer date (%cI), so the
# artifact is a pure function of the source commit — which is exactly what the
# §2.4 freshness gate relies on when it regenerates and diffs. Safe to re-run.
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
# Freeze _meta.generated_at to the source commit's committer date so the emitted
# artifact is a pure function of $SHA (no wall-clock drift between this vendor
# run and the CI freshness gate's regeneration). resolved-freshness.yml derives
# the SAME value from PINNED_RULES_REF; the two MUST stay in lock-step.
GENERATED_AT="$(git -C "$RULES_DIR" show -s --format=%cI "$SHA")"

# Resolve the set of locales to vendor. An explicit LOCALES allow-list wins;
# otherwise default to the locales ALREADY vendored (basenames of the committed
# locales/.resolved/*.json). Defaulting to the committed set — rather than to
# "every governed locale upstream" — is what keeps a bare re-run from silently
# vendoring an un-signed-off locale and clobbering its hand-authored guide.
REQUESTED_LOCALES="${LOCALES:-}"
default_set=0
if [ -z "$REQUESTED_LOCALES" ]; then
  default_set=1
  for j in "$APP_LOCALES_DIR"/.resolved/*.json; do
    [ -e "$j" ] || continue
    REQUESTED_LOCALES="${REQUESTED_LOCALES:+$REQUESTED_LOCALES }$(basename "$j" .json)"
  done
  if [ -z "$REQUESTED_LOCALES" ]; then
    echo "sync-resolved: nothing vendored yet and no LOCALES given — nothing to do." >&2
    echo "       To bootstrap a locale: LOCALES=\"de_AT\" $0 [RULES_DIR]" >&2
    exit 0
  fi
fi

echo "sync-resolved: rules checkout = $RULES_DIR"
echo "sync-resolved: rules SHA      = $SHA"
echo "sync-resolved: generated_at   = $GENERATED_AT"
echo "sync-resolved: emit target    = $APP_LOCALES_DIR"
if [ "$default_set" -eq 1 ]; then
  echo "sync-resolved: locale set     = $REQUESTED_LOCALES (default: already-vendored)"
else
  echo "sync-resolved: locale set     = $REQUESTED_LOCALES (explicit LOCALES)"
fi
echo

# --- emit per governed locale ------------------------------------------------
synced=()
skipped=()

# Sort for deterministic, reproducible ordering across runs.
for d in "$RULES_DIR"/locales/*/; do
  [ -d "$d" ] || continue
  locale="$(basename "$d")"

  # Vendor only the resolved set (explicit LOCALES, or the already-vendored
  # default). Anything outside it is left untouched on disk.
  case " $REQUESTED_LOCALES " in
    *" $locale "*) : ;;          # in set — fall through
    *) continue ;;               # not in set — leave any existing vendor untouched
  esac

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
  # to $SHA + $GENERATED_AT. Write the index to a throwaway temp file so the
  # rules repo's committed resolver/index.json is left untouched.
  index_tmp="$(mktemp)"
  (
    cd "$RULES_DIR" && \
    uv run resolver/resolve.py "$locale" \
      --lint \
      --emit=md,json \
      --emit-dir "$APP_LOCALES_DIR" \
      --source-commit "$SHA" \
      --generated-at "$GENERATED_AT" \
      --index-path "$index_tmp"
  )
  rm -f "$index_tmp"
  synced+=("$locale")
done

# A requested locale that never synced is a typo or an ungoverned/absent locale
# upstream — fail loudly rather than silently vendoring nothing for it.
if [ -n "$REQUESTED_LOCALES" ]; then
  for want in $REQUESTED_LOCALES; do
    found=0
    for got in "${synced[@]:-}"; do
      [ "$got" = "$want" ] && found=1 && break
    done
    if [ "$found" -eq 0 ]; then
      echo "error: requested locale '${want}' was not vendored — ungoverned (no register.yaml) or absent at $RULES_DIR/locales/${want}" >&2
      exit 2
    fi
  done
fi

# --- summary -----------------------------------------------------------------
echo
echo "sync-resolved: done."
echo "  rules SHA: $SHA"
echo "  synced (${#synced[@]}): ${synced[*]:-<none>}"
echo "  skipped (${#skipped[@]}): ${skipped[*]:-<none>}"

if [ "${#synced[@]}" -eq 0 ]; then
  echo "sync-resolved: warning — no governed locales found under $RULES_DIR/locales" >&2
fi
