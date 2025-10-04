# try/80_database/20_database_logger_try.rb
#
# Tryouts for Familia's DatabaseLogger middleware functionality
#
# These tests verify that Familia's DatabaseLogger middleware correctly
# captures and logs Redis commands executed through Familia models.

require_relative '../test_helpers'

# Enable database logging for these tests
# This ensures the middleware is registered and capturing commands
Familia.enable_database_logging = true unless Familia.enable_database_logging

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
  cust.custid = 'test-database-logger'
  cust.email = 'dblogger@example.com'
  cust.save
  cust.delete!
end
[commands.class, commands.empty?]
#=> [Array, false]

## Captured commands include command hashes with keys
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = 'test-command-format'
  cust.email = 'format@example.com'
  cust.save
  cust.delete!
end
first_command = commands.first
[first_command.key?(:command), first_command.key?(:duration), first_command.key?(:timestamp)]
#=> [true, true, true]

## Command arrays contain Redis command names
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = 'test-command-names'
  cust.email = 'names@example.com'
  cust.save
  cust.delete!
end
# Should see various Redis commands (HSET, DEL, etc.)
command_names = commands.map { |cmd| cmd[:command].first }.uniq
has_redis_commands = !command_names.empty? && command_names.all? { |name| name.is_a?(String) }
has_redis_commands
#=> true

## Duration is measured in microseconds
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = 'test-duration'
  cust.email = 'duration@example.com'
  cust.save
  cust.delete!
end
# All durations should be positive numbers
durations_valid = commands.all? { |cmd| cmd[:duration].is_a?(Numeric) && cmd[:duration] > 0 }
durations_valid
#=> true

## Timestamps are Time objects
commands = DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = 'test-timestamps'
  cust.email = 'timestamps@example.com'
  cust.save
  cust.delete!
end
# All timestamps should be Time objects
timestamps_valid = commands.all? { |cmd| cmd[:timestamp].is_a?(Time) }
timestamps_valid
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
    cust.custid = 'test-no-logger'
    cust.email = 'nologger@example.com'
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
  cust.custid = 'test-operations'
  cust.email = 'ops@example.com'
  cust.save

  # Trigger various Redis operations
  loaded = Onetime::Customer.from_identifier(cust.identifier)
  loaded.delete!
end

# Should see various Redis commands
command_types = commands.map { |cmd| cmd[:command].first }.uniq
has_multiple_types = command_types.size > 1
has_multiple_types
#=> true

## Commands array can be cleared
DatabaseLogger.capture_commands do
  cust = Onetime::Customer.new
  cust.custid = 'test-clear'
  cust.email = 'clear@example.com'
  cust.save
  cust.delete!
end
DatabaseLogger.clear_commands
DatabaseLogger.commands.empty?
#=> true
