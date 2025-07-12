#!/bin/bash
# 6_migrate_frontend.sh - Migrate frontend tests to co-located structure

set -e  # Exit on error

echo "=== Migrating Frontend tests ==="

# Check if source directories exist
if [ ! -d "tests/unit/vue" ]; then
    echo "ERROR: tests/unit/vue directory not found!"
    exit 1
fi

# Create tests directory under src for non-co-locatable tests
echo "Creating src/tests directory for test utilities..."
mkdir -p src/tests/{integration,fixtures,setup}

# Move test setup files first
echo "Moving test setup files..."
for setup_file in tests/unit/vue/setup*.ts tests/unit/vue/types.d.ts; do
    if [ -f "$setup_file" ]; then
        basename=$(basename "$setup_file")
        echo "Moving $setup_file → src/tests/setup/$basename"
        git mv "$setup_file" "src/tests/setup/$basename" 2>/dev/null || mv "$setup_file" "src/tests/setup/$basename"
    fi
done

# Move fixtures to central location
if [ -d "tests/unit/vue/fixtures" ]; then
    echo "Moving fixtures..."
    git mv "tests/unit/vue/fixtures" "src/tests/fixtures" 2>/dev/null || mv "tests/unit/vue/fixtures" "src/tests/fixtures"
fi

# Function to co-locate test files
colocate_tests() {
    local test_dir="$1"
    local src_dir="$2"

    if [ ! -d "$test_dir" ]; then
        return
    fi

    echo "Co-locating tests from $test_dir to $src_dir..."

    # Find all test files in the test directory
    find "$test_dir" -name "*.spec.ts" -o -name "*.test.ts" | while read -r test_file; do
        # Get relative path from test directory
        rel_path=$(realpath --relative-to="$test_dir" "$test_file")

        # Create corresponding directory structure in src
        src_dest_dir="$src_dir/$(dirname "$rel_path")"
        mkdir -p "$src_dest_dir"

        # Move the test file
        dest="$src_dest_dir/$(basename "$test_file")"
        echo "  Moving $test_file → $dest"
        git mv "$test_file" "$dest" 2>/dev/null || mv "$test_file" "$dest"
    done
}

# Co-locate unit tests for each category
colocate_tests "tests/unit/vue/components" "src/components"
colocate_tests "tests/unit/vue/composables" "src/composables"
colocate_tests "tests/unit/vue/router" "src/router"
colocate_tests "tests/unit/vue/schemas" "src/schemas"
colocate_tests "tests/unit/vue/services" "src/services"
colocate_tests "tests/unit/vue/stores" "src/stores"
colocate_tests "tests/unit/vue/utils" "src/utils"

# Move integration tests to src/tests/integration
if [ -d "tests/integration/web" ]; then
    echo "Moving web integration tests..."
    git mv "tests/integration/web" "src/tests/integration/web" 2>/dev/null || mv "tests/integration/web" "src/tests/integration/web"
fi

# Move any remaining files in tests/unit/vue to src/tests
echo "Moving any remaining Vue test files..."
if [ -d "tests/unit/vue" ]; then
    find tests/unit/vue -name "*.ts" -o -name "*.js" -o -name "*.vue" | while read -r file; do
        if [ -f "$file" ]; then
            basename=$(basename "$file")
            echo "Moving remaining $file → src/tests/$basename"
            git mv "$file" "src/tests/$basename" 2>/dev/null || mv "$file" "src/tests/$basename"
        fi
    done
fi

# Update vitest configuration to include co-located tests
echo "Updating vitest configuration..."
if [ -f "vitest.config.ts" ]; then
    # Create backup
    cp vitest.config.ts vitest.config.ts.bak

    # Update test file patterns
    node -e "
    const fs = require('fs');
    let config = fs.readFileSync('vitest.config.ts', 'utf8');

    // Update include patterns to find co-located tests
    if (config.includes('include:')) {
        config = config.replace(
            /include:\s*\[[^\]]*\]/,
            'include: [\"src/**/*.{test,spec}.{js,ts,tsx}\", \"src/tests/**/*.{js,ts,tsx}\"]'
        );
    } else if (config.includes('test:')) {
        config = config.replace(
            /(test:\s*{[^}]*)/,
            '\$1\n    include: [\"src/**/*.{test,spec}.{js,ts,tsx}\", \"src/tests/**/*.{js,ts,tsx}\"],'
        );
    }

    fs.writeFileSync('vitest.config.ts', config);
    " || echo "Manual vitest.config.ts update needed"
fi

# Update Vite config to exclude test files from builds
echo "Checking vite.config.ts for test file exclusion..."
if [ -f "vite.config.ts" ]; then
    if ! grep -q "\.spec\." vite.config.ts && ! grep -q "\.test\." vite.config.ts; then
        echo "Note: Vite config may need manual update to exclude test files from production builds"
        echo "Add patterns like '**/*.{test,spec}.{js,ts,tsx}' to build.rollupOptions.external"
    fi
fi

# Update package.json test scripts if needed
echo "Checking package.json test scripts..."
if [ -f "package.json" ]; then
    echo "Note: Please verify package.json test scripts work with new test locations"
fi

echo "✓ Frontend test migration completed"
echo ""
echo "Files migrated:"
echo "  - Vue unit tests → co-located under src/"
echo "  - Test setup files → src/tests/setup/"
echo "  - Fixtures → src/tests/fixtures/"
echo "  - Web integration tests → src/tests/integration/web/"
echo ""
echo "Next steps:"
echo "1. Verify vitest.config.ts includes new test patterns"
echo "2. Check vite.config.ts excludes test files from builds"
echo "3. Test frontend tests with: npm run test:unit"
echo "4. Update .github/workflows/ci.yml if needed"
