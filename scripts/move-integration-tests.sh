#!/bin/bash
#
# Move integration tests from spec/unit/ to spec/integration/all/
# These tests require Redis/database connections and aren't true unit tests.
#
# Usage: ./scripts/move-integration-tests.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "=== DRY RUN MODE ==="
fi

cd "$(git rev-parse --show-toplevel)"

# Target directories
INTEGRATION_ALL="spec/integration/all"

run_cmd() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "Moving integration tests from spec/unit/onetime/ to spec/integration/all/"
echo ""

# Create target subdirectories
echo "Creating target directories..."
run_cmd mkdir -p "$INTEGRATION_ALL/initializers"
run_cmd mkdir -p "$INTEGRATION_ALL/jobs/workers"
run_cmd mkdir -p "$INTEGRATION_ALL/operations"

echo ""
echo "Moving initializer boot tests..."
# Boot tests - require full app initialization via Onetime.boot!
run_cmd git mv spec/unit/onetime/initializers/boot_part1_spec.rb "$INTEGRATION_ALL/initializers/"
run_cmd git mv spec/unit/onetime/initializers/boot_part2_spec.rb "$INTEGRATION_ALL/initializers/"

echo ""
echo "Moving worker tests (Redis idempotency)..."
# Worker tests - use real Redis via Familia.dbclient for idempotency checks
run_cmd git mv spec/unit/onetime/jobs/workers/base_worker_spec.rb "$INTEGRATION_ALL/jobs/workers/"
run_cmd git mv spec/unit/onetime/jobs/workers/email_worker_spec.rb "$INTEGRATION_ALL/jobs/workers/"
run_cmd git mv spec/unit/onetime/jobs/workers/billing_worker_spec.rb "$INTEGRATION_ALL/jobs/workers/"
run_cmd git mv spec/unit/onetime/jobs/workers/notification_worker_spec.rb "$INTEGRATION_ALL/jobs/workers/"

echo ""
echo "Moving operations tests (Redis notification storage)..."
# Operations tests - use real Redis for notification bell storage
run_cmd git mv spec/unit/onetime/operations/dispatch_notification_spec.rb "$INTEGRATION_ALL/operations/"

echo ""
echo "Cleaning up empty directories..."
# Remove empty workers directory if it exists
if [[ -d "spec/unit/onetime/jobs/workers" ]] && [[ -z "$(ls -A spec/unit/onetime/jobs/workers 2>/dev/null)" ]]; then
  run_cmd rmdir spec/unit/onetime/jobs/workers
fi

# Remove empty operations directory if it exists
if [[ -d "spec/unit/onetime/operations" ]] && [[ -z "$(ls -A spec/unit/onetime/operations 2>/dev/null)" ]]; then
  run_cmd rmdir spec/unit/onetime/operations
fi

echo ""
echo "=== Summary ==="
echo "Moved to $INTEGRATION_ALL/initializers/:"
echo "  - boot_part1_spec.rb"
echo "  - boot_part2_spec.rb"
echo ""
echo "Moved to $INTEGRATION_ALL/jobs/workers/:"
echo "  - base_worker_spec.rb"
echo "  - email_worker_spec.rb"
echo "  - billing_worker_spec.rb"
echo "  - notification_worker_spec.rb"
echo ""
echo "Moved to $INTEGRATION_ALL/operations/:"
echo "  - dispatch_notification_spec.rb"
echo ""

if ! $DRY_RUN; then
  echo "Files moved. Run 'git status' to review changes."
  echo "Run tests with: RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec spec/integration/all/"
fi
