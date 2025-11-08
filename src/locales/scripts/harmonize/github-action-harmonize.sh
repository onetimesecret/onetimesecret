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
ls -la "${GITHUB_WORKSPACE}/src/locales/scripts/"

# Determine copy option
COPY_OPTION=""
if [[ "$COPY_ENGLISH" == "true" ]]; then
  COPY_OPTION="-c"
fi

# Make scripts executable
chmod +x "${GITHUB_WORKSPACE}/src/locales/scripts/harmonize-locale-files"
chmod +x "${GITHUB_WORKSPACE}/src/locales/scripts/harmonize-locale-file"

# Run the harmonize script with verbose output
"${GITHUB_WORKSPACE}/src/locales/scripts/harmonize-locale-files" -v $COPY_OPTION

# Store exit code
HARMONIZE_EXIT_CODE=$?

# Check if changes were made to any locale files
if git diff --name-only | grep -q "src/locales/"; then
  echo "changes_made=true" >> $GITHUB_OUTPUT
else
  echo "changes_made=false" >> $GITHUB_OUTPUT
fi

echo "exit_code=$HARMONIZE_EXIT_CODE" >> $GITHUB_OUTPUT
exit $HARMONIZE_EXIT_CODE
