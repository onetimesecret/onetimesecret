# lib/tasks/spec.rake
#
# frozen_string_literal: true

# bundle exec rake spec:all

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
# Environment Variables:
#   RSPEC_OUTPUT_FILE - Path to JSON results file (e.g., tmp/rspec_results.json)
#                       When set, adds JSON formatter output for CI reporting
#
# See also: docs/adr/adr-007-test-process-boundaries.md

require 'rspec/core/rake_task'

INTEGRATION_MODES = %w[simple full disabled].freeze

# Build RSpec format options based on environment
# @return [String] RSpec format flags
def rspec_format_options
  opts = ['--format progress']
  if ENV['RSPEC_OUTPUT_FILE']
    opts << "--format json --out #{ENV['RSPEC_OUTPUT_FILE']}"
  end
  opts.join(' ')
end

# Auto-discover app-specific spec directories (co-located with their applications)
# Scans apps/{type}/{name}/spec for spec directories
APP_SPECS = Dir.glob('apps/*/*/spec').each_with_object({}) do |path, hash|
  # path: apps/api/v1/spec -> key: api:v1
  parts     = path.split('/')[1..2] # ['api', 'v1']
  key       = parts.join(':')
  hash[key] = path
end.freeze

namespace :spec do
  desc 'Run unit tests'
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern    = 'spec/unit/**/*_spec.rb'
    t.rspec_opts = rspec_format_options
  end

  desc 'Run CLI tests'
  RSpec::Core::RakeTask.new(:cli) do |t|
    t.pattern    = 'spec/cli/**/*_spec.rb'
    t.rspec_opts = rspec_format_options
  end

  # App-specific specs (co-located with their applications)
  namespace :apps do
    APP_SPECS.each do |name, path|
      desc "Run specs for #{name}"
      RSpec::Core::RakeTask.new(name.tr(':', '_')) do |t|
        t.pattern    = "#{path}/**/*_spec.rb"
        t.rspec_opts = rspec_format_options
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
        env        = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => mode,
        }
        # Full mode uses SQLite, excluding PostgreSQL-specific tests
        # Respect AUTH_DATABASE_URL if set (e.g., file-based SQLite from CI)
        tag_filter = ''
        if mode == 'full'
          env['AUTH_DATABASE_URL'] = ENV.fetch('AUTH_DATABASE_URL', 'sqlite::memory:')
          tag_filter               = '--tag ~postgres_database'
        end

        patterns = [
          "spec/integration/#{mode}",
          'spec/integration/all',
        ].join(' ')

        sh env, "bundle exec rspec #{patterns} #{tag_filter} #{rspec_format_options}"
      end
    end

    desc 'Run full mode with PostgreSQL'
    task 'full:postgres' do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => ENV.fetch('AUTH_DATABASE_URL',
          'postgresql://postgres@localhost:5432/onetime_auth_test',
        ),
      }
      sh env, "bundle exec rspec spec/integration/full --tag postgres_database #{rspec_format_options}"
    end

    desc 'Run all integration tests (all modes, isolated processes)'
    task all: INTEGRATION_MODES

    desc 'Run all integration tests including Postgres'
    task 'all:with_postgres': INTEGRATION_MODES + ['full:postgres']
  end

  desc 'Run all non-integration specs (unit, cli, apps)'
  task fast: [:unit, :cli] + ['apps:all']

  desc 'Run the complete test suite'
  task all: ['spec:fast', 'spec:integration:all']
end

# Tryouts test tasks
# Tryouts is a documentation-first Ruby testing framework where tests are plain
# Ruby code with comment expectations. These tasks mirror the RSpec structure.
namespace :try do
  desc 'Run unit tryouts'
  task :unit do
    patterns = %w[try/unit try/system].select { |p| Dir.exist?(p) }.join(' ')
    sh "bundle exec tryouts --agent #{patterns}" unless patterns.empty?
  end

  desc 'Run feature tryouts'
  task :features do
    sh 'bundle exec tryouts --agent try/features' if Dir.exist?('try/features')
  end

  namespace :integration do
    desc 'Run integration tryouts (simple mode only)'
    task :simple do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'simple',
      }

      patterns = %w[
        try/integration/middleware
        try/integration/boot
        try/integration/web
        try/integration/api
        try/integration/email
        try/integration/billing
        try/integration/homepage_bypass_header_integration_try.rb
        try/integration/homepage_mode_integration_try.rb
      ].select { |p| File.exist?(p) || Dir.exist?(p) }.join(' ')

      sh env, "bundle exec tryouts --agent #{patterns}" unless patterns.empty?
    end
  end

  desc 'Run all tryouts'
  task all: [:unit, :features, :'integration:simple']
end

# Billing VCR cassette recording tasks
# These tasks require a real Stripe test API key to record HTTP interactions
namespace :vcr do
  namespace :billing do
    desc 'Record NEW VCR cassettes for billing CLI specs (requires STRIPE_API_KEY)'
    task :record do
      unless ENV['STRIPE_API_KEY']
        abort <<~MSG
          ERROR: STRIPE_API_KEY is required to record VCR cassettes.

          Usage:
            STRIPE_API_KEY=sk_test_xxx rake vcr:billing:record      # record new only
            STRIPE_API_KEY=sk_test_xxx rake vcr:billing:rerecord  # re-record everything

          Get your test key from: https://dashboard.stripe.com/test/apikeys
        MSG
      end

      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'STRIPE_API_KEY' => ENV.fetch('STRIPE_API_KEY', nil),
        'VCR_MODE' => 'new_episodes',
        'DEFAULT_LOG_LEVEL' => 'error',
      }

      specs = %w[
        apps/web/billing/spec/cli/refunds_spec.rb
        apps/web/billing/spec/cli/invoices_spec.rb
        apps/web/billing/spec/cli/subscriptions_spec.rb
        apps/web/billing/spec/cli/products_spec.rb
      ].join(' ')

      p [:vcr_billing_record, specs, env.keys]

      sh env, "bundle exec rspec #{specs} #{rspec_format_options}"
    end

    desc 'Re-record ALL VCR cassettes for billing specs (requires STRIPE_API_KEY)'
    task :rerecord do
      unless ENV['STRIPE_API_KEY']
        abort <<~MSG
          ERROR: STRIPE_API_KEY is required to record VCR cassettes.

          Usage:
            STRIPE_API_KEY=sk_test_xxx rake vcr:billing:rerecord

          Get your test key from: https://dashboard.stripe.com/test/apikeys
        MSG
      end

      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'STRIPE_API_KEY' => ENV.fetch('STRIPE_API_KEY', nil),
        'VCR_MODE' => 'all',
        'DEFAULT_LOG_LEVEL' => 'error',
      }

      sh env, "bundle exec rspec apps/web/billing/spec #{rspec_format_options}"
    end

    desc 'Verify billing specs run with existing VCR cassettes (no API key needed)'
    task :verify do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'VCR_MODE' => 'none',
        'DEFAULT_LOG_LEVEL' => 'error',
      }

      sh env, "bundle exec rspec apps/web/billing/spec #{rspec_format_options}"
    end
  end
end

task spec: 'spec:fast'
