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
chmod +x [1-5]_*.sh 3_migrate_tryouts.rb

# Run each script
for script in 1_create_structure.sh 2_migrate_rspec.sh 3_migrate_tryouts.rb 4_update_ci.sh 5_verify_migration.sh; do
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
