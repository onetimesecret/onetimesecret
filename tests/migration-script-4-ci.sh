#!/bin/bash
# 4_update_ci.sh - Update CI configuration for new test structure

set -e  # Exit on error

echo "=== Updating CI Configuration ==="

# Update GitHub Actions workflow
CI_FILE=".github/workflows/ci.yml"

if [ -f "$CI_FILE" ]; then
    echo "Updating $CI_FILE..."

    # Create backup
    cp "$CI_FILE" "${CI_FILE}.bak"

    # Update RSpec command - much simpler now!
    sed -i '' -e 's|bundle exec rspec \\|bundle exec rspec|g' "$CI_FILE"
    sed -i '' -e '/--require \.\/tests\/unit\/ruby\/rspec\/spec_helper\.rb/d' "$CI_FILE"
    sed -i '' -e '/--format progress/d' "$CI_FILE"
    sed -i '' -e '/--format json/d' "$CI_FILE"
    sed -i '' -e '/--out tmp\/rspec_results\.json/d' "$CI_FILE"
    sed -i '' -e '/\$(find tests\/unit\/ruby\/rspec/d' "$CI_FILE"

    # Update the dry-run command too
    sed -i '' -e 's|bundle exec rspec \\|bundle exec rspec --dry-run --format documentation|g' "$CI_FILE"
    sed -i '' -e '/--dry-run/,/\$(find tests/d' "$CI_FILE"

    echo "✓ Updated CI workflow"
else
    echo "WARNING: $CI_FILE not found"
fi

# Create a simple Rakefile for common test tasks
echo "Creating Rakefile..."
cat > Rakefile << 'EOF'
# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

desc "Run tryouts"
task :tryouts do
  sh "bundle exec try tryouts/**/*_try.rb"
end

desc "Run all tests"
task test: [:spec, :tryouts]

task default: :test
EOF

echo "✓ Created Rakefile"

# Update package.json test scripts if needed
if [ -f "package.json" ]; then
    echo "Checking package.json for test script updates..."
    # Note: This would need jq or similar to modify JSON properly
    echo "Note: Please manually review package.json test scripts"
fi

# Create a test runner script
echo "Creating test runner script..."
cat > run_tests.sh << 'EOF'
#!/bin/bash
# run_tests.sh - Run all test suites

set -e

echo "=== Running Test Suites ==="

# Ruby tests
echo "Running RSpec tests..."
bundle exec rspec

echo -e "\nRunning Tryouts..."
bundle exec try tryouts/**/*_try.rb

# Frontend tests
echo -e "\nRunning Vue unit tests..."
npm run test:unit

echo -e "\nRunning E2E tests..."
npm run test:e2e

echo -e "\n✓ All tests completed"
EOF

chmod +x run_tests.sh

echo "✓ CI configuration updated"
echo ""
echo "Next steps:"
echo "1. Review changes to .github/workflows/ci.yml"
echo "2. Test with: ./run_tests.sh"
echo "3. Run ./5_verify_migration.sh to verify the migration"
