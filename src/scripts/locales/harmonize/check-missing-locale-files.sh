#!/usr/bin/env bash
#
# Script: check-missing-locale-files.sh
# Purpose: Check for and optionally create missing locale JSON files
# Usage: ./src/scripts/locales/harmonize/check-missing-locale-files.sh [--dry-run] [--source LOCALE]
#
# Options:
#   --dry-run         Only report what would be created, don't write files
#   --source LOCALE   Use specified locale as source (default: en)
#
# Source locale files (from en/ by default):
#   _common.json, account-billing.json, account.json, auth-full.json, auth.json,
#   colonel.json, dashboard.json, email.json, error-pages.json, feature-branding.json,
#   feature-domains.json, feature-feedback.json, feature-incoming.json,
#   feature-organizations.json, feature-regions.json, feature-secrets.json,
#   feature-testimonials.json, feature-translations.json, homepage.json, layout.json,
#   uncategorized.json
#
# Target locale directories (excluding source):
#   ar, bg, ca_ES, cs, da_DK, de, de_AT, el_GR, es, fr_CA, fr_FR, he, hu, it_IT,
#   ja, ko, mi_NZ, nl, pl, pt_BR, pt_PT, ru, sl_SI, sv_SE, tr, uk, vi, zh
#
# Exit codes:
#   0 - Success (files created or all files already exist)
#   1 - Error (source directory not found, no JSON files found, etc.)

set -euo pipefail

# Determine project root relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOCALES_DIR="${PROJECT_ROOT}/src/locales"

# Default values
DRY_RUN=false
SOURCE_LOCALE="en"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --source)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --source requires a locale argument"
                exit 1
            fi
            SOURCE_LOCALE="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: $0 [--dry-run] [--source LOCALE]"
            exit 1
            ;;
    esac
done

SOURCE_DIR="${LOCALES_DIR}/${SOURCE_LOCALE}"

# Print mode header
if [[ "$DRY_RUN" == true ]]; then
    echo "=== DRY RUN MODE - No files will be created ==="
    echo
fi

echo "Source locale: ${SOURCE_LOCALE}"
echo "Source directory: ${SOURCE_DIR}"
echo

# Verify source locale directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: Source locale directory not found: $SOURCE_DIR"
    exit 1
fi

# Get list of JSON files from source locale (just the filenames)
SOURCE_JSON_FILES=()
for f in "$SOURCE_DIR"/*.json; do
    if [[ -f "$f" ]]; then
        SOURCE_JSON_FILES+=("$(basename "$f")")
    fi
done

if [[ ${#SOURCE_JSON_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No JSON files found in source locale: ${SOURCE_LOCALE}"
    exit 1
fi

echo "Found ${#SOURCE_JSON_FILES[@]} JSON files in source locale (${SOURCE_LOCALE}):"
printf "  - %s\n" "${SOURCE_JSON_FILES[@]}"
echo

# Track counts
TOTAL_MISSING=0
TOTAL_CREATED=0

# Track missing files for summary (locale:count format)
LOCALES_WITH_MISSING=""

# Iterate through each locale directory
for locale_dir in "$LOCALES_DIR"/*/; do
    locale_name=$(basename "$locale_dir")

    # Skip source locale
    if [[ "$locale_name" == "$SOURCE_LOCALE" ]]; then
        continue
    fi

    # Check each expected JSON file
    locale_missing_count=0
    for json_file in "${SOURCE_JSON_FILES[@]}"; do
        target_file="${locale_dir}${json_file}"

        if [[ ! -f "$target_file" ]]; then
            ((locale_missing_count++)) || true
            ((TOTAL_MISSING++)) || true

            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would create: ${locale_name}/${json_file}"
            else
                echo "{}" > "$target_file"
                echo "Created: ${locale_name}/${json_file}"
                ((TOTAL_CREATED++)) || true
            fi
        fi
    done

    if [[ $locale_missing_count -gt 0 ]]; then
        LOCALES_WITH_MISSING="${LOCALES_WITH_MISSING}${locale_name}:${locale_missing_count}\n"
    fi
done

echo
echo "=== Summary ==="
echo "Source locale: ${SOURCE_LOCALE}"
echo "Source files: ${#SOURCE_JSON_FILES[@]}"
echo

if [[ $TOTAL_MISSING -eq 0 ]]; then
    echo "All locale directories already have all required JSON files."
    exit 0
fi

# Report by locale
echo "Missing files by locale:"
echo -e "$LOCALES_WITH_MISSING" | while IFS=: read -r locale count; do
    if [[ -n "$locale" ]]; then
        echo "  ${locale}: ${count} file(s)"
    fi
done
echo

if [[ "$DRY_RUN" == true ]]; then
    echo "Total files that would be created: ${TOTAL_MISSING}"
else
    echo "Total files created: ${TOTAL_CREATED}"
fi

exit 0
