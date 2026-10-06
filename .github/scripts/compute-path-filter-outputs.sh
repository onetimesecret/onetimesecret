#!/bin/bash
#
# Compute final path filter outputs based on CI flags and file changes.
#
# When [ci-skip] is set, all outputs are false.
# When [ci-all] is set or workflow files changed, all outputs are true.
# Otherwise, outputs match the path filter results. Auth and billing selection
# are flags of their own: each adds its jobs and never turns on the ordinary
# Ruby jobs. Those jobs get the frontend build they need from build-assets,
# whose gate in ci.yml includes both flags.
#
# Environment variables (inputs):
#   SKIP_CI          - true if [ci-skip] detected
#   RUN_ALL          - true if [ci-all] detected or workflow_dispatch
#   GA_WORKFLOWS     - true if .github/** files changed
#   FILTER_RUBY      - true if Ruby files changed
#   FILTER_TYPESCRIPT - true if TypeScript files changed
#   FILTER_FRONTEND  - true if frontend files changed
#   FILTER_OCI       - true if Docker/OCI files changed
#   FILTER_AUTH      - shared auth selector result (paths, label, or event)
#   FILTER_BILLING   - true if billing files changed
#
# Outputs (to GITHUB_OUTPUT):
#   ruby, typescript, frontend, oci, auth, billing, ga_workflow_files

set -e

# Read inputs from environment
SKIP_CI="${SKIP_CI:-false}"
RUN_ALL="${RUN_ALL:-false}"
GA_WORKFLOWS="${GA_WORKFLOWS:-false}"
FILTER_RUBY="${FILTER_RUBY:-false}"
FILTER_TYPESCRIPT="${FILTER_TYPESCRIPT:-false}"
FILTER_FRONTEND="${FILTER_FRONTEND:-false}"
FILTER_OCI="${FILTER_OCI:-false}"
FILTER_BILLING="${FILTER_BILLING:-false}"
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
  GA_WORKFLOW_FILES=false
  AUTH=false
  BILLING=false
elif [[ "$RUN_ALL" == "true" || "$GA_WORKFLOWS" == "true" ]]; then
  # Run everything
  RUBY=true
  TYPESCRIPT=true
  FRONTEND=true
  OCI=true
  GA_WORKFLOW_FILES=true
  AUTH=true
  BILLING=true
else
  # Use path filter results
  RUBY="$FILTER_RUBY"
  TYPESCRIPT="$FILTER_TYPESCRIPT"
  FRONTEND="$FILTER_FRONTEND"
  OCI="$FILTER_OCI"
  GA_WORKFLOW_FILES=false
  AUTH="$FILTER_AUTH"
  BILLING="$FILTER_BILLING"
fi

# Output results
if [[ -n "$GITHUB_OUTPUT" ]]; then
  echo "ruby=$RUBY" >> "$GITHUB_OUTPUT"
  echo "typescript=$TYPESCRIPT" >> "$GITHUB_OUTPUT"
  echo "frontend=$FRONTEND" >> "$GITHUB_OUTPUT"
  echo "oci=$OCI" >> "$GITHUB_OUTPUT"
  echo "auth=$AUTH" >> "$GITHUB_OUTPUT"
  echo "billing=$BILLING" >> "$GITHUB_OUTPUT"
  echo "ga_workflow_files=$GA_WORKFLOW_FILES" >> "$GITHUB_OUTPUT"
else
  # Local testing - print to stdout
  echo "ruby=$RUBY"
  echo "typescript=$TYPESCRIPT"
  echo "frontend=$FRONTEND"
  echo "oci=$OCI"
  echo "auth=$AUTH"
  echo "billing=$BILLING"
  echo "ga_workflow_files=$GA_WORKFLOW_FILES"
fi
