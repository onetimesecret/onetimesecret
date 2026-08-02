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

## Anonymous fallthrough refusal: when a credentialed strategy already
## rejected presented credentials (marker set in env), NoAuthStrategy must
## return an AuthFailure echoing that reason — never anonymous success.
## Regression for docs/security/audits/2026-07-29-api.md item 1.
@marker_key = Onetime::Application::AuthStrategies::Helpers::CREDENTIALED_FAILURE_ENV_KEY
@env_refused = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  @marker_key => '[CREDENTIALS_INVALID] Invalid credentials'
}
@result_refused = @strategy.authenticate(@env_refused, nil)
[
  @result_refused.class.name,
  @result_refused.failure_reason
]
#=> ['Otto::Security::Authentication::AuthFailure', '[CREDENTIALS_INVALID] Invalid credentials']

## Chain simulation: BasicAuthStrategy rejects an unrecognized Authorization
## scheme and marks the env; NoAuthStrategy (same env, as in Otto's
## RouteAuthWrapper OR chain) then refuses instead of going anonymous.
@env_bearer = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  'HTTP_AUTHORIZATION' => 'Bearer some_token'
}
@basic_strategy = Onetime::Application::AuthStrategies::BasicAuthStrategy.new
@basic_result = @basic_strategy.authenticate(@env_bearer, nil)
@noauth_after_basic = @strategy.authenticate(@env_bearer, nil)
[
  @basic_result.class.name,
  @env_bearer.key?(@marker_key),
  @noauth_after_basic.class.name
]
#=> ['Otto::Security::Authentication::AuthFailure', true, 'Otto::Security::Authentication::AuthFailure']

## An Authorization header WITHOUT a credentialed-strategy failure (noauth-only
## route: no credentialed strategy ran, no marker) is ignored — the request
## stays anonymous. Proxy-forwarded or browser-cached Basic headers must not
## break noauth-only pages.
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

## A valid session outranks a rejected Authorization header: the refusal only
## applies to requests that would otherwise become ANONYMOUS. A logged-in user
## whose browser re-sends cached Basic credentials — or whose request passes
## through an htpasswd reverse proxy that forwards its own header — must keep
## their session identity instead of being 401'd mid-session.
@env_session_and_marker = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @test_customer.extid,
    'email' => @test_customer.email
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  'HTTP_AUTHORIZATION' => 'Basic eDp5',
  @marker_key => '[CREDENTIALS_INVALID] Invalid credentials'
}
@result_session_and_marker = @strategy.authenticate(@env_session_and_marker, nil)
[
  @result_session_and_marker.class.name,
  @result_session_and_marker.authenticated?,
  @result_session_and_marker.user&.custid == @test_customer.custid
]
#=> ['Otto::Security::Authentication::StrategyResult', true, true]

## Marker + a session that resolves NO identity (logged out, or stale/deleted
## customer) still fails closed — the fallthrough hole stays shut.
@env_stale_session_and_marker = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => 'nonexistent@example.com'
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0',
  @marker_key => '[CREDENTIALS_INVALID] Invalid credentials'
}
@result_stale = @strategy.authenticate(@env_stale_session_and_marker, nil)
[
  @result_stale.class.name,
  @result_stale.failure_reason
]
#=> ['Otto::Security::Authentication::AuthFailure', '[CREDENTIALS_INVALID] Invalid credentials']

# Cleanup
@test_customer.delete!
