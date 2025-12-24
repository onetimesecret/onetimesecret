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

# Auto-discover app-specific spec directories (co-located with their applications)
# Scans apps/{type}/{name}/spec for spec directories
APP_SPECS = Dir.glob('apps/*/*/spec').each_with_object({}) do |path, hash|
  # path: apps/api/v1/spec -> key: api:v1
  parts = path.split('/')[1..2] # ['api', 'v1']
  key = parts.join(':')
  hash[key] = path
end.freeze

namespace :spec do
  desc 'Run unit tests'
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = 'spec/unit/**/*_spec.rb'
  end

  desc 'Run CLI tests'
  RSpec::Core::RakeTask.new(:cli) do |t|
    t.pattern = 'spec/cli/**/*_spec.rb'
  end

  # App-specific specs (co-located with their applications)
  namespace :apps do
    APP_SPECS.each do |name, path|
      desc "Run specs for #{name}"
      RSpec::Core::RakeTask.new(name.tr(':', '_')) do |t|
        t.pattern = "#{path}/**/*_spec.rb"
      end
    end

    namespace :api do
      desc 'Run all API app specs'
      task all: APP_SPECS.keys.select { |k| k.start_with?('api:') }.map { |k| k.tr(':', '_') }
    end

    namespace :web do
      desc 'Run all web app specs'
      task all: APP_SPECS.keys.select { |k| k.start_with?('web:') }.map { |k| k.tr(':', '_') }
    end

    desc 'Run all app specs'
    task all: APP_SPECS.keys.map { |k| k.tr(':', '_') }
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

  desc 'Run all non-integration specs (unit, cli, apps)'
  task fast: %i[unit cli] + ['apps:all']

  desc 'Run the complete test suite'
  task all: ['spec:fast', 'spec:integration:all']
end

task spec: 'spec:fast'
