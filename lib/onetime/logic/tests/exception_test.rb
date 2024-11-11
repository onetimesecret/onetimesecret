require 'test/unit'
require_relative '../../test/helper'
require_relative '../exceptions'

class ExceptionTest < Test::Unit::TestCase
  include TestHelper

  def setup
    @logic = Onetime::Logic::Misc::ReceiveException.new(nil, {})
    redis_flush!
  end

  def test_valid_exception
    params = {
      message: "Test error",
      type: "TypeError",
      stack: "Error\n  at line 1\n  at line 2",
      url: "https://example.com/test",
      line: 42,
      column: 10,
      user_agent: "Mozilla/5.0",
      environment: "test",
      release: "1.0.0"
    }

    logic = Onetime::Logic::Misc::ReceiveException.new(nil, params)
    logic.process_params
    logic.process

    assert logic.greenlighted
    assert_not_nil logic.instance_variable_get(:@exception_key)
  end

  def test_truncates_long_values
    params = {
      message: "x" * 2000,
      type: "y" * 200,
      stack: "z" * 20000,
      url: "u" * 2000
    }

    logic = Onetime::Logic::Misc::ReceiveException.new(nil, params)
    logic.process_params
    data = logic.instance_variable_get(:@exception_data)

    assert_equal 1000, data[:message].length
    assert_equal 100, data[:type].length
    assert_equal 10000, data[:stack].length
    assert_equal 1000, data[:url].length
  end

  def test_rate_limiting
    params = { message: "Test", type: "Error", url: "http://test.com" }

    # Submit multiple exceptions quickly
    10.times do
      logic = Onetime::Logic::Misc::ReceiveException.new(nil, params)
      logic.process_params
      assert_raises(Onetime::RateLimitError) { logic.raise_concerns }
    end
  end
end
