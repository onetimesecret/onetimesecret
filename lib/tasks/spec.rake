# lib/tasks/spec.rake

# frozen_string_literal: true

# Integration Test Orchestration
# ==============================
#
# OneTimeSecret runs in discrete authentication modes (simple, full, disabled)
# where certain code paths are intentionally absent in certain modes. This is
# a security architecture decision, not a testing convenience: reduced attack
# surface means the code literally doesn't exist at runtime.
#
# Test process boundaries mirror deployment boundaries. Since we'd never run
# mode configurations together in production, we don't run their tests together
# either. Each mode gets its own RSpec invocation with the appropriate runtime
# configuration.
#
# Directory structure:
#
#   spec/integration/
#   ├── simple/    AUTHENTICATION_MODE=simple only
#   ├── full/      AUTHENTICATION_MODE=full only
#   ├── disabled/  AUTHENTICATION_MODE=disabled only
#   └── all/       Runs in ALL modes (infrastructure validation)
#
# The all/ specs run three times, once per mode. This is intentional: they
# validate that infrastructure (Puma forking, RabbitMQ, routing) works correctly
# regardless of which auth configuration is active. If someone accidentally
# couples infrastructure to auth mode, these specs catch it.
#
# Usage:
#
#   rake spec:integration:simple     # Run simple mode specs + all/
#   rake spec:integration:full       # Run full mode specs + all/
#   rake spec:integration:disabled   # Run disabled mode specs + all/
#   rake spec:integration:modes      # Run all modes sequentially
#
#   rake spec:unit                   # Unit tests (no auth mode dependency)
#   rake spec:all                    # Everything, all modes
#
# CI can either run spec:integration:modes sequentially or parallelize via
# matrix builds with AUTHENTICATION_MODE as the variable.
#
# See also: docs/adr/adr-001-test-process-boundaries.md

require 'rspec/core/rake_task'

INTEGRATION_MODES = %w[simple full disabled].freeze

namespace :spec do
  desc 'Run unit tests'
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = 'spec/unit/**/*_spec.rb'
  end

  desc 'Run CLI tests'
  RSpec::Core::RakeTask.new(:cli) do |t|
    t.pattern = 'spec/cli/**/*_spec.rb'
  end

  desc 'Run concurrency tests'
  RSpec::Core::RakeTask.new(:concurrency) do |t|
    t.pattern = 'spec/concurrency/**/*_spec.rb'
  end

  desc 'Run performance tests'
  RSpec::Core::RakeTask.new(:performance) do |t|
    t.pattern = 'spec/performance/**/*_spec.rb'
  end

  desc 'Run library tests'
  RSpec::Core::RakeTask.new(:lib) do |t|
    t.pattern = 'spec/lib/**/*_spec.rb'
  end

  desc 'Run onetime module tests'
  RSpec::Core::RakeTask.new(:onetime) do |t|
    t.pattern = 'spec/onetime/**/*_spec.rb'
  end

  namespace :integration do
    INTEGRATION_MODES.each do |mode|
      desc "Run integration specs for AUTHENTICATION_MODE=#{mode}"
      RSpec::Core::RakeTask.new(mode) do |t|
        t.pattern = [
          "spec/integration/#{mode}/**/*_spec.rb",
          'spec/integration/all/**/*_spec.rb'
        ]
      end

      # Ensure ENV is set before RSpec loads
      Rake::Task["spec:integration:#{mode}"].enhance ['spec:integration:set_mode']
    end

    task :set_mode do
      # Mode is inferred from the invoking task name
      # This task exists as an enhancement hook; actual ENV setting happens below
    end

    # Override each mode task to set ENV before execution
    INTEGRATION_MODES.each do |mode|
      task mode do
        ENV['AUTHENTICATION_MODE'] = mode
      end
    end

    desc 'Run integration specs for all authentication modes (sequentially)'
    task modes: INTEGRATION_MODES.map { |m| "spec:integration:#{m}" }

    desc 'Run only the shared integration specs (single mode, for fast feedback)'
    RSpec::Core::RakeTask.new(:shared_only) do |t|
      ENV['AUTHENTICATION_MODE'] ||= 'simple'
      t.pattern = 'spec/integration/all/**/*_spec.rb'
    end
  end

  desc 'Run all non-integration specs'
  task fast: %i[unit lib onetime cli]

  desc 'Run the complete test suite (all modes)'
  task all: ['spec:fast', 'spec:integration:modes']
end

# Default: run fast specs only (integration requires explicit mode choice)
task spec: 'spec:fast'
