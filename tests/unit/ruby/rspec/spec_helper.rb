# tests/unit/ruby/rspec/spec_helper.rb

# This file sets up the RSpec testing environment for the OnetimeSecret project.
# It includes necessary libraries, configures code coverage, and mocks essential components.

require 'rspec'
require 'simplecov'

# Starts SimpleCov for code coverage analysis if the COVERAGE environment variable is set.
SimpleCov.start if ENV['COVERAGE']

# Adds the 'lib' directory to the load path to ensure that the Onetime library can be required.
# Add lib directory to load path
lib_path = File.expand_path('../../../../lib', __FILE__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# Add spec directory to load path
spec_path = File.expand_path('../..', __FILE__)
$LOAD_PATH.unshift(spec_path) unless $LOAD_PATH.include?(spec_path)

begin
  require 'onetime'
  require 'onetime/alias' # OT
  require 'onetime/refinements/rack_refinements'
  require 'onetime/logic/secrets/show_secret'
rescue LoadError => e
  puts "Failed to load refinements: #{e.message}"
  puts "Current directory: #{Dir.pwd}"
  puts "Load path: #{$LOAD_PATH}"
  exit
end

OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

# Mocking the OT module to stub logging methods during tests.
# This prevents actual logging and allows tests to run without external dependencies.
module OT
  class << self
    # Stub method for logging to avoid cluttering test output.
    # @param message [String] The message intended for logging.
    def ld(message)
      puts message
    end
  end
end

# Configures RSpec with desired settings to tailor the testing environment.
RSpec.configure do |config|
  # Configures RSpec to include chain clauses in custom matcher descriptions for better readability.
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Sets RSpec as the mocking framework.
  config.mock_with :rspec

  # Applies shared context metadata to host groups, enhancing test organization.
  # Will be default in RSpec 4       
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Disables RSpec's monkey patching to encourage the use of the RSpec DSL.
  config.disable_monkey_patching!

  # Suppresses Ruby warnings during test runs for a cleaner output.
  config.warnings = false

  # Orders test execution randomly to surface order dependencies and improve test reliability.
  config.order = :random

  # Seeds the random number generator based on RSpec's seed to allow reproducible test order.
  Kernel.srand config.seed
end
