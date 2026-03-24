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

# Cleanup: Customer records created during tests are left for inspection
# They will be cleaned up by Redis TTL or manual cleanup
