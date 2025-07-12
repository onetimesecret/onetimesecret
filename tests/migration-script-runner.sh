#!/bin/bash
# migrate_all.sh - Run all migration scripts in sequence

set -e

echo "=== OneTimeSecret Test Migration ==="
echo "This will reorganize your test structure."
echo "Current tests are failing, so risk is low."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled"
    exit 1
fi

# Make all scripts executable
chmod +x migration-script-[1-5]-*.sh migration-script-3-tryouts.rb

# Run each script
for script in migration-script-1-structure.sh migration-script-2-rspec.sh migration-script-3-tryouts.rb migration-script-4-ci.sh migration-script-5-verify.sh; do
    echo ""
    echo "Running $script..."
    ./"$script"

    read -p "Continue to next step? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Migration paused at $script"
        exit 0
    fi
done

echo ""
echo "=== Migration Complete ==="
echo "Review the changes and commit when ready:"
echo "  git add -A"
echo "  git commit -m 'Reorganize test structure to follow Ruby conventions'"
