# try/integration/authentication/advanced_mode/env_toggles/mfa_enabled_try.rb
#
# frozen_string_literal: true

# ENV Toggle Test: ENABLE_MFA=true
#
# Tests that MFA features (otp, recovery_codes) are enabled when ENV is set.
#
# MFA features use the pattern: ENV['ENABLE_MFA'] == 'true'
# This means disabled by default, must explicitly enable.
#
# Routes provided by MFA features:
# - /auth/otp-setup (setup TOTP)
# - /auth/otp-auth (verify TOTP code)
# - /auth/otp-disable (disable TOTP)
# - /auth/recovery-codes (view/generate recovery codes)
# - /auth/recovery-auth (authenticate with recovery code)
#
# REQUIRES: Full mode with AUTHENTICATION_MODE=full and ENABLE_MFA=true

require_relative '../../../../support/test_helpers'
require_relative '../../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :full

# Ensure database URL is configured for full mode
if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
  puts 'SKIPPING: Full mode requires AUTH_DATABASE_URL'
  exit 0
end

# MUST enable MFA before boot
ENV['ENABLE_MFA'] = 'true'

# Setup
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/auth_config'
require 'onetime/middleware'
require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

require 'rack/test'
require 'json'

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def @test.json_response
  JSON.parse(last_response.body)
rescue JSON::ParserError
  {}
end

# -------------------------------------------------------------------
# MFA FEATURES ENABLED (ENABLE_MFA=true)
# -------------------------------------------------------------------

## Verify MFA ENV is set correctly
ENV['ENABLE_MFA']
#=> 'true'

## Verify MFA ENV pattern evaluates to enabled
ENV['ENABLE_MFA'] == 'true'
#=> true

## Auth app is mounted
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> true

## Auth::Config has OTP feature methods
Auth::Config.method_defined?(:otp_setup_route) || Auth::Config.private_method_defined?(:otp_setup_route)
#=> true

## Auth::Config has recovery codes feature methods
Auth::Config.method_defined?(:recovery_codes_route) || Auth::Config.private_method_defined?(:recovery_codes_route)
#=> true

## Auth::Config has two_factor_base feature methods
Auth::Config.method_defined?(:two_factor_authentication_setup?) || Auth::Config.private_method_defined?(:two_factor_authentication_setup?)
#=> true

## OTP setup route exists (may redirect or return auth error)
@test.get '/auth/otp-setup'
# 302 = redirect to login, 401/403 = auth error, 200 = success (unlikely without auth)
[200, 302, 401, 403].include?(@test.last_response.status)
#=> true

## OTP setup route response is valid
@test.get '/auth/otp-setup'
content_type = @test.last_response.headers['Content-Type']
is_json = content_type&.include?('application/json')
is_html = content_type&.include?('text/html')
is_redirect = @test.last_response.status == 302
is_json || is_html || is_redirect
#=> true

## OTP auth route exists
@test.post '/auth/otp-auth',
  { otp_code: '123456' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[200, 400, 401, 403, 422].include?(@test.last_response.status)
#=> true

## Recovery codes route exists (may redirect or return auth error)
@test.get '/auth/recovery-codes'
# 302 = redirect to login, 401/403 = auth error
[200, 302, 401, 403].include?(@test.last_response.status)
#=> true

## Recovery auth route exists
@test.post '/auth/recovery-auth',
  { recovery_code: 'abc12345' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[200, 400, 401, 403, 422].include?(@test.last_response.status)
#=> true

## Login still works with MFA enabled
@test.post '/auth/login',
  { login: 'test@example.com', password: 'wrongpassword' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[400, 401, 422].include?(@test.last_response.status)
#=> true
