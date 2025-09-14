# spec/spec_helper.rb
# Test harness for Onetime.

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Path setup - do one thing well
base_path = File.expand_path('../..', __FILE__)
apps_root = File.join(base_path, 'apps').freeze

$LOAD_PATH.unshift(File.join(apps_root, 'api'))
$LOAD_PATH.unshift(File.join(apps_root, 'web'))
$LOAD_PATH.unshift(File.join(base_path, 'lib'))
$LOAD_PATH.unshift(File.expand_path('..', __FILE__))

# Load test utilities
Dir[File.join(__dir__, 'support', '*.rb')].each { |f| require f }

# Load application - fail fast, fail clearly
begin
  require 'onetime'
  require 'onetime/alias'

  # Due to how Familia::Horreum defines model classes we need to create
  # an instance of each model class to ensure that they are loaded and
  # available for testing. Part of ##1185.
  require 'onetime/models'

  require 'onetime/logic'
  require 'onetime/controllers'
  require 'onetime/views'
rescue LoadError => e
  warn "Load failed: #{e.message}"
  warn "PWD: #{Dir.pwd}"
  exit 1
end

# Test mode
OT.mode = :test
OT::Config.path = File.join(Onetime::HOME, 'spec', 'config.test.yaml')

# Initialize configuration - required for tests that access OT.conf
begin
  Onetime.boot!
rescue => e
  # If boot fails, at least ensure OT.conf is not nil with minimal defaults
  minimal_config_data = {
    'site' => {
      'secret' => 'test-secret-key-for-specs',
      'host' => 'localhost',
      'ssl' => false,
      'authentication' => {
        'enabled' => false,
        'colonels' => []
      },
      'domains' => {
        'enabled' => false
      }
    },
    'emailer' => {
      'mode' => 'smtp',
      'from' => 'test@example.com',
      'fromname' => 'Test Suite'
    },
    'experimental' => {},
    'redis' => {
      'uri' => 'redis://localhost:6379/15'
    }
  }
  minimal_config = OT::Config.new(minimal_config_data)
  if OT.conf.nil?
    OT.conf = minimal_config
    # Also ensure Onetime.conf works (they should be aliases but let's be explicit)
    Onetime.instance_variable_set(:@conf, minimal_config)
  end
  warn "Boot failed, using minimal config: #{e.message}"
end


RSpec.configure do |config|
  # Expectations
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mocks
  config.mock_with :rspec do |mocks|
    # When enabled, RSpec will:
    #
    # - Verify that stubbed methods actually exist on the real object
    # - Check method arity (number of arguments) matches
    # - Ensure you're not stubbing non-existent methods
    #
    mocks.verify_partial_doubles = true
  end

  # General configuration
  config.default_formatter = 'doc' if config.files_to_run.one?

  # Show only when requested
  config.profile_examples = 10 if ENV['PROFILE_TESTS'] || ARGV.include?('--profile')

  # Metadata
  #
  # Applies shared context metadata to host groups, enhancing test organization.
  # Will be default in RSpec 4
  config.shared_context_metadata_behavior = :apply_to_host_groups
  #
  # RSpec will create this file to keep track of example statuses, and
  # powers the the --only-failures flag.
  config.example_status_persistence_file_path = 'spec/.rspec_status'

  # Suppresses Ruby warnings during test runs for a cleaner output.
  config.warnings = true

  # Execution
  config.order = :defined
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  # Let Rspec handle the randomization, leave these settings unchanged:
  # config.seed = 12345
  # Kernel.srand config.seed

  # Aggregate failures for better signal-to-noise
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true unless meta.key?(:aggregate_failures)
  end

  # Silence noise
  config.before(:each) do
    allow(OT).to receive(:ld).and_return(nil)
    allow(OT).to receive(:li).and_return(nil)
    allow(OT).to receive(:le).and_return(nil) unless defined?(@preserve_error_logs) && @preserve_error_logs
  end

  # Prevent accidental external dependencies
  config.before(:each) do |example|
    unless example.metadata[:allow_redis]
      allow(Redis).to receive(:new).and_raise("No external Redis in tests")
    end
  end
end
