# spec/spec_helper.rb

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

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Path setup - do one thing well
base_path = File.expand_path('..', __dir__)
apps_root = File.join(base_path, 'apps').freeze

$LOAD_PATH.unshift(File.join(apps_root, 'api'))
$LOAD_PATH.unshift(File.join(apps_root, 'web'))
$LOAD_PATH.unshift(File.join(base_path, 'lib'))
$LOAD_PATH.unshift(File.expand_path(__dir__))


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
# Dir[File.join(__dir__, 'support', '*.rb')].each { |f| require f }

# Test mode
OT.mode = :test
OT::Config.path = File.join(Onetime::HOME, 'spec', 'config.test.yaml')


RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # Use default expectations configuration
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed
end

__END__
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
