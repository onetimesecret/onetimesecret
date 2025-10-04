# try/80_database/21_database_logger_demo_try.rb
#
# Demonstration of DatabaseLogger functionality
#
# This file demonstrates how to use the DatabaseLogger middleware
# for viewing Redis commands in development and testing.

require_relative '../../support/test_helpers'

# Ensure logging is enabled for the demo
Familia.enable_database_logging = true unless Familia.enable_database_logging

@commands = []

## Example: Capture commands programmatically for testing
@commands = DatabaseLogger.capture_commands do
  cust = V2::Customer.new
  cust.custid = 'demo-customer'
  cust.email = 'demo@example.com'
  cust.save
  cust.delete!
end
@commands.size > 0
#=> true

## Commands include full details
first_cmd = @commands.first
[first_cmd.key?(:command), first_cmd.key?(:duration), first_cmd.key?(:timestamp)]
#=> [true, true, true]

## Commands show Redis operation names
command_names = @commands.map { |cmd| cmd[:command].first }.uniq
command_names.all? { |name| name.is_a?(String) && !name.empty? }
#=> true

## Commands measure execution time in microseconds
@commands.all? { |cmd| cmd[:duration].is_a?(Numeric) && cmd[:duration] > 0 }
#=> true

## Commands include timestamps
@commands.all? { |cmd| cmd[:timestamp].is_a?(Time) }
#=> true

## DatabaseLogger can be enabled/disabled via environment variables
# FAMILIA_DEBUG=1 - Enable logging to STDOUT
# DEBUG_REDIS=1   - Enable logging to STDOUT
true
#=> true

## DatabaseLogger integrates with Familia models
## All Redis commands executed through Familia models are captured
commands = DatabaseLogger.capture_commands do
  V2::Customer.instances.size # This queries Redis
end
commands.size
#=> 1
