#!/bin/bash
# Run all v0.24.0 upgrade stages
#
# Environment variables (checked in order):
#   VALKEY_URL - Primary Redis/Valkey URL
#   REDIS_URL  - Fallback Redis URL
#
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/../../.." && pwd)"

# Validate a URL is available
if [ -z "${VALKEY_URL:-$REDIS_URL}" ]; then
  echo "Error: Redis URL is required"
  echo "Set VALKEY_URL or REDIS_URL environment variable"
  exit 1
fi

echo "=== v0.24.0 Upgrade Scripts ==="
echo "Redis: ${VALKEY_URL:-$REDIS_URL}"
echo "Data:  $PROJECT_ROOT/data/upgrades/v0.24.0"
echo ""

echo "=== Dump and generate data ==="
ruby "$DIR/dump_keys.rb" --all

echo "=== Enriching with identifiers ==="
ruby "$DIR/enrich_with_identifiers.rb"

echo "=== Customer ==="
ruby "$DIR/01-customer/transform.rb"
ruby "$DIR/01-customer/create_indexes.rb"

echo "=== Organization ==="
ruby "$DIR/02-organization/generate.rb"
ruby "$DIR/02-organization/create_indexes.rb"

echo "=== Domain ==="
ruby "$DIR/03-customdomain/transform.rb"
ruby "$DIR/03-customdomain/create_indexes.rb"

echo "=== Receipt ==="
ruby "$DIR/04-receipt/transform.rb"
ruby "$DIR/04-receipt/create_indexes.rb"

echo "=== Secret ==="
ruby "$DIR/05-secret/transform.rb"
ruby "$DIR/05-secret/create_indexes.rb"

echo "=== Enriching with original records ==="
ruby "$DIR/enrich_with_original_record.rb"

echo "=== Done ==="
