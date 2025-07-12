#!/bin/bash
# 1_create_structure.sh - Create new test directory structure

set -e  # Exit on error

echo "=== Creating new test directory structure ==="

# Create root test directories
echo "Creating spec directories..."
mkdir -p spec/{unit,integration,support/{fixtures,helpers}}

echo "Creating tryouts directories..."
mkdir -p tryouts/{models,logic,utils,config,middleware,templates,integration,helpers}

# Create config files
echo "Creating .rspec configuration..."
cat > spec/.rspec << 'EOF'
--require spec_helper
--format documentation
--color
EOF

# Create root .rspec that points to spec/
cat > .rspec << 'EOF'
--require spec/spec_helper
EOF

# Create basic spec_helper.rb
echo "Creating spec_helper.rb..."
cat > spec/spec_helper.rb << 'EOF'
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/onetime'

# Use test configuration
OT::Configurator.path = File.join(__dir__, '../tests/unit/ruby/config.test.yaml')
OT.boot! :test

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/.rspec_status"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Load support files
  Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }
end
EOF

# Create basic tryouts configuration
echo "Creating tryouts configuration..."
cat > tryouts/.tryouts << 'EOF'
# Tryouts configuration
require_relative 'helpers/test_helpers'

# Set up test environment
ENV['RACK_ENV'] = 'test'
EOF

echo "✓ Directory structure created successfully"
echo ""
echo "Next steps:"
echo "1. Review the created structure"
echo "2. Run ./2_migrate_rspec.sh to migrate RSpec tests"
