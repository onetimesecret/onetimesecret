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
  def run_cli_command(*args)
    capture_output do
      begin
        Dry::CLI.new(Onetime::CLI).call(arguments: args)
      rescue SystemExit => e
        # Capture exit code but don't actually exit
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

    # Prevent actual application boot by default
    allow(OT).to receive(:boot!)
    allow(Onetime).to receive(:boot!)
  end

  config.after(:each, type: :cli) do
    # Clean up any temporary files
    cleanup_temp_migrations if respond_to?(:cleanup_temp_migrations)
  end
end
