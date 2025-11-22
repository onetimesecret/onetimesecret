# spec/spec_helper.rb
#
# frozen_string_literal: true

# Debugging helpers for tests
#
# To debug tests with IRB console:
#   RUBY_DEBUG_IRB_CONSOLE=true bundle exec rspec spec/your_test_spec.rb
#
# To run specific tests:
#   bundle exec rspec spec/your_test_spec.rb:line_number
#   bundle exec rspec spec/your_test_spec.rb -e "test description"
#
# To run tests with focus tag:
#   Add `focus: true` to your it/describe blocks, then run: bundle exec rspec
#
# To see full error backtraces:
#   bundle exec rspec --backtrace
#
# To run tests in the order they're written (not random):
#   bundle exec rspec --order defined
#
# To see detailed output:
#   bundle exec rspec --format documentation


# spec/spec_helper.rb
# Test harness for Onetime.

# Set test environment variables
ENV['SECRET'] ||= 'test-secret-key-for-rspec-tests-only-not-for-production-use-12345678901234567890'

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Configure FakeRedis for testing
require 'fakeredis'

# Configure Timecop for time manipulation in tests
require 'timecop'

# Configure Rack::Test for request specs
require 'rack/test'

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
rescue LoadError => e
  warn "Load failed: #{e.message} (pwd: #{Dir.pwd})"
  exit 1
end

# Load test utilities
Dir[File.join(spec_root, 'support', '*.rb')].each { |f| require f }

# Test mode
OT.mode = :test
OT::Config.path = File.join(spec_root, 'config.test.yaml')

# Shared helper for creating a memoized FakeRedis instance
module SpecHelpers
  # Create a memoized FakeRedis instance for use across tests
  # Note: Redis.new returns a FakeRedis instance because the fakeredis
  # gem monkey-patches the Redis class when required (see line 39).
  def self.fake_redis
    @fake_redis ||= Redis.new
  end

  # Reset the memoized instance (useful for cleanup)
  def self.reset_fake_redis!
    @fake_redis = nil
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # Use default expectations configuration
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Start stripe-mock Go server once for entire test suite
  # StripeMockServer is a Ruby wrapper that spawns the stripe-mock go binary
  config.before(:suite) do
    StripeMockServer.start
    StripeMockServer.configure_stripe_client!
  end

  config.after(:suite) do
    StripeMockServer.stop
  end

  # Reset stripe-mock state between tests for isolation
  config.before(:each, :stripe) do
    StripeMockServer.reset!
  end

  # VCR: Automatically wrap tests tagged with :vcr in cassettes
  config.around(:each, :vcr) do |example|
    # Generate cassette name from test description
    cassette_name = example.metadata[:full_description]
                           .downcase
                           .gsub(/[^\w\s]/, '')
                           .gsub(/\s+/, '_')

    VCR.use_cassette(cassette_name) do
      example.run
    end
  end

  # Configure FakeRedis for all tests (except where explicitly disabled)
  # Skip FakeRedis for billing tests - they need real Redis on port 2121
  config.before(:each) do |example|
    # Skip FakeRedis stub for billing tests - they use real Redis
    next if example.metadata[:type] == :billing

    # Ensure FakeRedis is used for all other Redis connections
    # Using memoized instance for better performance
    allow(Familia).to receive(:dbclient).and_return(SpecHelpers.fake_redis)
  end

  # Configure Timecop - automatically return to real time after each test
  config.after(:each) do
    Timecop.return
  end

  # Include Rack::Test::Methods for request specs
  config.include Rack::Test::Methods, type: :request

  config.filter_run_when_matching :focus
  config.warnings = true
  config.order = :random

  Kernel.srand config.seed
end
