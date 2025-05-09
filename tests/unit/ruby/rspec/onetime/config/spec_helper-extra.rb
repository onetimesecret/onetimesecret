# tests/unit/ruby/rspec/onetime/config2/spec_helper.rb

require 'rspec'
require 'yaml'
require 'tempfile'
require 'fileutils'

# Add the lib directory to the load path
lib_path = File.expand_path('../../../../../../lib', __FILE__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

# Load the onetime library
begin
  require 'onetime'
  require 'onetime/config'
  require 'onetime/alias' # OT
rescue LoadError => e
  puts "Failed to load onetime: #{e.message}"
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
  # Use the specified formatter
  config.formatter = :documentation

  # Enable warnings
  config.warnings = false

  # Run specs in random order
  config.order = :random

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
