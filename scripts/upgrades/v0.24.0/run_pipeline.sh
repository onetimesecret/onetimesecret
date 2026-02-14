#!/bin/bash
# Run v0.24.0 transform pipeline (enrich, per-model transforms, validation).
#
# This script handles the TRANSFORM phase only. It is called by upgrade.sh
# as Phase 2. Do not run this directly for a full upgrade — use upgrade.sh.
#
# Usage: Run from project root:
#   scripts/upgrades/v0.24.0/run_pipeline.sh
#
# Environment variables (checked in order):
#   VALKEY_URL - Primary Redis/Valkey URL
#   REDIS_URL  - Fallback Redis URL
#
set -e

# Verify running from project root
if [ ! -f "CLAUDE.md" ] || [ ! -d "scripts/upgrades/v0.24.0" ]; then
  echo "Error: Must run from project root directory"
  echo "Usage: scripts/upgrades/v0.24.0/run_pipeline.sh"
  exit 1
fi

# Validate a URL is available
if [ -z "${VALKEY_URL:-$REDIS_URL}" ]; then
  echo "Error: Redis URL is required"
  echo "Set VALKEY_URL or REDIS_URL environment variable"
  exit 1
fi

pipeline_start=$SECONDS

echo "=== v0.24.0 Upgrade Scripts ============================================="
echo "Redis: ${VALKEY_URL:-$REDIS_URL}"
echo "Data:  data/upgrades/v0.24.0"
echo ""

echo ""
echo ""
phase_start=$SECONDS
echo "=== Enriching with identifiers ============================================="
ruby scripts/upgrades/v0.24.0/enrich_with_identifiers.rb
echo "  Enrichment completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Customer ============================================="
ruby scripts/upgrades/v0.24.0/01-customer/transform.rb
ruby scripts/upgrades/v0.24.0/01-customer/create_indexes.rb
ruby scripts/upgrades/v0.24.0/01-customer/validate_instance_index.rb --redis-url="${VALKEY_URL:-$REDIS_URL}"
echo "  Customer completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Organization ============================================="
ruby scripts/upgrades/v0.24.0/02-organization/generate.rb
ruby scripts/upgrades/v0.24.0/02-organization/create_indexes.rb
ruby scripts/upgrades/v0.24.0/02-organization/validate_instance_index.rb
echo "  Organization completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Domain ============================================="
ruby scripts/upgrades/v0.24.0/03-customdomain/transform.rb
ruby scripts/upgrades/v0.24.0/03-customdomain/create_indexes.rb
ruby scripts/upgrades/v0.24.0/03-customdomain/validate_instance_index.rb --redis-url="${VALKEY_URL:-$REDIS_URL}"
echo "  Domain completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Receipt ============================================="
ruby scripts/upgrades/v0.24.0/04-receipt/transform.rb
ruby scripts/upgrades/v0.24.0/04-receipt/create_indexes.rb
ruby scripts/upgrades/v0.24.0/04-receipt/validate_instance_index.rb
echo "  Receipt completed in $((SECONDS - phase_start))s"

echo ""
echo ""
phase_start=$SECONDS
echo "=== Secret ============================================="
ruby scripts/upgrades/v0.24.0/05-secret/transform.rb
ruby scripts/upgrades/v0.24.0/05-secret/create_indexes.rb
ruby scripts/upgrades/v0.24.0/05-secret/validate_instance_index.rb
echo "  Secret completed in $((SECONDS - phase_start))s"

echo ""
echo "=== Done in $((SECONDS - pipeline_start))s ============================================="
