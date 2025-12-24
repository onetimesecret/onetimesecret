# lib/tasks/spec.rake
#
# frozen_string_literal: true

# Integration Test Architecture
# =============================
#
# OneTimeSecret runs in discrete authentication modes (simple, full, disabled)
# where code paths are intentionally absent in certain modes to reduce attack
# surface. This is a security architecture decision, not a configuration toggle.
#
# Test process boundaries mirror deployment boundaries: you would never run
# mode "full" and mode "simple" in the same production process, so testing them
# together would validate a configuration that doesn't exist. Each mode gets
# its own RSpec invocation with the appropriate runtime environment.
#
# Directory structure:
#
#   spec/integration/
#   ├── simple/     # AUTHENTICATION_MODE=simple only
#   ├── full/       # AUTHENTICATION_MODE=full only
#   ├── disabled/   # AUTHENTICATION_MODE=disabled only
#   └── all/        # Runs in ALL modes (infrastructure validation)
#
# The "all/" specs run three times (once per mode). This is intentional: they
# validate that infrastructure (Puma forking, RabbitMQ, routing) works correctly
# regardless of which auth layer sits above it. If someone accidentally couples
# infrastructure to auth mode, these specs catch it.
#
# The full:postgres variant exists because SQLite and PostgreSQL have different
# trigger/constraint behaviors. CI runs both; local development defaults to
# SQLite for speed.
#
# See also: docs/adr/adr-007-test-process-boundaries.md

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

  namespace :integration do
    INTEGRATION_MODES.each do |mode|
      desc "Run integration specs for AUTHENTICATION_MODE=#{mode}"
      task mode do
        env = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => mode
        }
        env['AUTH_DATABASE_URL'] = 'sqlite::memory:' if mode == 'full'

        patterns = [
          "spec/integration/#{mode}",
          "spec/integration/all"
        ].join(' ')

        sh env, "bundle exec rspec #{patterns} --format documentation"
      end
    end

    desc 'Run full mode with PostgreSQL'
    task 'full:postgres' do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'postgresql://postgres@localhost:5432/onetime_auth_test'
      }
      sh env, 'bundle exec rspec spec/integration/full --tag postgres_database --format documentation'
    end

    desc 'Run all integration tests (all modes, isolated processes)'
    task all: INTEGRATION_MODES

    desc 'Run all integration tests including Postgres'
    task 'all:with_postgres': INTEGRATION_MODES + ['full:postgres']
  end

  desc 'Run all non-integration specs'
  task fast: %i[unit cli]

  desc 'Run the complete test suite'
  task all: ['spec:fast', 'spec:integration:all']
end

task spec: 'spec:fast'
