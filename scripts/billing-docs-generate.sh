#!/usr/bin/env bash
# scripts/billing-docs-generate.sh
#
# Regenerate apps/web/billing/docs/plan-definitions.md from etc/billing.yaml.
# Designed to be safe to invoke from `predev` and similar hooks where the
# host environment may not have Ruby/bundler available (e.g. frontend-only
# developers, Node-only CI jobs).
#
# Exit semantics
# --------------
# Always exits 0. Differentiates failure modes via stderr:
#   - bundle not installed   → silent skip (frontend-only dev)
#   - billing.yaml absent    → handled inside the CLI command (info skip)
#   - generation itself errs → loud non-fatal log (so devs see real bugs)
#
# This intentionally never fails the calling script. The doc is committed
# source, not a build artifact — a stale doc is a drift bug, not a build
# blocker.

set -u

if ! command -v bundle >/dev/null 2>&1; then
  echo "[docs:billing:generate] skipped: bundle not installed" >&2
  exit 0
fi

if ! bundle exec bin/ots billing catalog generate-docs; then
  echo "[docs:billing:generate] generation failed (non-fatal, continuing)" >&2
  exit 0
fi
