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
# Lane environment contract
# -------------------------
# Each task below is a LANE: one process started with the env hash the task
# builds, and nothing more. A spec under a lane's directory may rely on every
# setting in that hash (the full lane's ORGS_SSO_ENABLED=true registers the
# /auth/sso/* routes, for instance) and must not rely on anything outside it.
# The lane, not the developer's shell, is the environment of record; a bare
# `bundle exec rspec` run is not a lane. Specs that need a lane-provided
# setting tag themselves `lane_env:` (spec/support/helpers/lane_env_helpers.rb)
# so that running them outside the lane fails naming the lane. When a lane's
# env hash changes, that helper's LANES table and the spec_helper header are
# the two places that describe it to spec authors.
#
# Environment Variables:
#   RSPEC_OUTPUT_FILE - Path to JSON results file (e.g., tmp/rspec_results.json)
#                       When set, adds JSON formatter output for CI reporting
#   LANES_RSPEC_CONSOLE - `quiet` swaps the console's progress formatter for
#                       tests/lanes/support/quiet_formatter.rb. Assigned by
#                       tests/lanes/run --quiet; the results file is unaffected
#   worker count      - rspec processes per invocation for the tasks that
#                       split (see "In-lane workers" below, and
#                       tests/lanes/support/workers.rb for the variable);
#                       absent or 1 is one process
#
# See also: docs/adr/adr-007-test-process-boundaries.md

require 'fileutils'
require 'shellwords'
require 'rspec/core/rake_task'
require_relative '../../tests/lanes/support/rspec_format'
require_relative '../../tests/lanes/support/merge_rspec_status'
require_relative '../../tests/lanes/support/workers'

INTEGRATION_MODES = %w[simple full disabled].freeze

PG_TEST_DATABASE_URL   = ENV.fetch(
  'AUTH_DATABASE_URL_PG',
  'postgresql://onetime_user:testpass@localhost:5432/onetime_auth_test',
)
PG_TEST_MIGRATIONS_URL = ENV.fetch(
  'AUTH_DATABASE_URL_MIGRATIONS_PG',
  'postgresql://onetime_migrator:migratepass@localhost:5432/onetime_auth_test',
)

# RSpec format options for one rspec invocation
#
# The console formatter (progress, or the quiet one when tests/lanes/run
# --quiet exported LANES_RSPEC_CONSOLE=quiet) plus the JSON formatter when
# RSPEC_OUTPUT_FILE is set. The two are chosen independently and always passed
# together: a `--format` anywhere else (SPEC_OPTS, say) would replace this
# whole list and drop the results file. Lanes::RSpecFormat
# (tests/lanes/support/rspec_format.rb) is where the list is put together, for
# these tasks and for the runner's --only alike.
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
  Lanes::RSpecFormat.options(ENV, suffix: suffix)
end

# Format options for a task whose results file CI knows by its bare name
#
# migration-tests.yml uploads tmp/sqlite_migration_results.json by that exact
# path, and every lane below runs its task as the one task of a rake process,
# so there the file stays `<stem>.json`. The same task run beside others in
# one rake process (spec:integration:all, spec:all, smoke:rspec, or several
# names on one command line) takes a suffix from its own name instead, so no
# invocation truncates the file another one wrote.
#
# @param task [Rake::Task] the task making the rspec invocation
# @return [String] RSpec format flags
def rspec_task_format_options(task)
  rspec_format_options(Lanes::RSpecFormat.task_suffix(task.name, Rake.application.top_level_tasks))
end

# In-lane workers (#4551)
# -----------------------
# The runner's worker count (Lanes::Workers.count, from a lane's env file or
# `tests/lanes/run --workers N`; tests/lanes/support/workers.rb reads it,
# since this file is copied into the image and may name no runner variable)
# is the number of rspec processes a lane's invocation is split over. Absent,
# empty or 1 is the serial command, exactly as before. Above 1 the tasks
# that opt in (spec:integration:simple, spec:integration:full, spec:api) run
# parallel_rspec instead: N `bundle exec rspec` processes over the same
# paths, each started through tests/lanes/support/worker-env, which gives
# worker k (TEST_ENV_NUMBER, 1-based under --first-is-1) its own datastore
# index and URLs, its own example status file
# (<run dir>/rspec-status.w<k>.txt) and its own results file: the single
# `--out tmp/<stem>.json` the task passes becomes tmp/<stem>_w<k>.json,
# which .github/actions/run-test-lane already collects by tmp/<stem>*.json.
# The rspec options are the same string the serial command gets, handed
# whole to parallel_rspec's -o. Output is serialized per worker, in
# completion order, and the exit status is non-zero when any worker's is.
#
# When the workers are done, whatever the exit status, their status files
# are folded into the lane's (tests/lanes/support/merge_rspec_status.rb),
# so `tests/lanes/run <lane> --only <file> -- --only-failures` keeps
# reading one file. Stale worker files of an earlier run are removed first:
# rspec keeps entries for files a process did not load, so an old worker
# file would carry statuses this run assigned to another worker.
WORKER_ENV_SHIM = 'tests/lanes/support/worker-env'

# The integration modes whose task splits (with spec:api): the lanes that
# set a worker count in their env file. The disabled lane has no worker
# default and keeps one process even under `--workers N`; add the mode here
# to let it split.
WORKER_INTEGRATION_MODES = %w[simple full].freeze

# One rspec invocation of a lane: serial, or split over the runner's worker
# count (Lanes::Workers.count). +options+ is the shell-quoted tail of the
# serial command (tag filters and the format flags), +paths+ the
# directories and files.
#
# @param env [Hash] the lane's environment for the process(es)
# @param paths [Array<String>] what rspec is given to run
# @param options [String] rspec options, shell-quoted
def sh_rspec(env, paths, options)
  workers = Lanes::Workers.count
  if workers < 2
    sh env, "bundle exec rspec #{paths.join(' ')} #{options}"
    return
  end

  worker_env  = env.merge('PARALLEL_TESTS_EXECUTABLE' => "#{WORKER_ENV_SHIM} auto bundle exec rspec")
  status_file = Lanes::Workers.status_file
  worker_glob = status_file && Lanes::MergeRSpecStatus.worker_glob(status_file)
  FileUtils.rm_f(Dir.glob(worker_glob)) if worker_glob
  command     = "bundle exec parallel_rspec -n #{workers} --first-is-1 --serialize-stdout " \
                "-o #{Shellwords.escape(options)} #{paths.join(' ')}"
  begin
    sh worker_env, command
  ensure
    merge_worker_status(status_file, worker_glob) if worker_glob
  end
end

# Folds the worker status files into the lane's after a split run. Called
# from an `ensure`, so a failure here is reported and swallowed: it must not
# replace the test result that is propagating, and a stale status file costs
# one `--only-failures` rerun, not the run.
#
# @param status_file [String] the lane's status file
# @param worker_glob [String] the per-worker files beside it
def merge_worker_status(status_file, worker_glob)
  rc = Lanes::MergeRSpecStatus.main([status_file, worker_glob])
  warn "[spec.rake] merge_rspec_status exited #{rc}: #{status_file} may be stale" unless rc.zero?
rescue StandardError => ex
  warn "[spec.rake] could not merge the worker status files into #{status_file}: #{ex.class}: #{ex.message}"
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
# not a performance compromise: apps/web/billing/spec/support/billing_spec_helper.rb
# registers VCR around-hooks and billing stubs on GENERIC metadata keys (type:
# :cli among them), scoped to the billing files by :file_path. The root trees
# and the app trees keep separate processes so that scoping is the only thing
# standing between the billing hooks and the 430 spec/cli examples that also
# declare type: :cli.
#
# Billing is not in spec:fast at all. Its specs — the billing app's tree and
# the root trees named for billing — are the billing lane's (tests/lanes/billing,
# spec:billing below), excluded here by the same paths so that
# `rake spec:verify_selection` can prove the two lanes partition what spec:fast
# used to run.
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
# The billing lane's spec selection: the whole billing app tree and the root
# trees named for billing, as directories rather than a pattern — rspec's
# default pattern under each. The one exclusion is the billing app's
# integration/ subtree, spelled with the include's own prefix as the HARD
# RULE requires: its mode-less files are the billing-integration lane's
# (BILLING_INTEGRATION_SPEC_PATTERN below), and a mode subdirectory added
# there later (integration/full/, say) belongs to that mode's lanes, as in
# every other app tree.
#
# No --tag filters: the lane IS the membership. The ~500 :integration-tagged
# billing examples that APPS_FAST_TAG_FILTERS never managed to exclude from
# spec:fast run here, on purpose, with the rest of the billing tree.
BILLING_SPEC_PATHS   = %w[
  apps/web/billing/spec
  spec/cli/billing
  spec/unit/billing
  spec/unit/onetime/operations/billing
].freeze
BILLING_SPEC_EXCLUDE = 'apps/web/billing/spec/integration/**/*_spec.rb'

# The billing-integration lane's spec selection (tests/lanes/billing-integration,
# spec:integration:billing below): the files directly under the billing app's
# integration/, which has no mode subdirectories. No integration task
# dispatches a mode-less file — every spec:integration:<mode> reads
# integration/<mode> — so these ran nowhere until a lane adopted them
# (ADOPTED_PATTERNS in lib/tasks/spec_selection.rake). Non-recursive on
# purpose: a mode subdirectory is the mode lanes'. Expanded at load so the
# task passes files, which the lane ownership oracle models verbatim.
BILLING_INTEGRATION_SPEC_PATTERN = 'apps/web/billing/spec/integration/*_spec.rb'
BILLING_INTEGRATION_SPEC_FILES   = Dir.glob(BILLING_INTEGRATION_SPEC_PATTERN).sort.freeze

# Full-mode files that adapt to the auth feature set: an example that needs
# MFA, email_auth (magic links), WebAuthn or verify_account skips when the
# feature is not loaded, and the mirror-image example skips when it is. The shared full
# lanes boot with those features off, so spec:integration:full:mfa loads these
# files too, by name: in its boot the feature-on examples execute and the
# feature-off ones skip, and each example runs in some lane. Files, not
# directories: the rest of integration/full assumes the default feature set.
FULL_MFA_FEATURE_ADAPTIVE_SPECS = %w[
  apps/web/auth/spec/integration/full/restrict_to_enforcement_spec.rb
  apps/web/auth/spec/integration/full/signin_enabled_enforcement_spec.rb
  apps/web/auth/spec/integration/full/signin_gate_enforcement_spec.rb
  apps/web/auth/spec/integration/full/resend_verify_account_internal_request_spec.rb
  spec/integration/full/env_toggles/magic_links_spec.rb
  spec/integration/full/routes/availability_spec.rb
  spec/integration/full/routes/resend_verification_email_spec.rb
].freeze

# The harness lane's spec selection (tests/lanes/harness, spec:lanes below):
# the lane runner's own specs. Nearly every example there starts
# tests/lanes/run as a subprocess (the selftest lane, --print-key, run-all
# --dry-run), so the directory costs ~20s for examples that test the runner
# and not the application. CI runs the lane only when a path those specs
# exercise changed (the `harness` filter in ci.yml); spec:fast leaves the
# directory out so every other pull request skips it.
HARNESS_SPEC_PATHS = %w[spec/unit/lanes].freeze

# The same trees, as spec:fast's exclusions. Each exclude shares its include's
# prefix ('spec/…' against ROOT_FAST_PATTERN, 'apps/…' against
# APPS_FAST_PATTERN), the one spelling the HARD RULE allows.
ROOT_FAST_PATTERN = 'spec/unit/**/*_spec.rb,spec/cli/**/*_spec.rb,spec/lib/**/*_spec.rb'
ROOT_FAST_EXCLUDE = [
  'spec/cli/billing/**/*_spec.rb',
  'spec/unit/billing/**/*_spec.rb',
  'spec/unit/onetime/operations/billing/**/*_spec.rb',
  'spec/unit/lanes/**/*_spec.rb',
].join(',')
APPS_FAST_PATTERN = 'apps/*/*/spec/**/*_spec.rb'
APPS_FAST_EXCLUDE = [
  'apps/*/*/spec/integration/**/*_spec.rb',
  'apps/web/billing/spec/**/*_spec.rb',
  'apps/web/core/spec/controllers/config_generator_spec.rb',
  'apps/web/core/spec/controllers/page_bootstrap_me_spec.rb',
].join(',')

# Carried over VERBATIM from the per-app tasks, and inert in both places today.
# rspec-core 4.0.0.beta1 ANDs exclusion filters (MetadataFilter.apply? uses
# all?), and spec/support/postgres_mode_suite_database.rb:378 contributes a
# second exclusion rule whenever PostgreSQL is absent — which it always is here.
# The consequence is that these flags exclude nothing. The ~500
# :integration-tagged billing examples they were meant to drop now run in the
# billing lane (BILLING_SPEC_PATHS above), which runs no tag filter at all.
#
# Keeping the flags means an rspec-core upgrade that restores OR-semantics
# changes what spec:fast covers without a diff, for whatever :integration or
# :postgres_database tags remain in the other app trees. Dropping them is a
# lane membership decision for those trees, not a refactor.
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
    t.pattern         = ROOT_FAST_PATTERN
    t.exclude_pattern = ROOT_FAST_EXCLUDE
    t.rspec_opts      = rspec_format_options('root_fast')
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

  # The billing lane's rspec invocation (tests/lanes/billing). One process for
  # the billing app's tree and the root billing trees: billing_spec_helper.rb
  # scopes every hook it registers to the billing app's files by :file_path,
  # so spec/cli/billing's type: :cli examples run beside them unwrapped, the
  # same way the other app trees share a process in spec:apps_fast. Plain `sh`
  # rather than RSpec::Core::RakeTask so the lane ownership oracle
  # (spec/unit/lanes/ownership_spec.rb) sees the paths it passes.
  desc 'Run the billing specs (the billing lane; one process)'
  task :billing do |task|
    sh "bundle exec rspec #{BILLING_SPEC_PATHS.join(' ')} --exclude-pattern '#{BILLING_SPEC_EXCLUDE}' " \
       "#{rspec_task_format_options(task)}"
  end

  # The harness lane's rspec invocation (tests/lanes/harness): the lane
  # runner's own specs, HARNESS_SPEC_PATHS above, which spec:fast excludes.
  # Plain `sh` like spec:billing so the lane ownership oracle sees the paths.
  desc 'Run the lane runner specs (the harness lane; one process)'
  task :lanes do |task|
    sh "bundle exec rspec #{HARNESS_SPEC_PATHS.join(' ')} #{rspec_task_format_options(task)}"
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
      task mode do |task|
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
          # The install-wide SAML switch (#4604), default off: the tenant
          # saml placeholder route registers only with it on, and the full
          # lane's tenant SAML specs drive that route.
          env['SAML_ENABLED']      = 'true'
          tag_filter               = '--tag ~postgres_database'
        end

        patterns = [
          *Dir.glob("apps/*/*/spec/integration/#{mode}"),
          "spec/integration/#{mode}",
          'spec/integration/all',
        ]

        options = [tag_filter, rspec_task_format_options(task)].reject(&:empty?).join(' ')
        if WORKER_INTEGRATION_MODES.include?(mode)
          sh_rspec env, patterns, options
        else
          sh env, "bundle exec rspec #{patterns.join(' ')} #{options}"
        end
      end
    end

    # The billing-integration lane's rspec invocation (tests/lanes/billing-integration):
    # the mode-less files directly under apps/web/billing/spec/integration/,
    # in the same simple-mode, billing-off environment as the billing lane
    # they came from (the specs stub the billing configuration themselves and
    # replay committed VCR cassettes). Files, not the directory: the
    # directory would recurse into a mode subdirectory added later, which
    # belongs to that mode's lanes. An empty list aborts rather than runs:
    # `rspec` with no paths would run the whole default tree and report it
    # as this lane's green.
    desc 'Run the mode-less billing integration specs (the billing-integration lane)'
    task :billing do |task|
      if BILLING_INTEGRATION_SPEC_FILES.empty?
        abort "spec:integration:billing selects no files: nothing matches #{BILLING_INTEGRATION_SPEC_PATTERN}"
      end

      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'simple',
      }
      sh env, "bundle exec rspec #{BILLING_INTEGRATION_SPEC_FILES.join(' ')} #{rspec_task_format_options(task)}"
    end

    desc 'Run full-mode specs that require AUTH_MFA_ENABLED=true (own process)'
    task 'full:mfa' do
      # Own process because Auth::Config configures exactly once per process
      # (auth-config-one-shot.md): the Rodauth OTP, email_auth (magic link)
      # and webauthn feature sets can only exist in a boot whose auth config
      # said so from the start. In :full_auth_mode that config is
      # AuthModeHelpers::MockAuthConfig (mfa_enabled hardcoded true; the
      # email_auth and webauthn flags read the env below). AUTH_MFA_ENABLED
      # here is the separate-process defence against ambient env, not what
      # loads the feature. SQLite lane only, mirroring the default full-mode
      # environment above. Keep identical to tests/lanes/full-mfa/env.
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'ORGS_SSO_ENABLED' => 'true',
        'SAML_ENABLED' => 'true',
        'AUTH_MFA_ENABLED' => 'true',
        'AUTH_EMAIL_AUTH_ENABLED' => 'true',
        # Passkey-as-second-factor coverage (omniauth_connect_reauth_webauthn_spec)
        # needs the Rodauth webauthn feature set in the same one-shot boot.
        'AUTH_WEBAUTHN_ENABLED' => 'true',
        # Email verification for the verify_account examples among the
        # feature-adaptive files below.
        'AUTH_VERIFY_ACCOUNT_ENABLED' => 'true',
      }

      # This task is the full-mfa lane's only task, so an empty glob would
      # otherwise pass the "SQLite, MFA" CI row with zero examples (e.g.
      # after a directory rename). Fail loudly instead. Same for a renamed
      # feature-adaptive file: rspec would abort on the missing path, but name
      # it here so the fix is obvious.
      patterns = Dir.glob('apps/*/*/spec/integration/full_mfa')
      abort '[spec:integration:full:mfa] no apps/*/*/spec/integration/full_mfa directories found' if patterns.empty?

      missing = FULL_MFA_FEATURE_ADAPTIVE_SPECS.reject { |f| File.file?(f) }
      abort "[spec:integration:full:mfa] FULL_MFA_FEATURE_ADAPTIVE_SPECS names missing file(s): #{missing.join(' ')}" if missing.any?

      patterns += FULL_MFA_FEATURE_ADAPTIVE_SPECS

      # Distinct results file so this task never clobbers the full-mode JSON
      # output when both run in one rake process with RSPEC_OUTPUT_FILE set
      # (spec:integration:all).
      sh env, "bundle exec rspec #{patterns.join(' ')} --tag ~postgres_database #{rspec_format_options('mfa')}"
    end

    desc 'Run full-mode specs with the PLATFORM SAML provider configured (own process)'
    task 'full:saml_platform' do
      # Own process for the same one-shot reason as full:mfa (#4450):
      # configure_provider reads SAML_* when Auth::Config configures, and with
      # them set the saml route registers with REAL trust anchors instead of
      # the tenant placeholder. The shared full lanes assert the placeholder
      # (canonical host 404 / refused), so the two cannot share a boot.
      # SAML_IDP_CERT is installed by the spec itself before the first boot
      # from a keypair it mints (no key material is checked in). Keep
      # identical to tests/lanes/full-saml-platform/env.
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'ORGS_SSO_ENABLED' => 'true',
        'AUTH_SSO_ENABLED' => 'true',
        # The install-wide SAML switch (#4604): without it the platform
        # provider registers no route, whatever the SAML_* vars say.
        'SAML_ENABLED' => 'true',
        'SAML_IDP_SSO_SERVICE_URL' => 'https://login.platform-idp.test/saml/sso',
        'SAML_IDP_ENTITY_ID' => 'https://platform-idp.test/saml/metadata',
        # The SAML-compatible session cookie: Secure with same_site lax or
        # none. lax is the default-compatible policy the staged POST-to-GET
        # callback transport is designed for; none remains supported. Under
        # strict or a non-Secure cookie the platform provider is skipped at
        # boot (Saml.platform_options).
        'SESSION_COOKIE_SAME_SITE' => 'lax',
        'SESSION_COOKIE_SECURE' => 'true',
      }

      patterns = Dir.glob('apps/*/*/spec/integration/full_saml_platform')
      if patterns.empty?
        abort '[spec:integration:full:saml_platform] no apps/*/*/spec/integration/full_saml_platform directories found'
      end

      sh env, "bundle exec rspec #{patterns.join(' ')} --tag ~postgres_database #{rspec_format_options('saml_platform')}"
    end

    desc 'Run full mode with PostgreSQL (PG-only specs)'
    task 'full:postgres' do |task|
      env      = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
        'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
        'SAML_ENABLED' => 'true',
      }
      patterns = [
        *Dir.glob('apps/*/*/spec/integration/full'),
        'spec/integration/full',
      ]
      sh env, "bundle exec rspec #{patterns.join(' ')} --tag postgres_database #{rspec_task_format_options(task)}"
    end

    desc 'Run DB-agnostic full mode specs against PostgreSQL'
    task 'full:agnostic_on_pg' do |task|
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => PG_TEST_DATABASE_URL,
        'AUTH_DATABASE_URL_MIGRATIONS' => PG_TEST_MIGRATIONS_URL,
        'ORGS_SSO_ENABLED' => 'true',
        'SAML_ENABLED' => 'true',
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
      sh env, "bundle exec rspec #{patterns.join(' ')} --exclude-pattern '**/migrations/*_{postgres,sqlite}_spec.rb,**/{postgres,sqlite}*_spec.rb' #{rspec_task_format_options(task)}"
    end

    # Migration/trigger suites, run by .github/workflows/migration-tests.yml
    # via the migrations-* lanes (tests/lanes/). Separate from full:postgres
    # because migration-tests is a paths-filtered workflow that needs fast,
    # focused feedback on schema changes — not the whole full-mode matrix.
    namespace :migrations do
      desc 'Run SQLite migration/trigger specs'
      task :sqlite do |task|
        env = {
          'RACK_ENV' => 'test',
          'AUTHENTICATION_MODE' => 'full',
          'AUTH_DATABASE_URL' => 'sqlite::memory:',
        }
        sh env, "bundle exec rspec spec/integration/full/database_triggers/sqlite_spec.rb #{rspec_task_format_options(task)}"
      end

      desc 'Run PostgreSQL migration/trigger/infrastructure specs'
      task :postgres do |task|
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
        sh env, "bundle exec rspec #{specs} --tag postgres_database #{rspec_task_format_options(task)}"
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
    task all: INTEGRATION_MODES + ['full:mfa', 'full:saml_platform']

    desc 'Run all integration tests including Postgres'
    task 'all:with_postgres': INTEGRATION_MODES + ['full:mfa', 'full:saml_platform', 'full:postgres']
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
  task :api do |task|
    env = { 'RACK_ENV' => 'test', 'AUTHENTICATION_MODE' => 'simple' }
    sh_rspec env, ['spec/api'], rspec_task_format_options(task)
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
# The billing lane's tryouts (tests/lanes/billing): the billing app's tree and
# the try/unit subtrees named for billing. try:unit leaves them out.
BILLING_TRY_PATHS = %w[apps/web/billing/try try/unit/billing try/unit/cli/billing].freeze

# +root+ as the paths tryouts should load so that none of +excluded+ is among
# them. Tryouts has no exclude flag and recurses into every directory it is
# given, so a directory on the way to an excluded one is replaced by its
# children; every other directory stays one argument. Files are passed by
# name only where a directory had to be opened.
#
# @param root [String] directory to expand
# @param excluded [Array<String>] directories to leave out, repo-relative
# @return [Array<String>] paths for the tryouts command line
def try_paths_without(root, excluded)
  return [] if excluded.include?(root)
  return [root] if excluded.none? { |dir| dir.start_with?("#{root}/") }

  Dir.children(root).sort.flat_map do |child|
    path = File.join(root, child)
    if File.directory?(path)
      try_paths_without(path, excluded)
    else
      path.end_with?('_try.rb') ? [path] : []
    end
  end
end

namespace :try do
  desc 'Run unit tryouts (includes security, feature, and app-colocated tests)'
  task :unit do
    patterns  = %w[try/unit try/system try/security try/features try/jobs]
    patterns += Dir.glob('apps/**/try')
    paths     = patterns.uniq.select { |p| Dir.exist?(p) }
    paths     = paths.flat_map { |p| try_paths_without(p, BILLING_TRY_PATHS) }.join(' ')
    # In CI: verbose output without agent mode; locally: agent mode for concise output
    flags     = ENV['CI'] ? '--stack --verbose --debug --fails' : '--agent'
    sh "bundle exec tryouts #{flags} #{paths}".squeeze(' ') unless paths.empty?
  end

  desc 'Run the billing tryouts (the billing lane)'
  task :billing do
    paths = BILLING_TRY_PATHS.select { |p| Dir.exist?(p) }.join(' ')
    flags = ENV['CI'] ? '--stack --verbose --debug --fails' : '--agent'
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
      # try/integration/billing is the billing-integration lane's (try:integration:billing).
      patterns = %w[
        try/integration/middleware
        try/integration/boot
        try/integration/web
        try/integration/api
        try/integration/email
        try/integration/homepage_bypass_header_integration_try.rb
        try/integration/homepage_mode_integration_try.rb
        try/integration/check_jobqueue_live_try.rb
        try/integration/domain_auth_enforcement_try.rb
      ].select { |p| File.exist?(p) || Dir.exist?(p) }.join(' ')

      sh env, "bundle exec tryouts --agent #{patterns}" unless patterns.empty?
    end

    # The billing-integration lane's tryouts (tests/lanes/billing-integration):
    # the one try/integration subtree named for billing, which try:integration:simple
    # used to run. Same simple-mode environment; its own process and CI job.
    desc 'Run the billing integration tryouts (the billing-integration lane)'
    task :billing do
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'simple',
      }

      sh env, 'bundle exec tryouts --agent try/integration/billing' if Dir.exist?('try/integration/billing')
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
    task :record do |task|
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

      sh env, "bundle exec rspec #{specs} #{rspec_task_format_options(task)}"
    end

    desc 'Re-record ALL VCR cassettes for billing specs (requires STRIPE_API_KEY)'
    task :rerecord do |task|
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

      sh env, "bundle exec rspec apps/web/billing/spec #{rspec_task_format_options(task)}"
    end

    desc 'Verify billing specs run with existing VCR cassettes (no API key needed)'
    task :verify do |task|
      env = {
        'RACK_ENV' => 'test',
        'AUTHENTICATION_MODE' => 'full',
        'AUTH_DATABASE_URL' => 'sqlite::memory:',
        'VCR_MODE' => 'none',
        'DEFAULT_LOG_LEVEL' => 'error',
      }

      sh env, "bundle exec rspec apps/web/billing/spec #{rspec_task_format_options(task)}"
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
