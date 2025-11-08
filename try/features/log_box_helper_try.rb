# frozen_string_literal: true

# Setup - Load the application
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

require_relative '../../lib/onetime'

## Can call log_box method
OT.respond_to?(:log_box)
#=> true

## Simple box outputs 3 lines (top, middle, bottom)
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Hello, world!'])
$stdout = @original_stdout
@output.string.split("
").length
#=> 3

## Top border starts with correct character
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Hello'])
$stdout = @original_stdout
@lines = @output.string.split("
")
@lines[0][0]
#=> '╔'

## Middle line contains content and has borders
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Test content'])
$stdout = @original_stdout
@lines = @output.string.split("
")
@lines[1].include?('Test content') && @lines[1][0] == '║'
#=> true

## Bottom border starts with correct character
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Test'])
$stdout = @original_stdout
@lines = @output.string.split("
")
@lines[-1][0]
#=> '╚'

## Multiple lines produce correct number of output lines (top + 3 content + bottom = 5)
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Line 1', 'Line 2', 'Line 3'])
$stdout = @original_stdout
@output.string.split("
").length
#=> 5

## Custom width creates correct border length (width + 2 for border chars)
@output = StringIO.new
@original_stdout = $stdout
$stdout = @output
OT.log_box(['Test'], width: 20)
$stdout = @original_stdout
@lines = @output.string.split("
")
@lines[0].length
#=> 22
