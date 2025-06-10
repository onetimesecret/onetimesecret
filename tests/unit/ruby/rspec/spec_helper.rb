# tests/unit/ruby/rspec/onetime/config/spec_helper.rb

require 'rspec'
require 'tempfile'
require 'fileutils'
# require 'fakeredis'

# Establish the environment
ENV['RACK_ENV'] ||= 'production'
ENV['ONETIME_HOME'] ||= File.expand_path('../../../../..', __FILE__).freeze

unless defined?(APPS_ROOT)
  project_root = ENV['ONETIME_HOME']
  APPS_ROOT = File.join(project_root, 'apps').freeze

  # Add the apps dirs to the load path. This allows us to require
  # 'v2/logic' naturally (without needing the 'apps/api' prefix).
  %w{api web}.each { |name| $LOAD_PATH.unshift(File.join(APPS_ROOT, name)) }

  # Add the lib directory for the core project.
  LIB_ROOT = File.join(project_root, 'lib').freeze
  $LOAD_PATH.unshift(LIB_ROOT)

  # Define the directory for static web assets like images, CSS, and JS files.
  PUBLIC_DIR = File.join(project_root, '/public/web').freeze

  # Add spec directory to load path
  spec_path = File.expand_path('../..', __FILE__)
  $LOAD_PATH.unshift(spec_path)
end

require_relative './support/mail_context'
require_relative './support/rack_context'
require_relative './support/view_context'
require_relative './support/model_test_helper'

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
  # available for testing. Part of #1185.
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

# Set up minimal test configuration
minimal_test_config = {
  site: {
    secret: 'test-secret-key-for-tests',
    authentication: {
      enabled: true,
      colonels: []
    }
  },
  development: {},
  mail: {
    truemail: {}
  }
}

# Set the configuration directly for tests
OT.send(:conf=, minimal_test_config)

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

  # Disable actual Redis connections by default, but allow specific tests to enable them
  config.before(:each) do |example|
    # Skip Redis mocking if test is explicitly marked to allow Redis
    unless example.metadata[:allow_redis]
      # This is a safety net - it will raise an error if any code tries to actually connect to Redis
      allow(Redis).to receive(:new).and_raise("Real Redis connections are not allowed in tests! Use test helpers instead.")
    end
  end
end
