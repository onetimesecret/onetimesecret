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
#   apps/web/auth/spec/integration/
#   └── full/           # Full-mode specs (Rodauth, OmniAuth, SSO)
#       ├── basicauth/  # BasicAuth contract tests
#       └── migrations/ # DB migration tests
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

PG_TEST_DATABASE_URL   = ENV.fetch(
  'AUTH_DATABASE_URL_PG',
  'postgresql://onetime_user:testpass@localhost:5432/onetime_auth_test',
)
PG_TEST_MIGRATIONS_URL = ENV.fetch(
  'AUTH_DATABASE_URL_MIGRATIONS_PG',
  'postgresql://onetime_migrator:migratepass@localhost:5432/onetime_auth_test',
)

# Build RSpec format options based on environment
#
# +suffix+ names the JSON results file for ONE rspec invocation. A lane runs
# several invocations in a single job under one RSPEC_OUTPUT_FILE, and rspec
# truncates --out on open, so unsuffixed invocations leave only the last one's
# results behind and CI aggregates a fraction of the run. Pass a suffix from
# every task a lane can invoke alongside another (spec:integration:full:mfa has
# done this by hand since it was added). The names must be stable and distinct:
# .github/actions/run-test-lane uploads them by the glob tmp/<stem>*.json.
#
# @param suffix [String, nil] per-invocation discriminator for the JSON file
# @return [String] RSpec format flags
def rspec_format_options(suffix = nil)
  opts    = ['--format progress']
  if (out = ENV.fetch('RSPEC_OUTPUT_FILE', nil))
    out = "#{out.delete_suffix('.json')}_#{suffix}.json" if suffix
    opts << "--format json --out #{out}"
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

# spec:fast pattern set
# =====================
#
# spec:fast is THREE rspec processes (spec:root_fast, spec:apps_fast, and
# spec:apps_config_ru), not one per spec tree. The split is a behaviour boundary,
# not a performance
# compromise: apps/web/billing/spec/support/billing_spec_helper.rb registers VCR
# around-hooks and billing stubs on the GENERIC type: :cli key, and
# spec/cli/**/*_spec.rb declares type: :cli — merging the two into one process
# would wrap all 430 CLI examples in cassettes and stub Object#sleep under them.
# The trees that carry no exclusions (spec/unit, spec/cli, spec/lib) keep their
# own process for that reason.
#
# HARD RULE for anyone editing these patterns: never mix a 'spec/…'-prefixed
# include pattern with an 'apps/…'-prefixed exclude pattern in ONE invocation.
# rspec resolves both globs against each checked path, and
# Configuration#file_glob_from (rspec-core 4.0.0.beta1 configuration.rb:2071)
# returns a pattern verbatim only when it prefix-matches that path. The default
# checked path is 'spec', so an include of 'spec/unit/**' is used verbatim (i.e.
# repo-wide) while an exclude of 'apps/*/*/spec/integration/**' gets joined onto
# 'spec/' and matches nothing — silently leaking 807 examples from 52
# integration spec files into the fast lane. If a single invocation is ever
# wanted, the only safe spellings are explicit directories with a
# directory-relative exclude ('**/integration/**/*_spec.rb'), or both patterns
# made absolute. `rake spec:verify_selection` fails on the mistake.
ROOT_FAST_PATTERN = 'spec/unit/**/*_spec.rb,spec/cli/**/*_spec.rb,spec/lib/**/*_spec.rb'
APPS_FAST_PATTERN = 'apps/*/*/spec/**/*_spec.rb'
APPS_FAST_EXCLUDE = [
  'apps/*/*/spec/integration/**/*_spec.rb',
  'apps/web/core/spec/controllers/config_generator_spec.rb',
  'apps/web/core/spec/controllers/page_bootstrap_me_spec.rb',
].join(',')

# Carried over VERBATIM from the per-app tasks, and inert in both places today.
# rspec-core 4.0.0.beta1 ANDs exclusion filters (MetadataFilter.apply? uses
# all?), and spec/support/postgres_mode_suite_database.rb:378 contributes a
# second exclusion rule whenever PostgreSQL is absent — which it always is here.
# The consequence is that these flags exclude nothing and roughly 500
# :integration-tagged billing examples run inside spec:fast right now.
#
# Do not "fix" this alongside a consolidation: making the tags bite again would
# silently REMOVE those ~500 examples from the fast lane, which is a lane
# membership decision, not a refactor. Keeping the flags means an rspec-core
# upgrade that restores OR-semantics changes what spec:fast covers without a
# diff, so the follow-up is to decide the membership explicitly and then either
# retag the billing specs or drop these flags.
APPS_FAST_TAG_FILTERS = '--tag ~postgres_database --tag ~integration'

# The legs `spec:fast` runs, in order. See the task itself for why they are
# collected rather than chained as prerequisites.
FAST_LEGS = %w[spec:root_fast spec:apps_fast spec:apps_config_ru].freeze

namespace :spec do
  # The `spec:fast` invocations. Their patterns are documented at
  # ROOT_FAST_PATTERN above; `rake spec:verify_selection` proves they select
  # exactly what the per-tree tasks below select.
  desc 'Run unit + CLI + lib specs (one process)'
  RSpec::Core::RakeTask.new(:root_fast) do |t|
    t.pattern    = ROOT_FAST_PATTERN
    t.rspec_opts = rspec_format_options('root_fast')
  end

  desc 'Run every app spec tree except integration (one process)'
  RSpec::Core::RakeTask.new(:apps_fast) do |t|
    t.pattern         = APPS_FAST_PATTERN
    t.exclude_pattern = APPS_FAST_EXCLUDE
    t.rspec_opts      = "#{rspec_format_options('apps_fast')} #{APPS_FAST_TAG_FILTERS}"
  end

  # These Rack specs boot config.ru, which reconfigures process-global runtime
  # state. Keep them outside the merged apps process so their boot cannot alter
  # the model and controller specs that follow.
  desc 'Run config.ru controller specs in an isolated process'
  RSpec::Core::RakeTask.new(:apps_config_ru) do |t|
    t.pattern    = 'apps/web/core/spec/controllers/{config_generator,page_bootstrap_me}_spec.rb'
    t.rspec_opts = rspec_format_options('apps_config_ru')
  end

  # Per-tree tasks below are kept for targeted runs (`rake spec:apps:web_auth`)
  # and are what smoke:rspec invokes. They are no longer how spec:fast runs.
  desc 'Run unit tests'
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern    = 'spec/unit/**/*_spec.rb'
    t.rspec_opts = rspec_format_options('unit')
  end

  desc 'Run CLI tests'
  RSpec::Core::RakeTask.new(:cli) do |t|
    t.pattern    = 'spec/cli/**/*_spec.rb'
    t.rspec_opts = rspec_format_options('cli')
  end

  # App-specific specs (co-located with their applications)
  # NOTE: Excludes integration tests by both directory (integration/) and tag (:integration).
  # Integration tests run via spec:integration tasks with the correct AUTHENTICATION_MODE
  # and database setup. Also excludes :postgres_database tagged tests.
  namespace :apps do
    APP_SPECS.each do |name, path|
      desc "Run specs for #{name}"
      RSpec::Core::RakeTask.new(name.tr(':', '_')) do |t|
        t.pattern         = "#{path}/**/*_spec.rb"
        t.exclude_pattern = "#{path}/integration/**/*_spec.rb"
        t.rspec_opts      = "#{rspec_format_options(name.tr(':', '_'))} #{APPS_FAST_TAG_FILTERS}"
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

  desc 'Run ACME internal app specs'
  RSpec::Core::RakeTask.new(:acme) do |t|
    t.pattern    = 'apps/internal/acme/spec/**/*_spec.rb'
    t.rspec_opts = rspec_format_options('acme')
  end

  namespace :integration do
    INTEGRATION_MODES.each do |mode|
      desc "Run integration specs for AUTHENTICATION_MODE=#{mode}"
      task mode do
        env        = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => mode,
        }
        # Full mode uses SQLite by default, excluding PostgreSQL-specific
        # tests. Hardcoded to prevent ambient AUTH_DATABASE_URL (from dev
        # .env via direnv) from leaking in and wiping a non-test database.
        tag_filter = ''
        if mode == 'full'
          env['AUTH_DATABASE_URL'] = 'sqlite::memory:'
          env['ORGS_SSO_ENABLED']  = 'true'
          tag_filter               = '--tag ~postgres_database'
        end

        patterns = [
          *Dir.glob("apps/*/*/spec/integration/#{mode}"),
          "spec/integration/#{mode}",
          'spec/integration/all',
        ]

        sh env, "bundle exec rspec #{patterns.join(' ')} #{tag_filter} #{rspec_format_options}"

        # AUTH_MFA_ENABLED specs need a SEPARATE process: Auth::Config is
        # one-shot (auth-config-one-shot.md), so the shared full-mode process
        # above — booted with MFA off — can never load the OTP feature set.
        Rake::Task['spec:integration:full:mfa'].invoke if mode == 'full'
      end
    end

    desc 'Run full-mode specs that require AUTH_MFA_ENABLED=true (own process)'
    task 'full:mfa' do
      # Own process because Auth::Config configures exactly once per process
      # (auth-config-one-shot.md): the Rodauth OTP feature set can only exist
      # in a boot where AUTH_MFA_ENABLED was set from the start. SQLite lane
      # only, mirroring the default full-mode environment above.
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'ORGS_SSO_ENABLED' => 'true',
        'AUTH_MFA_ENABLED' => 'true',
      }

      patterns = Dir.glob('apps/*/*/spec/integration/full_mfa')
      if patterns.empty?
        warn '[spec:integration:full:mfa] no full_mfa spec directories found; nothing to run'
        next
      end

      # Distinct results file so this lane never clobbers the main full-mode
      # JSON output when CI sets RSPEC_OUTPUT_FILE for the parent task.
      sh env, "bundle exec rspec #{patterns.join(' ')} --tag ~postgres_database #{rspec_format_options('mfa')}"
    end

    desc 'Run full mode with PostgreSQL (PG-only specs)'
    task 'full:postgres' do
      env      = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
        'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
      }
      patterns = [
        *Dir.glob('apps/*/*/spec/integration/full'),
        'spec/integration/full',
      ]
      sh env, "bundle exec rspec #{patterns.join(' ')} --tag postgres_database #{rspec_format_options}"
    end

    desc 'Run DB-agnostic full mode specs against PostgreSQL'
    task 'full:agnostic_on_pg' do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
        'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
        'ORGS_SSO_ENABLED' => 'true',
      }

      # Root-level specs MUST load before app-level specs. The root spec_helper
      # registers define_derived_metadata for :full_auth_mode (matched by file
      # path). If app-level specs load first, their RSpec.describe creates
      # metadata before the derivation rule exists, so :full_auth_mode is never
      # set and FullModeSuiteDatabase.setup! never fires — leaving the PG
      # database without tables (seed-dependent "accounts does not exist").
      patterns = [
        'spec/integration/full',
        'spec/integration/all',
        *Dir.glob('apps/*/*/spec/integration/full'),
      ]
      sh env, "bundle exec rspec #{patterns.join(' ')} --exclude-pattern '**/migrations/*_{postgres,sqlite}_spec.rb,**/{postgres,sqlite}*_spec.rb' #{rspec_format_options}"
    end

    # Migration/trigger suites, run by .github/workflows/migration-tests.yml
    # via the migrations-* lanes (tests/lanes/). Separate from full:postgres
    # because migration-tests is a paths-filtered workflow that needs fast,
    # focused feedback on schema changes — not the whole full-mode matrix.
    namespace :migrations do
      desc 'Run SQLite migration/trigger specs'
      task :sqlite do
        env = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => 'full',
          'AUTH_DATABASE_URL' => 'sqlite::memory:',
        }
        sh env, "bundle exec rspec spec/integration/full/database_triggers/sqlite_spec.rb #{rspec_format_options}"
      end

      desc 'Run PostgreSQL migration/trigger/infrastructure specs'
      task :postgres do
        env   = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => 'full',
          'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
          'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
        }
        specs = %w[
          spec/integration/full/database_triggers/postgres_spec.rb
          spec/integration/full/postgres_infrastructure_spec.rb
        ].join(' ')
        sh env, "bundle exec rspec #{specs} --tag postgres_database #{rspec_format_options}"
      end

      desc 'Verify migrations use the elevated connection (dual-URL config)'
      task :verify_dual_url do
        env    = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => 'full',
          'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
          'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
        }
        script = <<~RUBY
          require "bundler/setup"
          require_relative "lib/onetime"
          require_relative "apps/web/auth/database"

          # This should use AUTH_DATABASE_URL_MIGRATIONS for migrations
          # and AUTH_DATABASE_URL for normal operations
          Auth::Database.ensure_migrations!

          puts "Dual URL configuration verified"
        RUBY
        sh env, 'bundle', 'exec', 'ruby', '-e', script
      end
    end

    desc 'Run all integration tests (all modes, isolated processes)'
    task all: INTEGRATION_MODES

    desc 'Run all integration tests including Postgres'
    task 'all:with_postgres': INTEGRATION_MODES + ['full:postgres']
  end

  # API contract specs (spec/api/) are organized by API surface and version
  # (v1/v2/v3, account, domains) — a DIFFERENT axis than auth mode. They are
  # NOT folded into spec:integration:<mode> on purpose: doing so would re-mix
  # the API-contract and auth-mode taxonomies. Most specs are mode-agnostic
  # entitlement/wire-format checks; the few that need a specific mode set it
  # themselves. Real Valkey on port 2163 is required (type: :integration).
  #
  # NOTE: a subset currently fails against the membership-based entitlement
  # contract (#3225 / ADR-012 Stage 3): they stub the removed `logic.org` and
  # gate on `org.can?`, but production now checks `auth_membership.can?`. These
  # were latent because nothing ran them. Repair is tracked as #3225 follow-up;
  # this lane makes the drift visible. Not yet wired into the CI gate.
  #
  # Deliberately NOT a prerequisite of spec:all while red: `sh` raises on a
  # non-zero exit, so folding it in would hard-fail `rake spec:all` locally on
  # the known #3225 drift. CI runs this lane via a dedicated non-blocking step
  # (continue-on-error) — see .github/workflows/ci.yml — so visibility is kept
  # without blocking. Add it back to spec:all once #3225 greens the lane.
  desc 'Run API contract specs (spec/api/, mode-agnostic; needs Valkey on 2163)'
  task :api do
    env = { 'RACK_ENV' => 'test', 'AUTHENTICATION_MODE' => 'simple' }
    sh env, "bundle exec rspec spec/api #{rspec_format_options}"
  end

  # Two rspec processes, not thirteen. `rake spec:verify_selection` asserts the
  # pair selects exactly the files the thirteen selected; run it after any edit
  # to ROOT_FAST_PATTERN / APPS_FAST_PATTERN / APPS_FAST_EXCLUDE.
  #
  # Deliberately NOT a prerequisite chain (`task fast: [...]`): rake stops a
  # prerequisite chain at its first failure — RSpec::Core::RakeTask exits the
  # process on a red leg — so any root_fast failure used to skip apps_fast and
  # apps_config_ru entirely: all 11 apps/*/*/spec trees, ~5,200 examples, with
  # nothing in the output saying so. Two environment-dependent examples
  # (spec/unit/lanes/isolation_key_spec.rb wherever Docker is absent) were
  # enough to hide app-spec drift behind a red-but-partial run. Every leg runs;
  # a red one is recorded, summarized per leg, and fails the task at the end.
  desc 'Run all non-integration specs (unit, cli, lib, apps)'
  task :fast do
    failures = {}
    FAST_LEGS.each do |leg|
      Rake::Task[leg].invoke
    rescue SystemExit => ex
      # RSpec's rake task calls `exit` rather than raising, and SystemExit is
      # not a StandardError — a bare rescue here would let the first red leg
      # take the whole chain down again.
      failures[leg] = "exit #{ex.status}"
    rescue StandardError => ex
      failures[leg] = ex.message
    end

    puts
    puts "spec:fast leg summary (#{FAST_LEGS.size - failures.size}/#{FAST_LEGS.size} ok):"
    FAST_LEGS.each do |leg|
      puts format('  %-20s %s', leg, failures.key?(leg) ? "FAILED (#{failures[leg]})" : 'ok')
    end
    unless failures.empty?
      abort "spec:fast: #{failures.size} of #{FAST_LEGS.size} legs failed: #{failures.keys.join(', ')}"
    end
  end

  desc 'Run the complete test suite'
  task all: ['spec:fast', 'spec:integration:all']
end

# Tryouts test tasks
# Tryouts is a documentation-first Ruby testing framework where tests are plain
# Ruby code with comment expectations. These tasks mirror the RSpec structure.
namespace :try do
  desc 'Run unit tryouts (includes security, feature, and app-colocated tests)'
  task :unit do
    patterns  = %w[try/unit try/system try/security try/features try/jobs]
    patterns += Dir.glob('apps/**/try')
    paths     = patterns.uniq.select { |p| Dir.exist?(p) }.join(' ')
    # In CI: verbose output without agent mode; locally: agent mode for concise output
    flags     = ENV['CI'] ? '--stack --verbose --debug --fails' : '--agent'
    sh "bundle exec tryouts #{flags} #{paths}".squeeze(' ') unless paths.empty?
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

      # NOTE: colonel_role_auth_try.rb excluded - requires full Rack app which
      # calls exit in CI environment. Run locally with: bundle exec try try/integration/colonel_role_auth_try.rb
      patterns = %w[
        try/integration/middleware
        try/integration/boot
        try/integration/web
        try/integration/api
        try/integration/email
        try/integration/billing
        try/integration/homepage_bypass_header_integration_try.rb
        try/integration/homepage_mode_integration_try.rb
        try/integration/check_jobqueue_live_try.rb
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

# Smoke test tasks
# Quick validation that the system works without running the full test suite.
# Designed for CI's "comprehensive" job to catch obvious breakages efficiently.
#
# Philosophy:
# - Run representative tests, not exhaustive coverage
# - One integration mode (simple) is sufficient for smoke testing
# - Skip 100% pending specs (they waste time loading but never execute)
# - Complete in under 2 minutes
namespace :smoke do
  desc 'Run smoke test for RSpec (unit + representative apps + simple integration)'
  task :rspec do
    # Unit and CLI tests - fast, covers core logic
    Rake::Task['spec:unit'].invoke
    Rake::Task['spec:cli'].invoke

    # Representative app specs - skip 100% pending (domains, acme)
    # These are chosen because they have actual passing tests
    %w[api_v1 api_v2 api_organizations web_billing].each do |app|
      Rake::Task["spec:apps:#{app}"].invoke
    end

    # One integration mode is enough for smoke testing
    Rake::Task['spec:integration:simple'].invoke
  end

  desc 'Run smoke test for Tryouts (unit only, skip integration)'
  task :tryouts do
    # Unit tryouts cover the critical paths without needing auth mode setup
    Rake::Task['try:unit'].invoke
  end

  desc 'Run complete smoke test suite (Ruby + Tryouts)'
  task ruby: [:rspec, :tryouts]

  desc 'Run smoke test with Vitest (full smoke)'
  task :all do
    Rake::Task['smoke:ruby'].invoke
    # Vitest is run via pnpm, not rake
    sh 'pnpm test' if system('command -v pnpm > /dev/null 2>&1')
  end
end

task spec: 'spec:fast'
