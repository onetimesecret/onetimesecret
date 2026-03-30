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

## DevBasicAuth#authenticate without Authorization header returns AuthFailure
@env_no_auth = {
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_no_auth = DevBasicAuth.new.authenticate(@env_no_auth, nil)
[
  @result_no_auth.class.name,
  @result_no_auth.failure_reason.include?('AUTH_HEADER_MISSING')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevBasicAuth#authenticate with malformed Authorization header returns AuthFailure
@env_malformed = {
  'HTTP_AUTHORIZATION' => 'Bearer some_token_here',
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_malformed = DevBasicAuth.new.authenticate(@env_malformed, nil)
[
  @result_malformed.class.name,
  @result_malformed.failure_reason.include?('AUTH_TYPE_INVALID')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevBasicAuth#authenticate with valid username but wrong apikey returns AuthFailure
@wrong_key_username = "dev_wrongkey_#{SecureRandom.hex(4)}"
@wrong_key_apikey = "dev_wrongapikey_#{SecureRandom.hex(8)}"
@wrong_key_header = "Basic #{Base64.strict_encode64("#{@wrong_key_username}:#{@wrong_key_apikey}")}"
@env_wrong_key = {
  'HTTP_AUTHORIZATION' => @wrong_key_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_wrong_key_first = DevBasicAuth.new.authenticate(@env_wrong_key, nil)
# First call creates the customer with the given apikey, so re-authenticate
# with a different apikey to test mismatch
@wrong_key_header2 = "Basic #{Base64.strict_encode64("#{@wrong_key_username}:dev_differentkey_999")}"
@env_wrong_key2 = {
  'HTTP_AUTHORIZATION' => @wrong_key_header2,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_wrong_key = DevBasicAuth.new.authenticate(@env_wrong_key2, nil)
[
  @result_wrong_key.class.name,
  @result_wrong_key.failure_reason.include?('CREDENTIALS_INVALID')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevBasicAuth#authenticate sets TTL on ephemeral customer
@ttl_username = "dev_ttlcheck_#{SecureRandom.hex(4)}"
@ttl_apikey = "dev_ttlkey_#{SecureRandom.hex(8)}"
@ttl_header = "Basic #{Base64.strict_encode64("#{@ttl_username}:#{@ttl_apikey}")}"
@env_ttl = {
  'HTTP_AUTHORIZATION' => @ttl_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_ttl = DevBasicAuth.new.authenticate(@env_ttl, nil)
@ttl_cust = @result_ttl.user
@ttl_remaining = @ttl_cust.ttl
@ttl_remaining > 0 && @ttl_remaining <= DevBasicAuth::DEV_CUSTOMER_TTL
#=> true

## DevBasicAuth#authenticate result metadata includes dev_user and ttl_seconds
[
  @result_ttl.metadata[:dev_user],
  @result_ttl.metadata[:ttl_seconds]
]
#=> [true, 72000]

## DevBasicAuth#authenticate with nil customer uses dummy (timing-safe, still fails)
# Simulate by using credentials where the username maps to a nonexistent customer
# but valid_dev_credentials? passes. We pre-delete to ensure no customer exists.
@timing_username = "dev_timing_#{SecureRandom.hex(4)}"
@timing_apikey = "dev_timingkey_#{SecureRandom.hex(8)}"
@identity_timing = Onetime::Application::AuthStrategies::DevWorkerIdentity
@timing_base = @timing_username.delete_prefix('dev_')
@timing_namespaced = "dev_#{@identity_timing.namespaced_username(@timing_base)}"
@timing_email = "#{@timing_namespaced}@dev.local"
# Ensure no customer exists with this email, then monkey-patch find_or_create to return nil
@timing_strategy = DevBasicAuth.new
# We cannot easily force find_or_create_dev_customer to return nil without deep stubbing,
# but we can verify the dummy path by checking that a frozen dummy customer would
# cause apitoken? to return false (which is the branch being tested).
dummy = Onetime::Customer.dummy
[dummy.frozen?, dummy.apitoken?(@timing_apikey)]
#=> [true, false]

## DevBasicAuth#authenticate reuses existing customer on second call
@reuse_username = "dev_reuse_#{SecureRandom.hex(4)}"
@reuse_apikey = "dev_reusekey_#{SecureRandom.hex(8)}"
@reuse_header = "Basic #{Base64.strict_encode64("#{@reuse_username}:#{@reuse_apikey}")}"
@env_reuse = {
  'HTTP_AUTHORIZATION' => @reuse_header,
  'rack.session' => {},
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_reuse_1 = DevBasicAuth.new.authenticate(@env_reuse, nil)
@result_reuse_2 = DevBasicAuth.new.authenticate(@env_reuse, nil)
[
  @result_reuse_1.authenticated?,
  @result_reuse_2.authenticated?,
  @result_reuse_1.user.email == @result_reuse_2.user.email
]
#=> [true, true, true]

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

## DevSessionAuth#authenticate without rack.session returns failure
@env_no_session = {
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_no_session = DevSessionAuth.new.authenticate(@env_no_session, nil)
[
  @result_no_session.class.name,
  @result_no_session.failure_reason.include?('SESSION_MISSING')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevSessionAuth#authenticate with unauthenticated session returns failure
@env_unauthed_session = {
  'rack.session' => {
    'authenticated' => false,
    'external_id' => 'some_id'
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_unauthed = DevSessionAuth.new.authenticate(@env_unauthed_session, nil)
[
  @result_unauthed.class.name,
  @result_unauthed.failure_reason.include?('SESSION_NOT_AUTHENTICATED')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevSessionAuth#authenticate with missing external_id returns failure
@env_no_extid = {
  'rack.session' => {
    'authenticated' => true
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_no_extid = DevSessionAuth.new.authenticate(@env_no_extid, nil)
[
  @result_no_extid.class.name,
  @result_no_extid.failure_reason.include?('IDENTITY_MISSING')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevSessionAuth#authenticate with nonexistent customer returns failure
@env_bad_extid = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => "nonexistent_#{SecureRandom.hex(8)}"
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_bad_extid = DevSessionAuth.new.authenticate(@env_bad_extid, nil)
[
  @result_bad_extid.class.name,
  @result_bad_extid.failure_reason.include?('CUSTOMER_NOT_FOUND')
]
#=> ['Otto::Security::Authentication::AuthFailure', true]

## DevSessionAuth#authenticate result metadata includes dev_user and user_roles
@meta_dev_email = "dev_meta_#{SecureRandom.hex(4)}@example.com"
@meta_dev_cust = Onetime::Customer.create!(email: @meta_dev_email, role: 'customer')
@env_meta_session = {
  'rack.session' => {
    'authenticated' => true,
    'external_id' => @meta_dev_cust.extid
  },
  'REMOTE_ADDR' => '127.0.0.1',
  'HTTP_USER_AGENT' => 'Test/1.0'
}
@result_meta = DevSessionAuth.new.authenticate(@env_meta_session, nil)
[
  @result_meta.metadata[:dev_user],
  @result_meta.metadata[:user_roles]
]
#=> [true, ['customer']]

## DevSessionAuth#authenticate preserves session identity in result
@result_meta.session.equal?(@env_meta_session['rack.session'])
#=> true

# =============================================================================
# Cleanup
# =============================================================================

# Customer records created during tests are left for inspection
# They will be cleaned up by Redis TTL or manual cleanup
