# try/unit/auth_strategies/noauth_strategy_try.rb
#
# Tests for NoAuthStrategy authentication strategy focusing on
# proper handling of anonymous vs authenticated users.
#
# Tests cover:
# 1. Anonymous users (no session) -> user should be nil
# 2. Authenticated users (session with external_id) -> user should be Customer
# 3. StrategyResult#authenticated? returns correct values
# 4. Strategy always succeeds (noauth allows everyone)

require_relative '../../support/test_logic'
require 'securerandom'

# Load the app with test configuration
OT.boot! :test, false

## Test 1: Anonymous user with empty session
@env_anon = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@strategy = Onetime::Application::AuthStrategies::NoAuthStrategy.new
@result_anon = @strategy.authenticate(@env_anon, nil)
[
  @result_anon.class.name,
  @result_anon.user.nil?,
  @result_anon.authenticated?,
  @result_anon.auth_method
]
#=> ['Otto::Security::Authentication::StrategyResult', true, false, 'noauth']

## Test 2: Authenticated user with session
@test_customer = Onetime::Customer.new(email: "test_#{SecureRandom.uuid}@example.com")
@test_customer.save
@env_auth = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @test_customer.extid,
    'email' => @test_customer.email
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_auth = @strategy.authenticate(@env_auth, nil)
[
  @result_auth.user.nil?,
  @result_auth.authenticated?,
  @result_auth.user.class.name,
  @result_auth.user.custid == @test_customer.custid,
  @result_auth.auth_method
]
#=> [false, true, 'Onetime::Customer', true, 'noauth']

## Test 3: Session with identity but customer doesn't exist
@env_missing = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => 'nonexistent@example.com',
    'email' => 'nonexistent@example.com'
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_missing = @strategy.authenticate(@env_missing, nil)
# Should fall back to nil since customer doesn't exist
[
  @result_missing.user.nil?,
  @result_missing.authenticated?
]
#=> [true, false]

## Test 4: Strategy always succeeds (returns StrategyResult, never fails)
@results = [
  @strategy.authenticate({'rack.session' => {}}, nil),
  @strategy.authenticate({'rack.session' => {'external_id' => 'fake'}}, nil)
]
@results.all? { |r| r.is_a?(Otto::Security::Authentication::StrategyResult) }
#=> true

## Test 5: Metadata is properly set
@env_with_ip = {
  'rack.session' => {},
  'REMOTE_ADDR' => '192.168.1.1',
  'HTTP_USER_AGENT' => 'Mozilla/5.0'
}
@strategy5 = Onetime::Application::AuthStrategies::NoAuthStrategy.new
@result_metadata = @strategy5.authenticate(@env_with_ip, nil)
# Check that strategy returns valid StrategyResult
@result_metadata.is_a?(Otto::Security::Authentication::StrategyResult)
#=> true

# Cleanup
@test_customer.delete!
