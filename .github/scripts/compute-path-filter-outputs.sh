#!/bin/bash
#
# Compute final path filter outputs based on CI flags and file changes.
#
# When [ci-skip] is set, all outputs are false.
# When [ci-all] is set or workflow files changed, every path output is true.
# Otherwise, outputs match the path filter results. Auth selection is a flag
# of its own: it adds its jobs and never turns on the ordinary Ruby jobs.
# Those jobs get the frontend build they need from build-assets, whose gate
# in ci.yml includes the flag.
#
# billing_nightly is not a path output at all. It is the nightly-only
# selection — the scheduled run, or a manual dispatch with run_all — and
# nothing else turns it on: not a path, not [ci-all], not a workflow-file
# change, not a push to main or a merge-queue check. [ci-skip] still turns
# it off, so a skipped nightly stays a skipped nightly.
#
# Environment variables (inputs):
#   SKIP_CI          - true if [ci-skip] detected
#   RUN_ALL          - true if [ci-all] detected or workflow_dispatch
#   GA_WORKFLOWS     - true if .github/** files changed
#   FILTER_RUBY      - true if Ruby files changed
#   FILTER_TYPESCRIPT - true if TypeScript files changed
#   FILTER_FRONTEND  - true if frontend files changed
#   FILTER_OCI       - true if Docker/OCI files changed
#   FILTER_HARNESS   - true if a path the lane runner's own specs exercise changed
#   FILTER_AUTH      - shared auth selector result (paths, label, or event)
#   NIGHTLY          - true on the schedule event or a dispatch with run_all
#
# Outputs (to GITHUB_OUTPUT):
#   ruby, typescript, frontend, oci, harness, auth, billing_nightly, ga_workflow_files

set -e

# Read inputs from environment
SKIP_CI="${SKIP_CI:-false}"
RUN_ALL="${RUN_ALL:-false}"
GA_WORKFLOWS="${GA_WORKFLOWS:-false}"
FILTER_RUBY="${FILTER_RUBY:-false}"
FILTER_TYPESCRIPT="${FILTER_TYPESCRIPT:-false}"
FILTER_FRONTEND="${FILTER_FRONTEND:-false}"
FILTER_OCI="${FILTER_OCI:-false}"
FILTER_HARNESS="${FILTER_HARNESS:-false}"
NIGHTLY="${NIGHTLY:-false}"
FILTER_AUTH="${FILTER_AUTH:-}"
case "$FILTER_AUTH" in
  true | false) ;;
  *) echo '::error::FILTER_AUTH must be true or false.' >&2; exit 1 ;;
esac

# Compute outputs
if [[ "$SKIP_CI" == "true" ]]; then
  # Skip everything
  RUBY=false
  TYPESCRIPT=false
  FRONTEND=false
  OCI=false
  HARNESS=false
  GA_WORKFLOW_FILES=false
  AUTH=false
  BILLING_NIGHTLY=false
elif [[ "$RUN_ALL" == "true" || "$GA_WORKFLOWS" == "true" ]]; then
  # Run everything path-gated
  RUBY=true
  TYPESCRIPT=true
  FRONTEND=true
  OCI=true
  HARNESS=true
  GA_WORKFLOW_FILES=true
  AUTH=true
  BILLING_NIGHTLY="$NIGHTLY"
else
  # Use path filter results
  RUBY="$FILTER_RUBY"
  TYPESCRIPT="$FILTER_TYPESCRIPT"
  FRONTEND="$FILTER_FRONTEND"
  OCI="$FILTER_OCI"
  HARNESS="$FILTER_HARNESS"
  GA_WORKFLOW_FILES=false
  AUTH="$FILTER_AUTH"
  BILLING_NIGHTLY="$NIGHTLY"
fi

# Output results
if [[ -n "$GITHUB_OUTPUT" ]]; then
  echo "ruby=$RUBY" >> "$GITHUB_OUTPUT"
  echo "typescript=$TYPESCRIPT" >> "$GITHUB_OUTPUT"
  echo "frontend=$FRONTEND" >> "$GITHUB_OUTPUT"
  echo "oci=$OCI" >> "$GITHUB_OUTPUT"
  echo "harness=$HARNESS" >> "$GITHUB_OUTPUT"
  echo "auth=$AUTH" >> "$GITHUB_OUTPUT"
  echo "billing_nightly=$BILLING_NIGHTLY" >> "$GITHUB_OUTPUT"
  echo "ga_workflow_files=$GA_WORKFLOW_FILES" >> "$GITHUB_OUTPUT"
else
  # Local testing - print to stdout
  echo "ruby=$RUBY"
  echo "typescript=$TYPESCRIPT"
  echo "frontend=$FRONTEND"
  echo "oci=$OCI"
  echo "harness=$HARNESS"
  echo "auth=$AUTH"
  echo "billing_nightly=$BILLING_NIGHTLY"
  echo "ga_workflow_files=$GA_WORKFLOW_FILES"
fi
