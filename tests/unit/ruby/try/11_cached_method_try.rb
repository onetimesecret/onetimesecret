# tests/unit/ruby/try/11_cached_method_try.rb

# These tryouts test the functionality of the cached_method in the Core::ViewHelpers module.
# The cached_method provides a caching mechanism for method results using Redis.
#
# We're testing various aspects of the cached_method, including:
# 1. Caching of method results
# 2. Retrieval of cached results
# 3. Expiration of cached results
#
# These tests aim to ensure that the caching mechanism works correctly,
# which is crucial for improving performance in the Onetime application.
#
# The tryouts simulate different scenarios of using the cached_method
# without needing to run the full application, allowing for targeted
# testing of this specific functionality.

require_relative './test_helpers'

require 'core/views'

# Familia.debug = true

# Use the default config file for tests
OT.boot! :test, false

@num = rand(1000)

class TestHelper
  include Core::Views::SanitizerHelpers
  attr_reader :num

  def initialize(num)
    @num = num
  end

  def test_method
    "This is a test result: #{num}"
  end
end

@helper = TestHelper.new @num

## First call should cache the result
@result1 = @helper.cached_method(:test_method) { @helper.test_method }
p [:start1, @num]
@result1.class
#=> String

## Content is as expected
p [:start2, @num]
p @helper.num
@numb = @num
@result1
#=> "This is a test result: #{@numb}"

## Second call should return the cached result
result2 = @helper.cached_method(:test_method) { @helper.test_method }
result2 == @result1
#=> true

## Call with different method name should cache separately
result3 = @helper.cached_method(:another_method) { "Another result: #{rand(100)}" }
result3 == @result1
#=> false

## Manually expire the cache
Familia::String.new("template:global:test_method", ttl: 1.hour, db: 0).delete!
#=> true

## Call after expiration should generate a new result
content = @helper.cached_method(:test_method) { @helper.test_method }
p content
p @result1
content == @result1
#=> true

Familia::String.new("template:global:test_method", ttl: 1.hour, db: 0).delete!
