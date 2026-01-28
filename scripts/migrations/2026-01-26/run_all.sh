#!/bin/bash
# Run all migration stages (assumes dump already exists)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

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

# echo "=== Domain ==="
ruby "$DIR/03-customdomain/transform.rb"
ruby "$DIR/03-customdomain/create_indexes.rb"


echo "=== Receipt ==="
# ruby "$DIR/04-receipt/transform.rb"
# ruby "$DIR/04-receipt/create_indexes.rb"

echo "=== Secret ==="
# ruby "$DIR/05-secret/transform.rb"
# ruby "$DIR/05-secret/create_indexes.rb"


# echo "=== Creating indexes ==="


# echo "=== Enriching with original records ==="
# ruby "$DIR/enrich_with_original_record.rb" customer
# ruby "$DIR/enrich_with_original_record.rb" customdomain
# ruby "$DIR/enrich_with_original_record.rb" receipt
# ruby "$DIR/enrich_with_original_record.rb" secret

# echo "=== Done ==="
