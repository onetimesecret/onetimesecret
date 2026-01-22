#!/usr/bin/env bash
#
# Export completed translations and commit each locale separately.
#
# Iterates through locale directories in locales/content/, runs export.py
# for each, and commits with stats from the translation database.
#
# Usage:
#   ./export-and-commit.sh [--dry-run] [--harmonize]
#
# Options:
#   --dry-run     Show what would be done without making changes
#   --harmonize   Run harmonize.py --create-missing before export

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCALES_DIR="$(dirname "$SCRIPT_DIR")"
CONTENT_DIR="$LOCALES_DIR/content"

DRY_RUN=false
HARMONIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --harmonize)
            HARMONIZE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ "$DRY_RUN" == true ]]; then
    echo "=== DRY RUN MODE ==="
fi

# Get list of locale directories (exclude en, hidden dirs)
get_locales() {
    find "$CONTENT_DIR" -mindepth 1 -maxdepth 1 -type d \
        ! -name ".*" ! -name "en" \
        -exec basename {} \; | sort
}

# Get stats for a locale as "completed/total"
get_stats() {
    local locale="$1"
    python "$SCRIPT_DIR/tasks/next.py" "$locale" --stats --json 2>/dev/null | \
        python -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('completed',0)}/{sum(d.values())}\")" 2>/dev/null || echo "0/0"
}

# Main loop
main() {
    local exported=0
    local skipped=0

    echo "Scanning locales in $CONTENT_DIR"
    echo

    for locale in $(get_locales); do
        # Harmonize first if requested (creates missing files)
        if [[ "$HARMONIZE" == true ]]; then
            python "$SCRIPT_DIR/migrate/harmonize.py" "$locale" --create-missing -q 2>/dev/null || true
        fi

        # Skip if no completed tasks to export
        if ! python "$SCRIPT_DIR/migrate/export.py" "$locale" --quiet 2>/dev/null; then
            ((skipped++)) || true
            continue
        fi

        # Get stats for commit message
        stats=$(get_stats "$locale")

        # Check if there are actual changes
        if ! git diff --quiet "$CONTENT_DIR/$locale" 2>/dev/null; then
            echo "[$locale] Exported translations ($stats)"

            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  Would commit: Update $locale translations ($stats)"
            else
                # Stage and commit
                git add "$CONTENT_DIR/$locale"
                git commit -m "Update $locale translations ($stats)"
            fi
            ((exported++)) || true
        else
            echo "[$locale] No changes to commit"
            ((skipped++)) || true
        fi
    done

    echo
    echo "Done: $exported locales exported, $skipped skipped"
}

main "$@"
