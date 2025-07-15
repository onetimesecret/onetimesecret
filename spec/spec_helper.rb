# spec/spec_helper.rb
require 'bundler/setup'
require 'rspec'
require 'tempfile'
require 'fileutils'

# Establish the environment
ENV['RACK_ENV'] ||= 'test'
ENV['ONETIME_HOME'] ||= File.expand_path('..', __dir__).freeze

# This tells OT::Configurator#load_with_impunity! to look in the preset list
# of paths to look for config, find a config that matches this basename.
ENV['ONETIME_CONFIG_FILE_BASENAME'] = 'config.test'

Warning[:deprecated] = true if ['development', 'dev', 'test'].include?(ENV['RACK_ENV'])

# Setup load paths
unless defined?(APPS_ROOT)
  project_root = ENV['ONETIME_HOME']
  APPS_ROOT = File.join(project_root, 'apps').freeze

  # Add the apps dirs to the load path
  %w{api web}.each { |name| $LOAD_PATH.unshift(File.join(APPS_ROOT, name)) }

  # Add the lib directory for the core project
  LIB_ROOT = File.join(project_root, 'lib').freeze
  $LOAD_PATH.unshift(LIB_ROOT)

  # Define the directory for static web assets
  PUBLIC_DIR = File.join(project_root, 'public/web').freeze
end

# Load the main library
require_relative '../lib/onetime'

# Load support files (if they exist)
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

# Load onetime modules after support files
begin
  require 'onetime/alias'   # allows using OT::Mail
  require 'onetime/logic'
  require 'onetime/models'
  require 'onetime/controllers'
  require 'onetime/views'
rescue LoadError => e
  puts "Failed to load onetime module: #{e.message}"
  puts "Current directory: #{Dir.pwd}"
  puts "Load path: #{$LOAD_PATH.inspect}"
  exit 1
end

# Setup test environment
OT.set_boot_state(:test, nil)

# Set up minimal test configuration
MINIMAL_TEST_CONFIG = {
  site: {
    secret: 'test-secret-key-for-tests',
    authentication: {
      enabled: true,
      colonels: []
    }
  },
  development: {},
  mail: {
    connection: {},
    validation: {
      defaults: {},
    },
  },
  experimental: {
    allow_nil_global_secret: false,
  },
}.freeze

# Configure RSpec
RSpec.configure do |config|
  # Expectation configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mock configuration
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # General configuration
  config.warnings = true
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.example_status_persistence_file_path = 'spec/.rspec_status'
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Enable aggregate failures by default
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true unless meta.key?(:aggregate_failures)
  end

  # Global before hooks
  config.before(:each) do
    # Set up default test configuration mock
    allow(OT).to receive(:conf).and_return(MINIMAL_TEST_CONFIG) unless OT.conf.is_a?(Hash)

    # Suppress logging during tests
    allow(OT).to receive(:ld).and_return(nil)
    allow(OT).to receive(:li).and_return(nil)
    allow(OT).to receive(:le).and_return(nil) unless defined?(@preserve_error_logs) && @preserve_error_logs
  end

  # Disable actual Redis connections by default
  config.before(:each) do |example|
    unless example.metadata[:allow_redis]
      allow(Redis).to receive(:new).and_raise("Real Redis connections are not allowed in tests! Use test helpers instead.")
    end
  end
end
