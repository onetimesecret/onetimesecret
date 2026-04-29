#!/bin/bash
# Run v0.24.5 transform pipeline (enrich, per-model transforms, validation).
#
# This script handles the TRANSFORM phase only. It is called by upgrade.sh
# as Phase 2. Do not run this directly for a full upgrade — use upgrade.sh.
#
# Transforms and index creation are FATAL on failure (set -e applies).
# Validators are NON-FATAL: failures are captured and summarized at the end.
# This lets the full pipeline complete so all issues surface in one run,
# rather than fixing one model at a time and re-running.
#
# CONTRACT: All scripts invoked by this pipeline MUST default to execute
# (i.e., run-with-side-effects without an explicit flag). The Phase 2
# orchestration in upgrade.sh runs this script only when --execute is set,
# so dry-run propagation is handled at the parent level. enrich_with_identifiers.rb
# is the documented exception (defaults to dry-run for direct CLI safety,
# cf. PR #2748); it is invoked here with an explicit --execute and guarded
# against silent dry-run output below. If you add a callee that defaults
# to dry-run, either flip its default or add a similar guard, or the
# pipeline will silently no-op (see issue #3036).
#
# Usage: Run from project root:
#   scripts/upgrades/v0.24.5/run_pipeline.sh
#
# Environment variables (checked in order):
#   VALKEY_URL - Primary Redis/Valkey URL
#   REDIS_URL  - Fallback Redis URL
#
set -e

# Track validation warnings (non-fatal)
validation_warnings=()

# Run a validator script. Captures exit code; non-zero is a warning, not fatal.
run_validator() {
  local script="$1"
  shift
  if ! ruby "$script" "$@"; then
    validation_warnings+=("$script")
    echo "  WARNING: validation issues detected (see above) — continuing"
  fi
}

# Verify running from project root
if [ ! -f "Gemfile" ] || [ ! -d "scripts/upgrades/v0.24.5" ]; then
  echo "Error: Must run from project root directory"
  echo "Usage: scripts/upgrades/v0.24.5/run_pipeline.sh"
  exit 1
fi

# Validate a URL is available
if [ -z "${VALKEY_URL:-$REDIS_URL}" ]; then
  echo "Error: Redis URL is required"
  echo "Set VALKEY_URL or REDIS_URL environment variable"
  exit 1
fi

pipeline_start=$SECONDS

# Redact passwords for display
redact_url() {
  echo "$1" | sed -E 's|(://[^:]*:)[^@]*(@)|\1***\2|'
}

echo "=== v0.24.5 Upgrade Scripts ============================================="
echo "Redis: $(redact_url "${VALKEY_URL:-$REDIS_URL}")"
echo "Data:  data/upgrades/v0.24.5"
echo ""

echo ""
echo ""
phase_start=$SECONDS
echo "=== Enriching with identifiers ============================================="
# Defensive guard: enrich_with_identifiers.rb is the only callee in this
# pipeline that defaults to dry-run; every other script defaults to execute.
# That asymmetry has burned us once already (cf. issue #3036). If the enricher
# silently no-ops, downstream transforms produce empty/incorrect output without
# any error. Capture the script output, replay it, and abort if the dry-run
# banner appears.
#
# Implementation note: $(cmd) under set -e aborts on non-zero, so we capture
# the exit status into enrich_status with `|| enrich_status=$?` (defaulting to
# 0 on success). That preserves real ruby crashes — we re-exit with the
# captured status — while letting us inspect the output for the dry-run banner.
enrich_output=$(ruby scripts/upgrades/v0.24.5/enrich_with_identifiers.rb --execute 2>&1) || enrich_status=$?
enrich_status=${enrich_status:-0}
echo "$enrich_output"
if [ "$enrich_status" -ne 0 ]; then
  echo "  FATAL: enrich_with_identifiers.rb exited with status $enrich_status"
  exit "$enrich_status"
fi
if echo "$enrich_output" | grep -q "Would enrich"; then
  echo ""
  echo "  FATAL: enrich_with_identifiers.rb ran in dry-run mode."
  echo "  The pipeline requires --execute. See run_pipeline.sh contract above."
  exit 1
fi
echo "  Enrichment completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Customer ============================================="
ruby scripts/upgrades/v0.24.5/01-customer/transform.rb
ruby scripts/upgrades/v0.24.5/01-customer/create_indexes.rb
run_validator scripts/upgrades/v0.24.5/01-customer/validate_instance_index.rb --redis-url="${VALKEY_URL:-$REDIS_URL}"
echo "  Customer completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Organization ============================================="
ruby scripts/upgrades/v0.24.5/02-organization/generate.rb
ruby scripts/upgrades/v0.24.5/02-organization/create_indexes.rb
run_validator scripts/upgrades/v0.24.5/02-organization/validate_instance_index.rb
echo "  Organization completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Domain ============================================="
ruby scripts/upgrades/v0.24.5/03-customdomain/transform.rb
ruby scripts/upgrades/v0.24.5/03-customdomain/create_indexes.rb
run_validator scripts/upgrades/v0.24.5/03-customdomain/validate_instance_index.rb --redis-url="${VALKEY_URL:-$REDIS_URL}"
echo "  Domain completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Receipt ============================================="
ruby scripts/upgrades/v0.24.5/04-receipt/transform.rb
ruby scripts/upgrades/v0.24.5/04-receipt/create_indexes.rb
run_validator scripts/upgrades/v0.24.5/04-receipt/validate_instance_index.rb
echo "  Receipt completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Secret ============================================="
ruby scripts/upgrades/v0.24.5/05-secret/transform.rb
ruby scripts/upgrades/v0.24.5/05-secret/create_indexes.rb
run_validator scripts/upgrades/v0.24.5/05-secret/validate_instance_index.rb
echo "  Secret completed in $((SECONDS - phase_start))s"

echo ""

# Summarize validation warnings
if [ ${#validation_warnings[@]} -gt 0 ]; then
  echo "=== Validation Warnings ===================================================="
  echo "  ${#validation_warnings[@]} validator(s) reported issues:"
  for script in "${validation_warnings[@]}"; do
    echo "    - $script"
  done
  echo ""
  echo "  Review the output above before proceeding to Phase 3 (load)."
  echo "  Transforms and indexes completed successfully."
  echo "============================================================================="
else
  echo "  All validators passed."
fi

echo ""
echo "=== Done in $((SECONDS - pipeline_start))s ============================================="
