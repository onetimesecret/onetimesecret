#!/bin/bash
# migration-script-rollback.sh - Rollback test migration changes

set -e  # Exit on error

echo "=== Test Migration Rollback ==="
echo "This will undo the test structure migration."
echo ""
read -p "Continue with rollback? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 1
fi

# Check git status
if ! git status --porcelain | grep -q "^"; then
    echo "Working directory is clean, proceeding with rollback..."
else
    echo "Working directory has uncommitted changes. Please commit or stash them first."
    git status --short
    exit 1
fi

# Find migration commits
echo "Finding migration commits..."
migration_commits=$(git log --oneline --grep="migration\|migrate\|test.*structure\|test.*reorganiz" -n 10 | cut -d' ' -f1)

if [ -z "$migration_commits" ]; then
    echo "No migration commits found in recent history"
    exit 1
fi

echo "Recent migration-related commits:"
git log --oneline --grep="migration\|migrate\|test.*structure\|test.*reorganiz" -n 10

echo ""
read -p "Enter commit hash to rollback to (or 'auto' for automatic detection): " target_commit

if [ "$target_commit" = "auto" ]; then
    # Try to find the commit before migration started
    target_commit=$(git log --oneline --grep="migration\|migrate\|test.*structure" -n 1 --format="%H^")
    echo "Auto-detected rollback target: $target_commit"
fi

# Verify commit exists
if ! git rev-parse --verify "$target_commit" >/dev/null 2>&1; then
    echo "Invalid commit hash: $target_commit"
    exit 1
fi

# Create rollback branch
rollback_branch="rollback-test-migration-$(date +%Y%m%d-%H%M%S)"
echo "Creating rollback branch: $rollback_branch"
git checkout -b "$rollback_branch"

# Perform rollback
echo "Rolling back to $target_commit..."
git reset --hard "$target_commit"

echo ""
echo "✓ Rollback completed"
echo "Current branch: $rollback_branch"
echo ""
echo "To confirm rollback:"
echo "  git log --oneline -5"
echo ""
echo "To return to original state:"
echo "  git checkout main"  # or whatever the original branch was
echo "  git branch -D $rollback_branch"
