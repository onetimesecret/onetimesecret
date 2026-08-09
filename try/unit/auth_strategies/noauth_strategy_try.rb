# try/unit/auth_strategies/noauth_strategy_try.rb
#
# frozen_string_literal: true

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

## Anonymous user with empty session
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

## Authenticated user with session
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

## Session with identity but customer doesn't exist
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

## Strategy always succeeds (returns StrategyResult, never fails)
@results = [
  @strategy.authenticate({'rack.session' => {}}, nil),
  @strategy.authenticate({'rack.session' => {'external_id' => 'fake'}}, nil)
]
@results.all? { |r| r.is_a?(Otto::Security::Authentication::StrategyResult) }
#=> true

## Metadata is properly set
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

## Fail-closed on rejected credentials is enforced by Otto's terminal
## AuthFailure, not by NoAuthStrategy. BasicAuthStrategy rejects an
## explicitly-presented (but invalid) Authorization header with a TERMINAL
## failure; Otto's RouteAuthWrapper halts the chain on that (the end-to-end
## 401 is covered by spec/api/v2/basicauth_fallthrough_spec.rb). Regression
## for docs/security/audits/2026-07-29-api.md item 1.
@env_bad_basic = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  'HTTP_AUTHORIZATION' => 'Basic eDp5'
}
@basic_strategy = Onetime::Application::AuthStrategies::BasicAuthStrategy.new
@basic_result = @basic_strategy.authenticate(@env_bad_basic, nil)
[
  @basic_result.class.name,
  @basic_result.terminal?
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## NoAuthStrategy run on its own does NOT refuse a rejected-credential env —
## it stays anonymous. The fail-closed decision belongs to Otto's
## RouteAuthWrapper, which never consults noauth after the terminal failure.
@noauth_after_bad_basic = @strategy.authenticate(@env_bad_basic, nil)
[
  @noauth_after_bad_basic.class.name,
  @noauth_after_bad_basic.user.nil?
]
#=> ['Otto::Security::Authentication::StrategyResult', true]

## An Authorization header on a noauth-only route (no credentialed strategy
## ran) is ignored — the request stays anonymous. Proxy-forwarded or
## browser-cached Basic headers must not break noauth-only pages.
@env_header_only = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  'HTTP_AUTHORIZATION' => 'Basic eDp5'
}
@result_header_only = @strategy.authenticate(@env_header_only, nil)
[
  @result_header_only.class.name,
  @result_header_only.user.nil?
]
#=> ['Otto::Security::Authentication::StrategyResult', true]

## A valid session outranks a stray Authorization header: NoAuthStrategy
## resolves the session identity, so a logged-in user whose browser re-sends
## cached Basic credentials — or whose request passes through an htpasswd
## reverse proxy forwarding its own header — keeps their session identity
## instead of being 401'd mid-session.
@env_session_and_header = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @test_customer.extid,
    'email' => @test_customer.email
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  'HTTP_AUTHORIZATION' => 'Basic eDp5'
}
@result_session_and_header = @strategy.authenticate(@env_session_and_header, nil)
[
  @result_session_and_header.class.name,
  @result_session_and_header.authenticated?,
  @result_session_and_header.user&.custid == @test_customer.custid
]
#=> ['Otto::Security::Authentication::StrategyResult', true, true]

# Cleanup
@test_customer.delete!
