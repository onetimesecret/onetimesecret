#!/bin/bash
# Run all v0.24.0 upgrade stages
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

echo "=== v0.24.0 Upgrade Scripts ==="
echo "Redis: ${VALKEY_URL:-$REDIS_URL}"
echo "Data:  data/upgrades/v0.24.0"
echo ""

echo "=== Enriching with identifiers ==="
ruby scripts/upgrades/v0.24.0/enrich_with_identifiers.rb

echo "=== Customer ==="
ruby scripts/upgrades/v0.24.0/01-customer/transform.rb
ruby scripts/upgrades/v0.24.0/01-customer/create_indexes.rb

echo "=== Organization ==="
ruby scripts/upgrades/v0.24.0/02-organization/generate.rb
ruby scripts/upgrades/v0.24.0/02-organization/create_indexes.rb

echo "=== Domain ==="
ruby scripts/upgrades/v0.24.0/03-customdomain/transform.rb
ruby scripts/upgrades/v0.24.0/03-customdomain/create_indexes.rb

echo "=== Receipt ==="
ruby scripts/upgrades/v0.24.0/04-receipt/transform.rb
ruby scripts/upgrades/v0.24.0/04-receipt/create_indexes.rb

echo "=== Secret ==="
ruby scripts/upgrades/v0.24.0/05-secret/transform.rb
ruby scripts/upgrades/v0.24.0/05-secret/create_indexes.rb

echo "=== Enriching with original records ==="
ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb

echo "=== Done ==="
