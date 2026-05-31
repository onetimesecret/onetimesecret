#!/usr/bin/env bash
# scripts/billing-docs-generate.sh
#
# Regenerate apps/web/billing/docs/plan-definitions.md from etc/billing.yaml.
#
# Boot-free
# ---------
# Doc generation is a pure YAML → markdown transform, so this drives the
# standalone scripts/generate_billing_docs.rb entrypoint: plain `ruby` +
# stdlib, no bundler, no `require 'onetime'`, no Redis/auth.yaml/full boot.
# That keeps it runnable on any Ruby (even ones outside the app Gemfile's
# version constraint) and decoupled from a fully-provisioned environment.
#
# Strictness modes
# ----------------
# Default (tolerant): Always exits 0. Differentiates failure modes:
#   - ruby not installed         → silent skip on stderr (frontend-only dev)
#   - billing.yaml absent        → generator prints "skipped" line, exit 0
#   - generation errors          → LOUD multi-line warning on stderr, exit 0
#
# --strict (or STRICT=1):  Propagates exit codes. Use when you want CI
#   or a manual invocation to fail on real generation errors. Ruby not
#   being installed is still treated as an "infrastructure missing"
#   condition and exits 0 — it's not the generator's job to insist Ruby
#   be present in a frontend-only environment.
#
# Why split modes
# ---------------
# Pure tolerance hides real bugs (committed doc silently goes stale).
# Pure strictness blocks frontend-only devs from running `pnpm dev`.
# The default tolerant mode lets predev stay safe; the strict mode
# (used by `pnpm run docs:billing:generate` and CI doc-diff checks)
# surfaces the same failure loudly when intentionally invoked.

set -u

STRICT="${STRICT:-0}"
if [ "${1:-}" = "--strict" ]; then
  STRICT=1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "[docs:billing:generate] skipped: ruby not installed" >&2
  exit 0
fi

if ! ruby scripts/generate_billing_docs.rb; then
  if [ "$STRICT" = "1" ]; then
    cat >&2 <<'EOF'

*** [docs:billing:generate] GENERATION FAILED (strict mode)
*** Fix the underlying error above before retrying.

EOF
    exit 1
  fi

  cat >&2 <<'EOF'

*** [docs:billing:generate] GENERATION FAILED — committed doc may be stale.
*** Run `pnpm run docs:billing:generate` to reproduce with strict exit.
*** This is non-fatal so `pnpm dev` continues, but the drift is real.

EOF
  exit 0
fi
