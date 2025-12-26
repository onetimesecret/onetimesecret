# spec/spec_helper.rb
#
# frozen_string_literal: true

# Debugging helpers for tests
#
# To debug tests with IRB console (debugger):
#   RUBY_DEBUG_IRB_CONSOLE=true pnpm run test:rspec spec/your_test_spec.rb
#
# To run specific tests:
#   pnpm run test:rspec spec/your_test_spec.rb:line_number
#   pnpm run test:rspec spec/your_test_spec.rb -e "test description"
#
# To run tests with focus tag:
#   Add `focus: true` to your it/describe blocks, then run: pnpm run test:rspec
#
# To see full error backtraces:
#   pnpm run test:rspec --backtrace
#
# To run tests in the order they're written (not random):
#   pnpm run test:rspec --order defined
#
# To see detailed output:
#   pnpm run test:rspec --format documentation

# spec/spec_helper.rb
# Test harness for Onetime.

# Set test database URL - use port 2121 to avoid conflicts with development Redis
# This MUST be set before config.test.yaml is loaded via ERB, since it checks:
#   ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'
#
# Values from .env file would otherwise leak into tests. For tests, always use port 2121 explicitly.

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Redis/Valkey Testing Strategy
#
# FakeRedis was removed due to redis 5.x incompatibility. The project uses redis ~> 5.4.0,
# but fakeredis only supports redis ~> 4.8. Bundler resolved to fakeredis 0.1.4 (from 2013)
# which had no redis dependency constraint, but this ancient version lacked modern Redis features.
#
# Why fakeredis 0.1.4 was used:
# - fakeredis 0.9.2 (May 2023) → requires redis ~> 4.8 ❌ conflicts
# - fakeredis 0.5.0-0.8.0 → requires redis ~> 4.x ❌ conflicts
# - fakeredis 0.1.4 (2013) → no redis dependency ✓ only option
#
# Current state per GitHub issue guilleiguaran/fakeredis#268:
# - FakeRedis doesn't support redis-rb 5.x yet
# - redis-client (used by redis-rb 5.x) maintainers won't add mocking support
# - Ecosystem recommendation: use real Redis/Valkey for tests
#
# Testing approaches:
# - Unit tests: Most don't actually need Redis - they test pure Ruby logic
# - Integration tests: Use real Valkey on port 2121 (see integration_spec_helper.rb)
#
# Future alternative if needed:
# - mock_redis gem supports redis ~> 5.0 and is actively maintained
# - Add to Gemfile: gem 'mock_redis', require: false
# - See: https://rubygems.org/gems/mock_redis
#
# For now, tests requiring Redis should read from the spec/config.test.yaml
#   pnpm run test:database:start  # Start Valkey on port 2121
#   pnpm run test:rspec

# Configure Timecop for time manipulation in tests
require 'timecop'

# Configure Rack::Test for request specs
require 'rack/test'

# Block all external HTTP connections by default
# Tests must use VCR cassettes or explicit stubs for any HTTP calls
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)
# Path setup - do one thing well
spec_root = File.expand_path(__dir__)
base_path = File.expand_path('..', spec_root)
apps_root = File.join(base_path, 'apps').freeze

$LOAD_PATH.unshift(File.join(apps_root, 'api'))
$LOAD_PATH.unshift(File.join(apps_root, 'web'))
$LOAD_PATH.unshift(File.join(base_path, 'lib'))
$LOAD_PATH.unshift(spec_root)

# Load application - fail fast, fail clearly
begin
  require 'onetime'
  require 'onetime/alias'

  # Due to how Familia::Horreum defines model classes we need to create
  # an instance of each model class to ensure that they are loaded and
  # available for testing. Part of ##1185.
  require 'onetime/models'

  require 'onetime/logic'
  require 'onetime/views'

  # Load API modules for specs that test them
  require 'account/application'
  require 'core/application'
rescue LoadError => ex
  warn "Load failed: #{ex.message} (pwd: #{Dir.pwd})"
  exit 1
end

# Switch SemanticLogger to synchronous mode for tests.
# This eliminates race conditions where the async logging thread processes log
# messages containing mock objects after RSpec has torn down the mock context.
# The async thread would call .strftime on what should be a Time but is a mock,
# causing RSpec::Mocks::MockExpectationError.
#
# See: https://github.com/reidmorrison/semantic_logger/blob/master/lib/semantic_logger/sync.rb
require 'semantic_logger/sync'

# Load test utilities
Dir[File.join(spec_root, 'support', '*.rb')].each { |f| require f }
Dir[File.join(spec_root, 'support', 'shared_contexts', '*.rb')].each { |f| require f }
Dir[File.join(spec_root, 'support', 'shared_examples', '*.rb')].each { |f| require f }
Dir[File.join(spec_root, 'support', 'factories', '*.rb')].each { |f| require f }

# Test mode
OT.mode = :test

# Config resolution is handled automatically by Onetime::Utils::ConfigResolver
# when RACK_ENV=test - it uses spec/{name}.test.yaml files

# Billing isolation for RSpec is handled by apps/web/billing/spec/support/billing_isolation.rb
# which disables billing before each test and cleans up after tests that enable it.
# Framework-agnostic helpers live in apps/web/billing/lib/test_support/billing_helpers.rb

# Load the test configuration so OT.conf is available to tests.
# This is a minimal config load that doesn't run the full boot process.
# Integration tests that need full boot will call Onetime.boot! separately.
begin
  OT::Config.before_load
  raw_conf       = OT::Config.load
  processed_conf = OT::Config.after_load(raw_conf)
  OT.replace_config!(processed_conf)

  # Set Familia.uri from config so integration test hooks can use Familia.dbclient
  # before boot! runs. Without this, Familia uses default redis://127.0.0.1:6379.
  redis_uri   = OT.conf.dig('redis', 'uri')
  Familia.uri = redis_uri if redis_uri
rescue StandardError => ex
  warn "Failed to load test config: #{ex.message}"
  warn 'Tests requiring OT.conf will fail'
end

# Test helpers module
module SpecHelpers
  # Add shared test helpers here
end

RSpec.configure do |config|
  # ==========================================================================
  # DIRECTORY-BASED AUTH MODE ISOLATION
  # ==========================================================================
  # Integration tests are organized by authentication mode. Each mode runs in
  # a separate process with the appropriate AUTHENTICATION_MODE env var set.
  #
  # Directory structure:
  #   spec/integration/simple/    -> AUTHENTICATION_MODE=simple
  #   spec/integration/full/      -> AUTHENTICATION_MODE=full
  #   spec/integration/disabled/  -> AUTHENTICATION_MODE=disabled
  #   spec/integration/all/       -> Runs in ALL modes (infrastructure tests)
  #
  # Run tests via Rake tasks (recommended):
  #   bundle exec rake spec:integration:simple
  #   bundle exec rake spec:integration:full
  #   bundle exec rake spec:integration:disabled
  #   bundle exec rake spec:integration:all
  #
  # Or via pnpm:
  #   pnpm test:rspec:integration:simple
  #   pnpm test:rspec:integration:full
  #   pnpm test:rspec:integration:disabled
  #
  # The Rake tasks run mode-specific tests + all/ tests together, matching
  # production deployment where only one auth mode exists per instance.
  # ==========================================================================

  # Auto-derive auth mode tags from directory structure.
  # These tags trigger before(:context) hooks in support/ files that set up
  # mode-specific infrastructure (database mocks, factories, helpers).
  # See: spec/support/auth_mode_helpers.rb, spec/support/full_mode_suite_database.rb
  %w[simple full disabled].each do |mode|
    config.define_derived_metadata(file_path: %r{/integration/#{mode}/}) do |metadata|
      metadata[:"#{mode}_auth_mode"] = true
    end
  end

  # Tests in /integration/all/ run in every mode - tagged for documentation purposes
  config.define_derived_metadata(file_path: %r{/integration/all/}) do |metadata|
    metadata[:all_auth_modes] = true
  end

  config.expect_with :rspec do |expectations|
    # Use default expectations configuration
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Save critical OT global state before each test to prevent test isolation issues.
  # Some tests modify these values directly or set them to nil; this ensures
  # subsequent tests have valid state.
  config.before(:each) do
    @__original_ot_conf       = OT.conf
    # Save Runtime state - this is where locales and other i18n state lives
    @__original_runtime_i18n  = Onetime::Runtime.internationalization
    # Save boot state - tests that manipulate boot state need this restored
    @__original_boot_state    = Onetime.boot_state
  end

  config.after(:each) do
    # Flush SemanticLogger to ensure all log messages are processed before
    # moving to the next test. Since we use SemanticLogger.sync! (set above),
    # this is now a synchronous operation with no race conditions.
    #
    # Note: Some tests stub SemanticLogger.flush to test error handling,
    # so we rescue any errors here.
    begin
      SemanticLogger.flush if defined?(SemanticLogger)
    rescue StandardError => ex
      # Log but don't fail - this may be a test stub (setup_loggers_spec.rb)
      # or a real error worth investigating.
      warn "SemanticLogger.flush failed (possibly stubbed): #{ex.message}"
    end

    # Restore OT.conf if it was changed during the test
    if OT.conf != @__original_ot_conf
      OT.instance_variable_set(:@conf, @__original_ot_conf)
    end
    # Restore Runtime internationalization state if changed
    if Onetime::Runtime.internationalization != @__original_runtime_i18n
      Onetime::Runtime.internationalization = @__original_runtime_i18n
    end
    # Configure Timecop - automatically return to real time after each test
    Timecop.return

    # Clear thread-local initializer registry to prevent state leakage between tests.
    # The InitializerRegistry.with_registry pattern saves/restores, but direct assignments
    # to Thread.current[:initializer_registry] may not be cleaned up.
    Thread.current[:initializer_registry] = nil

    # Restore boot state if it was changed during the test.
    # This follows the same save/restore pattern as OT.conf and Runtime.internationalization.
    # Tests that manipulate boot state (e.g., boot! tests, error handling tests) will have
    # their changes restored, while tests that depend on persistent boot state (e.g., routes
    # tests using before(:all)) won't have their state unexpectedly reset.
    if Onetime.boot_state != @__original_boot_state
      case @__original_boot_state
      when Onetime::Initializers::BOOT_STARTED
        Onetime.started!
      when Onetime::Initializers::BOOT_FAILED
        Onetime.failed!(StandardError.new('Restored from test'))
      else
        Onetime.reset_ready!
      end
    end
  end

  # Include Rack::Test::Methods for request specs
  config.include Rack::Test::Methods, type: :request

  config.filter_run_when_matching :focus
  config.order = :random

  # One of :none, :all, :deprecations_only
  config.warnings = :deprecations_only

  Kernel.srand config.seed
end

# Load billing isolation support (must be after RSpec.configure)
# RSpec-specific hooks live in billing_isolation.rb, which requires the shared helpers.
require_relative '../apps/web/billing/spec/support/billing_isolation'
