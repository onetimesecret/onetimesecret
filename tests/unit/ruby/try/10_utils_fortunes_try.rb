# tests/unit/ruby/try/10_utils_fortunes_try.rb

require_relative './test_helpers'

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
#=> 'A house is full of games and puzzles.'

## random_fortune handles empty array gracefully
@original_fortunes = Onetime::Utils.instance_variable_get(:@fortunes)
Onetime::Utils.instance_variable_set(:@fortunes, [])
result = Onetime::Utils.random_fortune
Onetime::Utils.instance_variable_set(:@fortunes, @original_fortunes)
result
#=> 'A house is full of games and puzzles.'
