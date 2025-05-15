# tests/unit/ruby/rspec/onetime/config/spec_helper.rb

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

base_path = File.expand_path('../../../../..', __FILE__)
apps_root = File.join(base_path, 'apps').freeze

# Add the apps dirs to the load path. This allows us to require
# 'v2/logic' naturally (without needing the 'apps/api' prefix).
$LOAD_PATH.unshift(File.join(apps_root, 'api'))
$LOAD_PATH.unshift(File.join(apps_root, 'web'))

# Adds the 'lib' directory to the load path to ensure that the Onetime
# library can be required.
$LOAD_PATH.unshift File.join(base_path, 'lib')

# Add spec directory to load path
spec_path = File.expand_path('../..', __FILE__)
$LOAD_PATH.unshift(spec_path)

require_relative './support/mail_context'
require_relative './support/rack_context'
require_relative './support/view_context'

begin
  require 'onetime'
  require 'onetime/alias' # allows using OT::Mail
  require 'onetime/refinements/rack_refinements'
  require 'onetime/logic'
  require 'onetime/models'
  require 'onetime/controllers'
  require 'onetime/views'

  # Due to how Familia::Horreum defines model classes we need to create
  # an instance of each model class to ensure that they are loaded and
  # available for testing. Part of ##1185.
  #
  # From Horreum#initialize:
  #   "Automatically add a 'key' field if it's not already defined."
  #
  # V1::Secret.new
  # V2::Secret.new

rescue LoadError => e
  puts "Failed to load onetime module: #{e.message}"
  puts "Current directory: #{Dir.pwd}"
  puts "Load path: #{$LOAD_PATH.inspect}"
  exit 1
end

# Setup test environment
OT.mode = :test

# Set config path for tests
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')

# Configure RSpec
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

  # RSpec will create this file to keep track of example statuses, and
  # powers the the --only-failures flag.
  config.example_status_persistence_file_path = ".rspec_status"

  # Suppresses Ruby warnings during test runs for a cleaner output.
  config.warnings = false

  # Run specs in random order
  config.order = :defined # one of: :randomized (ideally), :defined

  # Alternately instead of order :defined, start the process with the same seed every time.
  # config.seed = 12345 # any fixed number

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Enable aggregate failures by default for cleaner specs
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true unless meta.key?(:aggregate_failures)
  end

  # Global before hooks
  config.before(:each) do

    # Suppress logging during tests
    allow(OT).to receive(:ld).and_return(nil)
    allow(OT).to receive(:li).and_return(nil)
    allow(OT).to receive(:le).and_return(nil) unless defined?(@preserve_error_logs) && @preserve_error_logs
  end
end
