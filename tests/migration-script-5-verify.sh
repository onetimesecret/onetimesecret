#!/bin/bash
# 5_verify_migration.sh - Verify test migration and cleanup

set -e

echo "=== Verifying Test Migration ==="

# Check new directories exist
echo "Checking directory structure..."
for dir in spec tryouts; do
    if [ -d "$dir" ]; then
        echo "✓ $dir/ exists"
        find "$dir" -type f -name "*.rb" | wc -l | xargs echo "  Files found:"
    else
        echo "✗ $dir/ missing!"
    fi
done

# Check for leftover files
echo -e "\nChecking for unmigrated files..."
if [ -d "tests/unit/ruby/rspec" ]; then
    count=$(find tests/unit/ruby/rspec -name "*.rb" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "⚠ Found $count files still in tests/unit/ruby/rspec:"
        find tests/unit/ruby/rspec -name "*.rb" | head -10
    fi
fi

if [ -d "tests/unit/ruby/try" ]; then
    count=$(find tests/unit/ruby/try -name "*.rb" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo "⚠ Found $count files still in tests/unit/ruby/try:"
        find tests/unit/ruby/try -name "*.rb" | head -10
    fi
fi

# Test basic functionality
echo -e "\nTesting basic commands..."
echo "RSpec: bundle exec rspec --version"
bundle exec rspec --version || echo "✗ RSpec not working"

echo -e "\nTryouts: bundle exec try --version"
bundle exec try --version || echo "✗ Tryouts not working"

# Summary report
echo -e "\n=== Migration Summary ==="
echo "RSpec tests: $(find spec -name "*_spec.rb" 2>/dev/null | wc -l) files"
echo "Tryout tests: $(find tryouts -name "*_try.rb" 2>/dev/null | wc -l) files"
echo "Frontend tests: $(find tests/unit/vue -name "*.spec.ts" 2>/dev/null | wc -l) Vue unit tests"
echo "E2E tests: $(find tests/integration/web -name "*.spec.ts" 2>/dev/null | wc -l) Playwright tests"

# Cleanup options
echo -e "\n=== Cleanup Options ==="
echo "To remove old empty directories:"
echo "  find tests/unit/ruby -type d -empty -delete"
echo ""
echo "To remove backup files:"
echo "  rm .github/workflows/ci.yml.bak"

# Git status
echo -e "\n=== Git Status ==="
git status --short | head -20

echo -e "\n✓ Verification complete"
