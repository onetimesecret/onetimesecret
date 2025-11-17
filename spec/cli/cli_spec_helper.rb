# spec/cli/cli_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/cli'
require 'stringio'

module CLISpecHelper
  # Capture CLI output (stdout and stderr)
  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    yield

    {
      stdout: $stdout.string,
      stderr: $stderr.string
    }
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Run a CLI command with arguments
  # Captures exit code but re-raises SystemExit for tests that need to catch it
  def run_cli_command(*args)
    @last_exit_code = nil
    capture_output do
      begin
        Dry::CLI.new(Onetime::CLI).call(arguments: args)
        @last_exit_code = 0  # Successful completion without exit
      rescue SystemExit => e
        # Capture exit code and re-raise
        @last_exit_code = e.status
        raise
      end
    end
  end

  # Run a CLI command without re-raising SystemExit
  # Use this when you want to check output and exit code separately
  def run_cli_command_quietly(*args)
    @last_exit_code = nil
    capture_output do
      begin
        Dry::CLI.new(Onetime::CLI).call(arguments: args)
        @last_exit_code = 0
      rescue SystemExit => e
        @last_exit_code = e.status
      end
    end
  end

  # Get last exit code from command
  def last_exit_code
    @last_exit_code || 0
  end

  # Mock Redis client
  def mock_redis_client
    double('Redis').tap do |redis|
      allow(Familia).to receive(:dbclient).and_return(redis)
    end
  end

  # Mock Onetime application boot
  def mock_ot_boot
    allow(OT).to receive(:boot!)
    allow(Onetime).to receive(:boot!)
  end

  # Create temporary migration file
  def create_temp_migration(name, content)
    dir = File.join(Onetime::HOME, 'migrations')
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  # Clean up temporary migration files
  def cleanup_temp_migrations
    dir = File.join(Onetime::HOME, 'migrations')
    FileUtils.rm_rf(dir) if Dir.exist?(dir)
  end
end

RSpec.configure do |config|
  config.include CLISpecHelper, type: :cli

  config.before(:each, type: :cli) do
    # Reset exit code before each test
    @last_exit_code = nil

    # Stub out model classes that tests will mock
    # Use Module/Class that allows method stubbing via RSpec
    unless defined?(Onetime::Models)
      stub_const('Onetime::Models', Module.new)
    end

    # Create stub classes with methods that can be mocked
    unless defined?(Onetime::Models::Domain)
      domain_class = Class.new do
        def self.all; end
        def self.load(_id); end
      end
      stub_const('Onetime::Models::Domain', domain_class)
    end

    unless defined?(Onetime::Models::Organization)
      org_class = Class.new do
        def self.load(_id); end
      end
      stub_const('Onetime::Models::Organization', org_class)
    end

    unless defined?(Onetime::Models::Customer)
      customer_class = Class.new do
        def self.all; end
      end
      stub_const('Onetime::Models::Customer', customer_class)
    end

    unless defined?(Onetime::Migration)
      # Create a simple class that can be mocked by RSpec
      migration_class = Class.new do
        def self.run(options = {}); end
        def self.load(file); end
      end
      stub_const('Onetime::Migration', migration_class)
    end

    # Prevent actual application boot by default
    allow(OT).to receive(:boot!)
    allow(Onetime).to receive(:boot!)
  end

  config.after(:each, type: :cli) do
    # Clean up any temporary files
    cleanup_temp_migrations if respond_to?(:cleanup_temp_migrations)
  end
end
