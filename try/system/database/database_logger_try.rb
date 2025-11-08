# try/system/database/database_logger_try.rb
#
# frozen_string_literal: true

#
# Tryouts for Familia's DatabaseLogger middleware functionality
#
# These tests verify that Familia's DatabaseLogger middleware correctly
# captures and logs Redis commands executed through Familia models.

# Enable database logging and force reconnection to apply middleware
# to existing connection pools (handles test suite execution order issues)
ENV['DEBUG_DATABASE'] = 'true' # must be set before OT.boot! / test_helpers

require_relative '../../support/test_helpers'

OT.boot! :test, true

# Familia.reconnect!

# Set a logger for DatabaseLogger (optional for capture, required for logging)
# When middleware is registered, it copies Familia.logger to DatabaseLogger.logger
# DatabaseLogger.logger = Logger.new(STDOUT, level: Logger::DEBUG) if ENV['DEBUG_DATABASE'] == 'true'

# Reload the connection pool to discard old connections without middleware
# The block closes each old connection before creating new ones
# OT.database_pool.reload { |conn| conn.quit rescue nil }


# Clear any commands captured by previous test files to ensure clean state
DatabaseLogger.clear_commands

# DatabaseLogger should be available after boot (it's a module from Familia)
@middleware_module = DatabaseLogger

## DatabaseLogger module exists
@middleware_module.class
#=> Module

## DatabaseLogger has logger accessor
@middleware_module.respond_to?(:logger)
#=> true

## DatabaseLogger has capture_commands method
@middleware_module.respond_to?(:capture_commands)
#=> true

## DatabaseLogger has clear_commands method
@middleware_module.respond_to?(:clear_commands)
#=> true

## DatabaseLogger captures Redis commands in a block
commands = DatabaseLogger.capture_commands do
  # Create a test customer which will execute Redis commands
  cust = Onetime::Customer.new
  cust.custid = "test-database-logger-#{Time.now.to_i}"
  cust.email = "dblogger-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
[commands.class, commands.empty?]
#=> [Array, false]

## Captured commands include command hashes with keys
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-command-format-#{Time.now.to_i}"
  cust.email = "format-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
first_command = commands.first
raise RuntimeError, "Command details missing" unless first_command&.command
[first_command.command.is_a?(String), first_command.μs.is_a?(Numeric), first_command.timeline.is_a?(Numeric)]
#=> [true, true, true]

## Command arrays contain Redis command names
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-command-names-#{Time.now.to_i}"
  cust.email = "names-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
# Should see various Redis commands (HSET, DEL, etc.)
command_names = commands.map { |cmd| cmd.command }.uniq
has_redis_commands = !command_names.empty? && command_names.all? { |name| name.is_a?(String) }
has_redis_commands
#=> true

## Duration is measured in microseconds
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-duration-#{Time.now.to_i}"
  cust.email = "duration-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
# All durations should be positive numbers
durations_valid = commands.all? { |cmd| cmd.μs.is_a?(Numeric) && cmd.μs > 0 }
durations_valid
#=> true

## Timeliens are Floats, ever increasing relative to the time the process started
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-timelines-#{Time.now.to_i}"
  cust.email = "timelines-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
# All timelines should be Time objects
commands.all? { |cmd| cmd.timeline.is_a?(Float) }
#=> true

## Logger can be set and retrieved
original_logger = DatabaseLogger.logger
begin
  test_logger = Logger.new(StringIO.new)
  DatabaseLogger.logger = test_logger
  DatabaseLogger.logger == test_logger
ensure
  DatabaseLogger.logger = original_logger
end
#=> true

## Logger can be nil (disabled state)
original_logger = DatabaseLogger.logger
begin
  DatabaseLogger.logger = nil
  DatabaseLogger.logger.nil?
ensure
  DatabaseLogger.logger = original_logger
end
#=> true

## Capture works even when logger is nil
original_logger = DatabaseLogger.logger
begin
  DatabaseLogger.logger = nil
  commands = DatabaseLogger.capture_commands do
    cust = Onetime::Customer.new
    cust.custid = "test-no-logger-#{Time.now.to_i}"
    cust.email = "nologger-#{Time.now.to_i}@example.com"
    cust.save
    cust.delete!
  end
  !commands.empty?
ensure
  DatabaseLogger.logger = original_logger
end
#=> true

## Captured commands include various Redis operations
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-operations-#{Time.now.to_i}"
  cust.email = "ops-#{Time.now.to_i}@example.com"
  cust.save

  # Trigger various Redis operations
  loaded = Onetime::Customer.find_by_identifier(cust.identifier)
  loaded.delete!
end

# Should see various Redis commands
command_types = commands.map { |cmd| cmd.command }.uniq
has_multiple_types = command_types.size > 1
has_multiple_types
#=> true

## Commands array can be cleared
DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = "test-clear-#{Time.now.to_i}"
  cust.email = "clear-#{Time.now.to_i}@example.com"
  cust.save
  cust.delete!
end
DatabaseLogger.clear_commands
DatabaseLogger.commands.empty?
#=> true

# Teardown: Clean up global state to prevent interference with other test files
DatabaseLogger.logger = nil
DatabaseLogger.clear_commands
Familia.enable_database_logging = false
ENV['DEBUG_DATABASE'] = 'false'
