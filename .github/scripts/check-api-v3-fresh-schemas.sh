#!/usr/bin/env bash
# Run from the checkout root, after Ruby/Node setup and test service provisioning.
set -euo pipefail

# The mounted harness has a fixed output path because the lane scrubs custom env.
# Clear prior JSON first: a skipped/partial producer must not reuse old captures.
capture_dir=tmp/api-v3-schema-captures
if [[ -L "$capture_dir" ]]; then
  echo 'Refusing a symlinked API v3 capture directory' >&2
  exit 1
fi
mkdir -p "$capture_dir"
rm -f "$capture_dir"/*.json

# --only skips the simple lane's locales prerequisite; fresh checkouts need it
# before spec_helper will boot. Use the same command as the lane's codegen phase.
pnpm run locales:sync

LANES_NO_AUTOSTART=1 tests/lanes/run simple --workers 1 --quiet \
  --only spec/integration/simple/api_v3_schema_capture_spec.rb

if ! compgen -G "$capture_dir/*.json" > /dev/null; then
  echo 'Fresh API v3 producer emitted no captures; refusing historical fallback' >&2
  exit 1
fi

API_V3_SCHEMA_CAPTURE_DIR="$capture_dir" pnpm test:base run \
  src/tests/contracts/v3-http-producer-contract.spec.ts \
  src/tests/schemas/api/v3-openapi-producer.spec.ts
