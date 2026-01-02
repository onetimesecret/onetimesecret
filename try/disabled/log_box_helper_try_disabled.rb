# try/disabled/log_box_helper_try_disabled.rb
#
# frozen_string_literal: true

# Load minimal dependencies
require 'bundler/setup'
require 'semantic_logger'
require 'reline'  # For Reline::Unicode.calculate_width

# Load only the logger methods module
require_relative '../../lib/onetime/logger_methods'

# Create a test class that includes LoggerMethods
class LogBoxTester
  extend Onetime::LoggerMethods
end

# Force synchronous logging for tests
SemanticLogger.sync!
SemanticLogger.default_level = :trace

# Create StringIO and appender with trace level
@log_output = StringIO.new
@test_appender = SemanticLogger.add_appender(io: @log_output, level: :trace, formatter: :raw)

## Can call log_box method
LogBoxTester.respond_to?(:log_box)
#=> true

## Simple box outputs 3 lines (top, middle, bottom)
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Hello, world!'])
SemanticLogger.flush
@log_output.string.split("\n").length
#=> 3

## Top border starts with correct character
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Hello'])
SemanticLogger.flush
@lines = @log_output.string.split("\n")
@lines[0].include?('╭')
#=> true

## Middle line contains content and has borders
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Test content'])
SemanticLogger.flush
@lines = @log_output.string.split("\n")
@lines[1].include?('Test content') && @lines[1].include?('│')
#=> true

## Bottom border starts with correct character
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Test'])
SemanticLogger.flush
@lines = @log_output.string.split("\n")
@lines[-1].include?('╰')
#=> true

## Multiple lines produce correct number of output lines (top + 3 content + bottom = 5)
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Line 1', 'Line 2', 'Line 3'])
SemanticLogger.flush
@log_output.string.split("\n").length
#=> 5

## Custom width creates wider border
@log_output.truncate(0)
@log_output.rewind
LogBoxTester.log_box(['Test'], width: 60)
LogBoxTester.log_box(['Test'], width: 20)
SemanticLogger.flush
@lines = @log_output.string.split("\n")
# First box (width 60) should be wider than second box (width 20)
# Border is width + 2 chars for corners
@lines[0].include?('─' * 60) && @lines[3].include?('─' * 20)
#=> true

## Teardown
SemanticLogger.remove_appender(@test_appender)
