# tests/unit/ruby/try/10_onetime_utils_fortunes_try.rb

require_relative '../helpers/test_helpers'

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

## random_fortune handles unexpected errors gracefull
# Store original fortunes
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)

# Create array that will raise exception when sample is called
test_array = ['test fortune']
test_array.define_singleton_method(:sample) { raise StandardError, "Test error" }

# Set our test array and execute the method
Onetime::Utils.instance_variable_set(:@fortunes, test_array)
result = Onetime::Utils.random_fortune

Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
result
#=> 'A house is full of games and puzzles.'
