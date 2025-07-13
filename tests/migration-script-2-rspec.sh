#!/bin/bash
# 2_migrate_rspec.sh - Migrate RSpec tests to spec/ directory

set -e  # Exit on error

echo "=== Migrating RSpec tests ==="

# Check if source directory exists
if [ ! -d "tests/unit/ruby/rspec" ]; then
    echo "ERROR: tests/unit/ruby/rspec directory not found!"
    exit 1
fi

# Move spec files preserving directory structure
echo "Moving RSpec test files..."
cd tests/unit/ruby/rspec

# Find all directories and create them in spec/unit
find . -type d -not -name "." -not -name "support" | while read -r dir; do
    mkdir -p "../../../../spec/unit/$dir"
done

# Move all spec files
find . -name "*_spec.rb" -not -path "./support/*" | while read -r file; do
    dest="../../../../spec/unit/$file"
    echo "Moving $file → spec/unit/$file"
    git mv "$file" "$dest" 2>/dev/null || mv "$file" "$dest"
done

# Move support files if they exist
if [ -d "support" ]; then
    echo "Moving support files..."
    find support -type f | while read -r file; do
        dest="../../../../spec/support/$file"
        mkdir -p "$(dirname "$dest")"
        echo "Moving $file → spec/support/$file"
        git mv "$file" "$dest" 2>/dev/null || mv "$file" "$dest"
    done
fi

cd ../../../../

# Move integration specs if they exist
if ls tests/integration/*.spec.rb 2>/dev/null; then
    echo "Moving integration specs..."
    for file in tests/integration/*.spec.rb; do
        if [ -f "$file" ]; then
            basename=$(basename "$file")
            echo "Moving $file → spec/integration/$basename"
            git mv "$file" "spec/integration/$basename" 2>/dev/null || mv "$file" "spec/integration/$basename"
        fi
    done
fi

# Update require statements in spec files
echo "Updating require statements..."
REQUIRE_ERRORS=""

find spec -name "*.rb" -type f | while read -r file; do
    echo "Processing requires in $file..."

    # Create backup first
    cp "$file" "${file}.bak"

    # More robust require statement updates
    ruby -i -pe '
      # Update spec_helper requires (various patterns)
      gsub(/require_relative\s+["\''\'']\.\.\/.*?spec_helper["\''\'']/, %{require "spec_helper"})
      gsub(/require_relative\s+["\''\''].*?\/spec_helper["\''\'']/, %{require "spec_helper"})
      gsub(/require\s+["\''\''].*?tests\/unit\/ruby\/rspec\/spec_helper["\''\'']/, %{require "spec_helper"})

      # Update other relative requires that point to old test structure
      gsub(/require_relative\s+["\''\'']\.\.\/\.\.\/\.\.\/tests\/unit\/ruby\//, %{require_relative "../../../tests/unit/ruby/"})
      gsub(/require_relative\s+["\''\'']\.\.\/tests\/unit\/ruby\//, %{require_relative "../../tests/unit/ruby/"})
    ' "$file"

    # Verify syntax after changes
    if ! ruby -c "$file" >/dev/null 2>&1; then
        echo "WARNING: Syntax error in $file after require updates"
        # Restore backup
        mv "${file}.bak" "$file"
        REQUIRE_ERRORS="$REQUIRE_ERRORS\n  $file"
    else
        # Clean up backup if successful
        rm -f "${file}.bak"
    fi
done

# Report any files that couldn't be updated
if [ -n "$REQUIRE_ERRORS" ]; then
    echo ""
    echo "⚠ WARNING: Could not update require statements in these files:"
    echo -e "$REQUIRE_ERRORS"
    echo "Please review these files manually."
    echo ""
fi

# Move the existing spec_helper if it exists in old location
if [ -f "tests/unit/ruby/rspec/spec_helper.rb" ]; then
    echo "Updating spec_helper.rb..."
    # Merge any unique content from old spec_helper
    echo "Note: Please manually review spec/spec_helper.rb for any custom configurations"
fi

echo "✓ RSpec migration completed"
echo ""
echo "Next steps:"
echo "1. Review moved files in spec/ directory"
echo "2. Test RSpec with: bundle exec rspec"
echo "3. Run ./3_migrate_tryouts.sh to migrate tryouts"
