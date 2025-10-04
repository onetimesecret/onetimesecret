# try/05_logging_sync_try.rb

#
# Capture STDOUT and STDERR for testing
#
# Tryouts (the library) does its own capturing which conflicts with
# capture_io so these tests are skipped while we sort out how to make
# them work together. This is low risk since the tests are just for
# demonstration and debugging purposes.
#

require_relative '../support/test_helpers'

@original_env = ENV.to_h
@sync_values = %w[true yes 1]

## Sanity check
@sync_values.include?(ENV['STDOUT_SYNC'])
#=> false

## Setting STDOUT_SYNC to 'true' enables sync
ENV['STDOUT_SYNC'] = 'true'
STDOUT.sync = @sync_values.include?(ENV['STDOUT_SYNC'])
STDOUT.sync
#=> true

## Setting STDOUT_SYNC to 'yes' enables sync
ENV['STDOUT_SYNC'] = 'yes'
STDOUT.sync = @sync_values.include?(ENV['STDOUT_SYNC'])
STDOUT.sync
#=> true

## Setting STDOUT_SYNC to '1' enables sync
ENV['STDOUT_SYNC'] = '1'
STDOUT.sync = @sync_values.include?(ENV['STDOUT_SYNC'])
STDOUT.sync
#=> true

## Setting STDOUT_SYNC to 'false' disables sync
ENV['STDOUT_SYNC'] = 'false'
STDOUT.sync = @sync_values.include?(ENV['STDOUT_SYNC'])
STDOUT.sync
#=> false

## Setting STDOUT_SYNC to an empty string disables sync
ENV['STDOUT_SYNC'] = ''
STDOUT.sync = @sync_values.include?(ENV['STDOUT_SYNC'])
STDOUT.sync
#=> false

## Default sync value in ruby process is false but irb is true
`ruby -e 'print STDOUT.sync'`
#=> "false"


## New IO object has sync set to false by default
io = IO.new(IO.sysopen("/dev/null", "w"))
io.sync
#=> false

## Environment variables don't force stdout sync to true
ENV['STDOUT_SYNC']
#=> ""

# Teardown
ENV.clear
ENV.update(@original_env)
STDOUT.sync = false
