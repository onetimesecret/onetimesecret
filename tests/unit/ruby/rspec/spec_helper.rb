# tests/unit/ruby/rspec/spec_helper.rb

# This file sets up the RSpec testing environment for the OnetimeSecret project.
# It includes necessary libraries, configures code coverage, and mocks essential components.

require 'rspec'
require 'simplecov'

require_relative 'support/rack_context'
require_relative 'support/view_context'
require_relative 'support/mail_context'

# Starts SimpleCov for code coverage analysis if the COVERAGE environment variable is set.
SimpleCov.start if ENV['COVERAGE']

base_path = File.expand_path('../../../../..', __FILE__)
apps_root = File.join(base_path, 'apps').freeze

# Add the apps dirs to the load path. This allows us
# to require 'v2/logic' naturally.
$LOAD_PATH.unshift(File.join(apps_root, 'api'))
$LOAD_PATH.unshift(File.join(apps_root, 'web'))

# Adds the 'lib' directory to the load path to ensure that the Onetime
# library can be required.
$LOAD_PATH.unshift File.join(base_path, 'lib')

# Add spec directory to load path
spec_path = File.expand_path('../..', __FILE__)
$LOAD_PATH.unshift(spec_path)

begin
  require 'onetime'
  require 'onetime/alias' # OT
  require 'onetime/refinements/rack_refinements'
  require 'onetime/logic'
  require 'onetime/models'
  require 'onetime/controllers'
  require 'onetime/views'
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

# We fail fast if templates aren't where we expec
# Should run after other setup code but before RSpec.configure
def verify_template_structure
  template_dir = File.expand_path("#{Onetime::HOME}/templates/mail", __FILE__)
  unless Dir.exist?(template_dir)
    puts "ERROR: Template directory not found at: #{template_dir}"
    puts "Current directory: #{Dir.pwd}"
    puts "Directory contents: #{Dir.entries('..')}"
    raise "Template directory missing - check project structure"
  end
end
verify_template_structure

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

  # Shared Context
  config.include_context "rack_test_context", type: :request
  config.include_context "view_test_context", type: :view

  config.before(:each, type: :request) do
    allow(Rack::Request).to receive(:new).and_return(rack_request)
    allow(Rack::Response).to receive(:new).and_return(rack_response)
  end
end
