#!/bin/bash
#
# GitHub Action wrapper for harmonize-locale-files
# This script is specifically designed to be run from GitHub Actions
#

set -e

# Debug information
echo "Current directory: $(pwd)"
echo "GitHub workspace: ${GITHUB_WORKSPACE}"
echo "Listing script directory:"
ls -la "${GITHUB_WORKSPACE}/src/scripts/locales/"

# Determine copy option
COPY_OPTION=""
if [[ "$COPY_ENGLISH" == "true" ]]; then
  COPY_OPTION="-c"
fi

# Make scripts executable
chmod +x "${GITHUB_WORKSPACE}/src/scripts/locales/harmonize/harmonize-all-locale-files"
chmod +x "${GITHUB_WORKSPACE}/src/scripts/locales/harmonize/harmonize-locale-file"

# Run the harmonize script with verbose output
"${GITHUB_WORKSPACE}/src/scripts/locales/harmonize/harmonize-all-locale-files" -v $COPY_OPTION

# Store exit code
HARMONIZE_EXIT_CODE=$?

# Run variable discrepancy audit
echo ""
echo "=== Running variable audit ==="
AUDIT_SCRIPT="${GITHUB_WORKSPACE}/src/scripts/locales/audit/audit-variables.py"
if [[ -f "$AUDIT_SCRIPT" ]]; then
  python3 "$AUDIT_SCRIPT" --summary
  AUDIT_EXIT_CODE=$?
  echo "variable_issues=$AUDIT_EXIT_CODE" >> $GITHUB_OUTPUT
else
  echo "Warning: audit-variables.py not found"
  AUDIT_EXIT_CODE=0
fi

# Check if changes were made to any locale files
if git diff --name-only | grep -q "src/locales/"; then
  echo "changes_made=true" >> $GITHUB_OUTPUT
else
  echo "changes_made=false" >> $GITHUB_OUTPUT
fi

echo "exit_code=$HARMONIZE_EXIT_CODE" >> $GITHUB_OUTPUT

# Fail if harmonization failed (audit issues are warnings only)
exit $HARMONIZE_EXIT_CODE
