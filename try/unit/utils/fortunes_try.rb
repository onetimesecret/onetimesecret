# try/unit/utils/fortunes_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

OT.boot! :test, false

@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)

## random_fortune returns a string
Onetime::Utils.random_fortune.class
#=> String

## random_fortune returns non-empty string when successful
Onetime::Utils.random_fortune.empty?
#=> false

## random_fortune handles nil fortunes gracefully
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)
Onetime::Utils.instance_variable_set(:@fortunes, nil)
result = Onetime::Utils.random_fortune
Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
result
#=> 'Unexpected outcomes bring valuable lessons.'

## random_fortune handles empty array gracefully
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)
Onetime::Utils.instance_variable_set(:@fortunes, [])
result = Onetime::Utils.random_fortune
Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
result
#=> 'Unexpected outcomes bring valuable lessons.'

## random_fortune handles unexpected errors gracefully
# This test intentionally injects an exception to verify error handling.
# Expected behavior: catch the exception, log it, and return a fallback fortune.
# The exception logged during this test is part of the test itself, not a failure.

# Store original fortunes
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)

# Create array that will raise exception when sample is called
test_array = ['test fortune']
test_array.define_singleton_method(:sample) { raise StandardError, "Test error" }

# Set our test array and execute the method. This will trigger the exception,
# which should be caught and logged by random_fortune.
Onetime::Utils.instance_variable_set(:@fortunes, test_array)
result = Onetime::Utils.random_fortune

Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
result
#=> 'A house is full of games and puzzles.'
