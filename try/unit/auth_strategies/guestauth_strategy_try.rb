# try/unit/auth_strategies/guestauth_strategy_try.rb
#
# frozen_string_literal: true

#
# Tests for GuestAuthStrategy authentication strategy focusing on
# config-based operation control and proper handling of anonymous vs
# authenticated users.
#
# Tests cover:
# 1. Anonymous users allowed (user should be nil)
# 2. Authenticated users allowed (user should be Customer)
# 3. Path matching for operation extraction
# 4. Strategy succeeds when operations are enabled
#
# Note: Configuration is frozen after boot, so we test with the default
# enabled state. Disabled state testing would require environment variables
# or integration tests that boot with different configs.

require_relative '../../support/test_logic'
require 'securerandom'

# Load the app with test configuration
OT.boot! :test, false

@strategy = Onetime::Application::AuthStrategies::GuestAuthStrategy.new

## Test 1: Verify guest routes are enabled in test config
@guest_config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
[
  @guest_config['enabled'],
  @guest_config['conceal'],
  @guest_config['generate'],
  @guest_config['reveal'],
  @guest_config['burn']
]
#=> [true, true, true, true, true]

## Test 2: Anonymous user with guest routes enabled
@env_anon_guest = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/share/secret/conceal',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_anon_guest = @strategy.authenticate(@env_anon_guest, nil)
[
  @result_anon_guest.class.name,
  @result_anon_guest.user.nil?,
  @result_anon_guest.authenticated?,
  @result_anon_guest.auth_method
]
#=> ['Otto::Security::Authentication::StrategyResult', true, false, 'guestauth']

## Test 3: Authenticated user with guest routes
@test_customer = Onetime::Customer.new(email: "test_guest_#{SecureRandom.uuid}@example.com")
@test_customer.save
@env_auth_guest = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @test_customer.extid,
    'email' => @test_customer.email
  },
  'PATH_INFO' => '/api/v3/share/secret/generate',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_auth_guest = @strategy.authenticate(@env_auth_guest, nil)
[
  @result_auth_guest.user.nil?,
  @result_auth_guest.authenticated?,
  @result_auth_guest.user.class.name,
  @result_auth_guest.user.custid == @test_customer.custid,
  @result_auth_guest.auth_method
]
#=> [false, true, 'Onetime::Customer', true, 'guestauth']

## Test 4: Path matching for conceal operation
@env_conceal = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/share/secret/conceal',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_conceal = @strategy.authenticate(@env_conceal, nil)
[
  @result_conceal.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_conceal.auth_method
]
#=> [true, 'guestauth']

## Test 5: Path matching for generate operation
@env_generate = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/share/secret/generate',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_generate = @strategy.authenticate(@env_generate, nil)
[
  @result_generate.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_generate.auth_method
]
#=> [true, 'guestauth']

## Test 6: Path matching for reveal operation
@env_reveal = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/share/secret/xyz123/reveal',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_reveal = @strategy.authenticate(@env_reveal, nil)
[
  @result_reveal.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_reveal.auth_method
]
#=> [true, 'guestauth']

## Test 7: Path matching for burn operation
@env_burn = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/share/receipt/xyz123/burn',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_burn = @strategy.authenticate(@env_burn, nil)
[
  @result_burn.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_burn.auth_method
]
#=> [true, 'guestauth']

## Test 8: Non-guest path (should still succeed but no operation extracted)
@env_non_guest = {
  'rack.session' => {},
  'PATH_INFO' => '/api/v3/some/other/path',
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_non_guest = @strategy.authenticate(@env_non_guest, nil)
[
  @result_non_guest.is_a?(Otto::Security::Authentication::StrategyResult),
  @result_non_guest.user.nil?,
  @result_non_guest.authenticated?
]
#=> [true, true, false]

# Cleanup
@test_customer.delete!
