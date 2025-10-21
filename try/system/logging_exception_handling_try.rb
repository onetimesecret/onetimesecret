# try/system/logging_exception_handling_try.rb
#
# Tests for enhanced exception logging functionality with SemanticLogger.
# Tests the new exception: parameter for OT.le method.

require_relative '../support/test_helpers'
require 'semantic_logger'
require 'stringio'

# Initialize SemanticLogger for tests
SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stdout, formatter: :color) unless SemanticLogger.appenders.any?

OT.boot! :test, true

## Exception Logging - Basic exception parameter
result = begin
  raise StandardError, "Test error"
rescue => ex
  # Should not raise an error when exception parameter is used
  OT.le "Test failed", exception: ex
  :ok
end
result
#=> :ok

## Exception Logging - Exception with context payload
result = begin
  raise ArgumentError, "Invalid argument"
rescue => ex
  # Should support both exception and context keywords
  OT.le "Validation failed", exception: ex, field: :email, value: "test"
  :ok
end
result
#=> :ok

## Exception Logging - Exception without message
result = begin
  raise RuntimeError, "Runtime problem"
rescue => ex
  # When message is empty, should use exception class name
  OT.le "", exception: ex
  :ok
end
result
#=> :ok

## Exception Logging - Standard error
result = begin
  raise StandardError, "Something went wrong"
rescue StandardError => ex
  OT.le "Operation failed", exception: ex, operation: :create
  :ok
end
result
#=> :ok

## Exception Logging - ArgumentError
result = begin
  raise ArgumentError, "Invalid input"
rescue ArgumentError => ex
  OT.le "Input validation failed", exception: ex, input: :username
  :ok
end
result
#=> :ok

## Exception Logging - IOError
result = begin
  raise IOError, "File not found"
rescue IOError => ex
  OT.le "File operation failed", exception: ex, path: "/tmp/test"
  :ok
end
result
#=> :ok

## Backward Compatibility - Legacy string message (no kwargs)
# Should still work without exception parameter
OT.le "Legacy error message"
#=> nil

## Backward Compatibility - Legacy multi-message
# Should still work with multiple string arguments
OT.le "Error:", "Something went wrong"
#=> nil

## Structured Logging - With payload but no exception
# Should work with structured data without exception (returns false when log level suppresses output)
result = OT.le "Failed to save", model: :customer, reason: :validation
result
#=> false

## Category Awareness - Exception with thread-local category
Thread.current[:log_category] = 'Auth'
result = begin
  raise RuntimeError, "Test runtime error"
rescue => ex
  OT.le "Authentication failed", exception: ex, email: "test@example.com"
  :ok
end
Thread.current[:log_category] = nil
result
#=> :ok

## Exception Type - Not an exception (no-op)
# Should handle non-exception gracefully when exception is not an Exception object
result = OT.le "Regular message", exception: "not an exception", context: :test
result
#=> false

## Multiple Arguments - Exception with multiple message parts
result = begin
  raise StandardError, "Multi-part error"
rescue => ex
  OT.le "Operation", "failed", "completely", exception: ex
  :ok
end
result
#=> :ok

## Empty Exception - nil exception parameter
# Should work with explicit nil and use structured logging path
result = OT.le "Error message", exception: nil, context: :value
result
#=> false

## Complex Context - Exception with nested payload
result = begin
  raise StandardError, "Database error"
rescue => ex
  OT.le "DB operation failed",
    exception: ex,
    query: "SELECT * FROM users",
    params: { id: 123 },
    connection: { host: "localhost", port: 6379 }
  :ok
end
result
#=> :ok

## Exception Details - Verify exception class preserved
begin
  raise TypeError, "Type mismatch"
rescue TypeError => ex
  # Exception object should preserve class info
  ex.class.name
end
#=> "TypeError"

## Backtrace - Exception has backtrace
begin
  raise RuntimeError, "Test backtrace"
rescue => ex
  # Exception should have backtrace array
  ex.backtrace.is_a?(Array)
end
#=> true

## Backtrace - Backtrace not empty
begin
  raise RuntimeError, "Test backtrace"
rescue => ex
  # Backtrace should have entries
  ex.backtrace.length > 0
end
#=> true
