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

# Encryption key for tests comes from spec/config.test.yaml site.secret fallback.
# Explicitly unset ENV['SECRET'] to prevent production values from .env leaking into tests.
# See commit 04a138f98 which changed Familia to use site.secret from config.
ENV.delete('SECRET')

# Set test database URL - use port 2121 to avoid conflicts with development Redis
# This MUST be set before config.test.yaml is loaded via ERB, since it checks:
#   ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:6379/0'
#
# IMPORTANT: Do NOT use ENV['REDIS_URL'] as fallback - it may contain production
# values from .env file. For tests, always use port 2121 explicitly.
# CI environments should set VALKEY_URL directly to the test database URL.
TEST_REDIS_URL = 'redis://127.0.0.1:2121/0'
ENV['VALKEY_URL'] = TEST_REDIS_URL
ENV['REDIS_URL'] = TEST_REDIS_URL  # Override any production value

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
# For now, tests requiring Redis should use real Valkey via spec/.env.test:
#   source spec/.env.test  # Sets VALKEY_URL=valkey://127.0.0.1:2121/0
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

# Load test utilities
Dir[File.join(spec_root, 'support', '*.rb')].each { |f| require f }

# Test mode
OT.mode         = :test
OT::Config.path = File.join(spec_root, 'config.test.yaml')

# Use test auth config to avoid issues with local auth.yaml modifications
Onetime::AuthConfig.path = File.join(spec_root, 'auth.test.yaml')

# Load the test configuration so OT.conf is available to tests.
# This is a minimal config load that doesn't run the full boot process.
# Integration tests that need full boot will call Onetime.boot! separately.
begin
  OT::Config.before_load
  raw_conf = OT::Config.load
  processed_conf = OT::Config.after_load(raw_conf)
  OT.replace_config!(processed_conf)

  # Set Familia.uri from config so integration test hooks can use Familia.dbclient
  # before boot! runs. Without this, Familia uses default redis://127.0.0.1:6379.
  redis_uri = OT.conf.dig('redis', 'uri')
  Familia.uri = redis_uri if redis_uri
rescue StandardError => ex
  warn "Failed to load test config: #{ex.message}"
  warn "Tests requiring OT.conf will fail"
end

# Test helpers module
module SpecHelpers
  # Add shared test helpers here
end

RSpec.configure do |config|
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
    @__original_ot_conf = OT.conf
    # Save Runtime state - this is where locales and other i18n state lives
    @__original_runtime_i18n = Onetime::Runtime.internationalization
  end

  config.after(:each) do
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
  end

  # Include Rack::Test::Methods for request specs
  config.include Rack::Test::Methods, type: :request

  config.filter_run_when_matching :focus
  config.order = :random

  # One of :none, :all, :deprecations_only
  config.warnings = :deprecations_only

  Kernel.srand config.seed
end
