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
