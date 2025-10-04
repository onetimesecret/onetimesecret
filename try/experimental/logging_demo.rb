# try/05_logging.rb

#
# Capture STDOUT and STDERR for testing
#
# Tryouts (the library) does its own capturing which conflicts with
# capture_io so these tests are skipped while we sort out how to make
# them work together. This is low risk since the tests are just for
# demonstration and debugging purposes.
#

require 'securerandom'

require_relative 'support/test_helpers'

def capture_io
  old_stdout = $stdout
  old_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
  return $stdout.string, $stderr.string
ensure
  $stdout = old_stdout
  $stderr = old_stderr
end


# TRYOUTS

## Can generate a random string
SecureRandom.hex.class
#=> String

## Can generate a different random string each time
initial_val = SecureRandom.hex
initial_val != SecureRandom.hex
#=> true



## Onetime.info logs to STDOUT
output = capture_io { Onetime.info("Test message") }
output.first.include?("I: Test message")
##=> true

## Onetime.le logs to STDERR
output = capture_io { Onetime.le("Test message") }
output.last.include?("E: Test message")
##=> true

## Onetime.ld logs to STDERR when debug is enabled
Onetime.debug = true
output = capture_io { Onetime.ld("Test message") }
output.last.include?("D: Test message")
##=> true

## Onetime.ld does not log to STDERR when debug is disabled
Onetime.debug = false
output = capture_io { Onetime.ld("Test message") }
output.last.empty?
##=> true
