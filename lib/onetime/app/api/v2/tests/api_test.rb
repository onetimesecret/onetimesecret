require 'test/unit'
require 'rack/test'
require_relative '../../../../test/helper'

class APIV2Test < Test::Unit::TestCase
  include TestHelper
  include Rack::Test::Methods

  def app
    Onetime::App::API
  end

  def setup
    redis_flush!
  end

  def test_receive_exception
    post '/v2/exception', {
      message: "Test error",
      type: "TypeError",
      stack: "Error\n  at line 1",
      url: "https://example.com/test",
      line: 42,
      column: 10
    }

    assert_equal 200, last_response.status
    response = JSON.parse(last_response.body)
    assert response['success']
    assert_not_nil response['record']['exception_id']
  end

  def test_receive_exception_without_message
    post '/v2/exception', {
      type: "TypeError",
      url: "https://example.com/test"
    }

    assert_equal 400, last_response.status
    response = JSON.parse(last_response.body)
    assert !response['success']
  end

  def test_receive_exception_with_auth
    authorize 'testuser', 'testpass'
    post '/v2/exception', {
      message: "Test error",
      type: "TypeError"
    }

    assert_equal 200, last_response.status
    response = JSON.parse(last_response.body)
    assert response['success']
    assert_match(/cust:/, response['record']['user'])
  end
end
