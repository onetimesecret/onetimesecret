# try/system/semantic_logger_fork_safety_try.rb
#
# frozen_string_literal: true

# Tryouts for SemanticLogger fork safety methods.
# Tests that flush and reopen work correctly for Puma cluster mode.
#
# Background: Puma in cluster mode with preload_app! forks worker processes.
# SemanticLogger's async appender creates background threads that don't
# survive fork properly. The solution is:
#   - before_fork: SemanticLogger.flush (flush pending logs)
#   - before_worker_boot: SemanticLogger.reopen (re-open appenders)
#
# See: https://github.com/reidmorrison/semantic_logger/blob/master/docs/forking.md

require_relative '../support/test_helpers'
require 'semantic_logger'

# Initialize SemanticLogger for tests (mimics production setup)
SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stdout, formatter: :color) unless SemanticLogger.appenders.any?

OT.boot! :test, true

## SemanticLogger responds to flush
SemanticLogger.respond_to?(:flush)
#=> true

## SemanticLogger responds to reopen
SemanticLogger.respond_to?(:reopen)
#=> true

## SemanticLogger.flush completes without error
result = begin
  SemanticLogger.flush
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## SemanticLogger.reopen completes without error
result = begin
  SemanticLogger.reopen
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## Fork safety sequence: flush then reopen (simulates Puma fork cycle)
# This mimics what happens during Puma's fork:
#   1. Master calls flush before forking
#   2. Worker calls reopen after fork
result = begin
  SemanticLogger.flush   # before_fork
  SemanticLogger.reopen  # before_worker_boot
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## Multiple flush calls are safe (idempotent)
result = begin
  3.times { SemanticLogger.flush }
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## Multiple reopen calls are safe (idempotent)
result = begin
  3.times { SemanticLogger.reopen }
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## Logging works after reopen
result = begin
  SemanticLogger.reopen
  logger = SemanticLogger['ForkSafetyTest']
  logger.info("Test message after reopen")
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true

## Appenders exist after reopen
SemanticLogger.reopen
SemanticLogger.appenders.any?
#=> true

## Flush with pending log messages
result = begin
  logger = SemanticLogger['FlushTest']
  logger.info("Message before flush")
  SemanticLogger.flush
  true
rescue => e
  "Error: #{e.class} - #{e.message}"
end
result
#=> true
