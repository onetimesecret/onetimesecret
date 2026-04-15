#!/usr/bin/env bash
# scripts/parallel-pre-push.sh
#
# Parallel pre-push hook that runs Ruby tests, ESLint, and TypeScript
# type checking concurrently to minimize wait time before pushing.
#
# This replaces sequential pre-commit hooks with a single parallel execution,
# reducing total time from ~115s to ~90s (limited by slowest task).
#
# Usage:
#   Called automatically by pre-commit on git push
#   Manual: ./scripts/parallel-pre-push.sh
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed

set -o pipefail

# Colors for output (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Create temp directory for output capture
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo -e "${BLUE}Running pre-push checks in parallel...${NC}"
echo ""

# Start background jobs with output capture
bundle exec rake spec:fast > "$TMPDIR/ruby.log" 2>&1 &
pid_ruby=$!

pnpm run lint > "$TMPDIR/lint.log" 2>&1 &
pid_lint=$!

pnpm run type-check > "$TMPDIR/types.log" 2>&1 &
pid_types=$!

# Track start time
start_time=$(date +%s)

# Wait for each job and capture exit codes
wait $pid_ruby
ruby_exit=$?

wait $pid_lint
lint_exit=$?

wait $pid_types
types_exit=$?

# Calculate duration
end_time=$(date +%s)
duration=$((end_time - start_time))

# Helper to show status
status_icon() {
  if [ "$1" -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗${NC}"
  fi
}

# Report results
echo ""
echo -e "${BLUE}Results:${NC} (${duration}s)"
echo -e "  Ruby specs (rake spec:fast):  $(status_icon $ruby_exit)"
echo -e "  ESLint (pnpm lint):            $(status_icon $lint_exit)"
echo -e "  TypeScript (pnpm type-check):  $(status_icon $types_exit)"
echo ""

# Show failures with relevant output
show_failure() {
  local name=$1
  local logfile=$2
  local exit_code=$3

  if [ "$exit_code" -ne 0 ]; then
    echo -e "${RED}━━━ $name failed ━━━${NC}"
    # Show last 50 lines of output (usually contains the error)
    tail -50 "$logfile"
    echo ""
  fi
}

if [ $ruby_exit -ne 0 ] || [ $lint_exit -ne 0 ] || [ $types_exit -ne 0 ]; then
  echo -e "${YELLOW}Failure details:${NC}"
  echo ""
  show_failure "Ruby specs" "$TMPDIR/ruby.log" $ruby_exit
  show_failure "ESLint" "$TMPDIR/lint.log" $lint_exit
  show_failure "TypeScript" "$TMPDIR/types.log" $types_exit

  echo -e "${RED}Pre-push checks failed. Push aborted.${NC}"
  exit 1
fi

echo -e "${GREEN}All pre-push checks passed.${NC}"
exit 0
