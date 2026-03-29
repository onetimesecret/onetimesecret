# try/unit/auth/dev_auth_strategies_try.rb
#
# frozen_string_literal: true

#
# Tests for development-only authentication strategies.
#
# These strategies enable dev workflows with auto-provisioned ephemeral users.
# They MUST be blocked in production environments.
#
# @see DevBasicAuthStrategy - API/curl-based auth with dev_ prefix
# @see DevSessionAuthStrategy - Browser-based auth validating dev_* sessions

require_relative '../../support/test_helpers'
require 'onetime/application/auth_strategies'

# Boot in test mode
OT.boot! :test, true

# Aliases for cleaner test code
DevBasicAuth = Onetime::Application::AuthStrategies::DevBasicAuthStrategy
DevSessionAuth = Onetime::Application::AuthStrategies::DevSessionAuthStrategy
AuthStrategies = Onetime::Application::AuthStrategies

# Setup test variables
@now = Familia.now

# TRYOUTS

# =============================================================================
# DevBasicAuthStrategy Tests
# =============================================================================

## DevBasicAuthStrategy has correct auth method name
DevBasicAuth.auth_method_name
#=> 'dev_basic_auth'

## DevBasicAuthStrategy has 20-hour TTL constant
DevBasicAuth::DEV_CUSTOMER_TTL
#=> 72000

## DevBasicAuthStrategy has dev_ prefix constant
DevBasicAuth::DEV_PREFIX
#=> 'dev_'

## DevBasicAuthStrategy can be instantiated
strategy = DevBasicAuth.new
strategy.class
#=> Onetime::Application::AuthStrategies::DevBasicAuthStrategy

# =============================================================================
# DevSessionAuthStrategy Tests
# =============================================================================

## DevSessionAuthStrategy has correct auth method name
DevSessionAuth.auth_method_name
#=> 'dev_session_auth'

## DevSessionAuthStrategy has dev_ prefix constant
DevSessionAuth::DEV_PREFIX
#=> 'dev_'

## DevSessionAuthStrategy can be instantiated
strategy = DevSessionAuth.new
strategy.class
#=> Onetime::Application::AuthStrategies::DevSessionAuthStrategy

# =============================================================================
# Config Check Methods
# =============================================================================

## dev_basic_auth_enabled? returns false by default
# Clear env vars to ensure clean test
original_basic = ENV['DEV_BASIC_AUTH']
ENV.delete('DEV_BASIC_AUTH')
result = AuthStrategies.dev_basic_auth_enabled?
ENV['DEV_BASIC_AUTH'] = original_basic if original_basic
result
#=> false

## dev_basic_auth_enabled? returns true when env var is set
original = ENV['DEV_BASIC_AUTH']
ENV['DEV_BASIC_AUTH'] = 'true'
result = AuthStrategies.dev_basic_auth_enabled?
ENV['DEV_BASIC_AUTH'] = original if original
ENV.delete('DEV_BASIC_AUTH') unless original
result
#=> true

## dev_session_auth_enabled? returns false by default
# Clear env vars to ensure clean test
original_session = ENV['DEV_SESSION_AUTH']
ENV.delete('DEV_SESSION_AUTH')
result = AuthStrategies.dev_session_auth_enabled?
ENV['DEV_SESSION_AUTH'] = original_session if original_session
result
#=> false

## dev_session_auth_enabled? returns true when env var is set
original = ENV['DEV_SESSION_AUTH']
ENV['DEV_SESSION_AUTH'] = 'true'
result = AuthStrategies.dev_session_auth_enabled?
ENV['DEV_SESSION_AUTH'] = original if original
ENV.delete('DEV_SESSION_AUTH') unless original
result
#=> true

# =============================================================================
# DevSessionAuthStrategy - dev_user? validation
# =============================================================================

## DevSessionAuth validates dev_ prefix (valid)
strategy = DevSessionAuth.new
@entropy = SecureRandom.hex(4)
@dev_email = "dev_testuser_#{@entropy}@example.com"
@dev_cust = Onetime::Customer.create!(email: @dev_email)
strategy.send(:dev_user?, @dev_cust)
#=> true

## DevSessionAuth rejects email without dev_ prefix
strategy = DevSessionAuth.new
@regular_email = generate_unique_test_email("notdev")
@regular_cust = Onetime::Customer.create!(email: @regular_email)
strategy.send(:dev_user?, @regular_cust)
#=> false

# =============================================================================
# DevBasicAuthStrategy - valid_dev_credentials? validation
# =============================================================================

## DevBasicAuth validates dev_ prefix on both username and apikey
strategy = DevBasicAuth.new
strategy.send(:valid_dev_credentials?, 'dev_alice', 'dev_secret123')
#=> true

## DevBasicAuth rejects when username lacks dev_ prefix
strategy = DevBasicAuth.new
strategy.send(:valid_dev_credentials?, 'alice', 'dev_secret123')
#=> false

## DevBasicAuth rejects when apikey lacks dev_ prefix
strategy = DevBasicAuth.new
strategy.send(:valid_dev_credentials?, 'dev_alice', 'secret123')
#=> false

## DevBasicAuth rejects when both lack dev_ prefix
strategy = DevBasicAuth.new
strategy.send(:valid_dev_credentials?, 'alice', 'secret123')
#=> false

## DevBasicAuth rejects nil credentials
strategy = DevBasicAuth.new
strategy.send(:valid_dev_credentials?, nil, nil)
#=> false

# =============================================================================
# DevBasicAuthStrategy#authenticate Tests
# =============================================================================

## DevBasicAuth#authenticate with valid dev_* credentials succeeds
@dev_username = "dev_testauth_#{SecureRandom.hex(4)}"
@dev_apikey = "dev_apikey_#{SecureRandom.hex(8)}"
@basic_auth_header = "Basic #{Base64.strict_encode64("#{@dev_username}:#{@dev_apikey}")}"
@env_dev_basic = {
  'HTTP_AUTHORIZATION' => @basic_auth_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@dev_basic_strategy = DevBasicAuth.new
@result_dev_basic = @dev_basic_strategy.authenticate(@env_dev_basic, nil)
[
  @result_dev_basic.class.name,
  @result_dev_basic.authenticated?,
  @result_dev_basic.metadata[:dev_user],
  @result_dev_basic.metadata[:ttl_seconds]
]
#=> ['Otto::Security::Authentication::StrategyResult', true, true, 72000]

## DevBasicAuth#authenticate creates ephemeral customer with dev_* email
@result_dev_basic.user.email.start_with?(@dev_username) && @result_dev_basic.user.email.end_with?('@dev.local')
#=> true

## DevBasicAuth#authenticate with non-dev username fails
@non_dev_username = "regular_user_#{SecureRandom.hex(4)}"
@non_dev_header = "Basic #{Base64.strict_encode64("#{@non_dev_username}:dev_secret123")}"
@env_non_dev = {
  'HTTP_AUTHORIZATION' => @non_dev_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_non_dev = DevBasicAuth.new.authenticate(@env_non_dev, nil)
[
  @result_non_dev.class.name,
  @result_non_dev.failure_reason.include?('DEV_PREFIX_REQUIRED')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevBasicAuth#authenticate with non-dev apikey fails
@non_dev_apikey_header = "Basic #{Base64.strict_encode64("dev_alice:regular_secret123")}"
@env_non_dev_apikey = {
  'HTTP_AUTHORIZATION' => @non_dev_apikey_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_non_dev_apikey = DevBasicAuth.new.authenticate(@env_non_dev_apikey, nil)
@result_non_dev_apikey.failure_reason.include?('DEV_PREFIX_REQUIRED')
#=> true

## DevBasicAuth#authenticate production guard returns failure (not exception)
# Temporarily set RACK_ENV to production to test the guard
original_rack_env = ENV['RACK_ENV']
ENV['RACK_ENV'] = 'production'
# Reload OT.env by checking production? directly
@prod_guard_result = DevBasicAuth.new.authenticate(@env_dev_basic, nil)
ENV['RACK_ENV'] = original_rack_env
[
  @prod_guard_result.class.name,
  @prod_guard_result.failure_reason.include?('DEV_AUTH_BLOCKED')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevBasicAuth#authenticate handles RecordExistsError race condition by retry
# First create the customer so a race condition would occur.
# NOTE: With DevWorkerIdentity, emails are namespaced for parallel CI execution.
# We need to pre-compute the namespaced email that the strategy will use.
@race_username = "dev_race_#{SecureRandom.hex(4)}"
@race_apikey = "dev_racekey_#{SecureRandom.hex(8)}"

# Compute the namespaced email the strategy will look for
@identity = Onetime::Application::AuthStrategies::DevWorkerIdentity
@race_base_name = @race_username.delete_prefix('dev_')
@race_namespaced = "dev_#{@identity.namespaced_username(@race_base_name)}"
@race_email = "#{@race_namespaced}@dev.local"

# Pre-create the customer with the namespaced email (simulates another request winning the race)
@precreated_cust = Onetime::Customer.create!(email: @race_email, role: 'customer')
@precreated_cust.apitoken = @race_apikey
@precreated_cust.save

@race_auth_header = "Basic #{Base64.strict_encode64("#{@race_username}:#{@race_apikey}")}"
@env_race = {
  'HTTP_AUTHORIZATION' => @race_auth_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}

# This should find the existing customer (simulates race resolution)
@result_race = DevBasicAuth.new.authenticate(@env_race, nil)
[
  @result_race.class.name,
  @result_race.authenticated?,
  @result_race.user.email == @race_email
]
#=> ['Otto::Security::Authentication::StrategyResult', true, true]

# =============================================================================
# DevSessionAuthStrategy#authenticate Tests
# =============================================================================

## DevSessionAuth#authenticate with dev user session succeeds
@session_dev_email = "dev_sessionauth_#{SecureRandom.hex(4)}@example.com"
@session_dev_cust = Onetime::Customer.create!(email: @session_dev_email, role: 'customer')
@env_dev_session = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @session_dev_cust.extid
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_dev_session = DevSessionAuth.new.authenticate(@env_dev_session, nil)
[
  @result_dev_session.class.name,
  @result_dev_session.authenticated?,
  @result_dev_session.metadata[:dev_user]
]
#=> ['Otto::Security::Authentication::StrategyResult', true, true]

## DevSessionAuth#authenticate with non-dev user session fails
@session_regular_email = "regular_sessionauth_#{SecureRandom.hex(4)}@example.com"
@session_regular_cust = Onetime::Customer.create!(email: @session_regular_email, role: 'customer')
@env_regular_session = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @session_regular_cust.extid
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_regular_session = DevSessionAuth.new.authenticate(@env_regular_session, nil)
[
  @result_regular_session.class.name,
  @result_regular_session.failure_reason.include?('DEV_USER_REQUIRED')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevSessionAuth#authenticate production guard returns failure
original_rack_env = ENV['RACK_ENV']
ENV['RACK_ENV'] = 'production'
@prod_session_result = DevSessionAuth.new.authenticate(@env_dev_session, nil)
ENV['RACK_ENV'] = original_rack_env
[
  @prod_session_result.class.name,
  @prod_session_result.failure_reason.include?('DEV_AUTH_BLOCKED')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

# =============================================================================
# Cleanup
# =============================================================================

# Customer records created during tests are left for inspection
# They will be cleaned up by Redis TTL or manual cleanup
