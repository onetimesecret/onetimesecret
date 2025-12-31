#!/bin/bash
#
# Script: create-missing-locale-files.sh
# Purpose: Ensure all locale directories have the same JSON files as English locale
# Usage: ./src/scripts/locales/create-missing-locale-files.sh [--dry-run]
#
# This script:
# - Gets the list of expected JSON files from src/locales/en/*.json
# - Iterates through each locale directory (excluding en/)
# - Creates missing JSON files with {} as content
# - Does NOT modify any existing files

set -euo pipefail

# Determine project root relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOCALES_DIR="${PROJECT_ROOT}/src/locales"
EN_DIR="${LOCALES_DIR}/en"
DRY_RUN=false

# Parse arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE - No files will be created ==="
    echo
fi

# Verify English locale directory exists
if [[ ! -d "$EN_DIR" ]]; then
    echo "ERROR: English locale directory not found: $EN_DIR"
    exit 1
fi

# Get list of JSON files from English locale (just the filenames)
EN_JSON_FILES=()
for f in "$EN_DIR"/*.json; do
    if [[ -f "$f" ]]; then
        EN_JSON_FILES+=("$(basename "$f")")
    fi
done

if [[ ${#EN_JSON_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No JSON files found in English locale"
    exit 1
fi

echo "Found ${#EN_JSON_FILES[@]} JSON files in English locale:"
printf "  - %s\n" "${EN_JSON_FILES[@]}"
echo

# Track created files
CREATED_FILES=()

# Iterate through each locale directory
for locale_dir in "$LOCALES_DIR"/*/; do
    locale_name=$(basename "$locale_dir")

    # Skip English locale
    if [[ "$locale_name" == "en" ]]; then
        continue
    fi

    # Check each expected JSON file
    for json_file in "${EN_JSON_FILES[@]}"; do
        target_file="${locale_dir}${json_file}"

        if [[ ! -f "$target_file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would create: $target_file"
            else
                echo "{}" > "$target_file"
                echo "Created: $target_file"
            fi
            CREATED_FILES+=("$target_file")
        fi
    done
done

echo
echo "=== Summary ==="
if [[ ${#CREATED_FILES[@]} -eq 0 ]]; then
    echo "All locale directories already have all required JSON files."
else
    echo "Total files ${DRY_RUN:+that would be }created: ${#CREATED_FILES[@]}"
fi
