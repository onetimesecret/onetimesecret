# try/integration/authentication/advanced_mode/env_toggles/webauthn_enabled_try.rb
#
# frozen_string_literal: true

# ENV Toggle Test: ENABLE_WEBAUTHN=true
#
# Tests that WebAuthn features (biometrics, security keys) are enabled when ENV is set.
#
# WebAuthn features use the pattern: ENV['ENABLE_WEBAUTHN'] == 'true'
# This means disabled by default, must explicitly enable.
#
# Routes provided by WebAuthn features:
# - /auth/webauthn-setup (register a new security key)
# - /auth/webauthn-auth (authenticate with security key)
# - /auth/webauthn-remove (remove a registered key)
# - /auth/webauthn-login (passwordless login with security key)
#
# REQUIRES: Full mode with AUTHENTICATION_MODE=full and ENABLE_WEBAUTHN=true

require_relative '../../../../support/test_helpers'
require_relative '../../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :full

# Ensure database URL is configured for full mode
if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
  puts 'SKIPPING: Full mode requires AUTH_DATABASE_URL'
  exit 0
end

# MUST enable WebAuthn before boot
ENV['ENABLE_WEBAUTHN'] = 'true'

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
# WEBAUTHN ENABLED (ENABLE_WEBAUTHN=true)
# -------------------------------------------------------------------

## Verify WebAuthn ENV is set correctly
ENV['ENABLE_WEBAUTHN']
#=> 'true'

## Verify WebAuthn ENV pattern evaluates to enabled
ENV['ENABLE_WEBAUTHN'] == 'true'
#=> true

## Auth app is mounted
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> true

## Auth::Config has webauthn feature methods
Auth::Config.method_defined?(:webauthn_setup_route) || Auth::Config.private_method_defined?(:webauthn_setup_route)
#=> true

## Auth::Config has webauthn_login feature methods
Auth::Config.method_defined?(:webauthn_login_route) || Auth::Config.private_method_defined?(:webauthn_login_route)
#=> true

## Auth::Config has webauthn_rp_name method
Auth::Config.method_defined?(:webauthn_rp_name) || Auth::Config.private_method_defined?(:webauthn_rp_name)
#=> true

## WebAuthn setup route exists (may redirect or return auth error)
@test.get '/auth/webauthn-setup'
# 302 = redirect to login, 401/403 = auth error, 200 = success (unlikely without auth)
[200, 302, 401, 403].include?(@test.last_response.status)
#=> true

## WebAuthn setup route response is valid
@test.get '/auth/webauthn-setup'
content_type = @test.last_response.headers['Content-Type']
is_json = content_type&.include?('application/json')
is_html = content_type&.include?('text/html')
is_redirect = @test.last_response.status == 302
is_json || is_html || is_redirect
#=> true

## WebAuthn auth route exists
@test.post '/auth/webauthn-auth',
  { webauthn_auth: 'invalid_data' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[200, 400, 401, 403, 422].include?(@test.last_response.status)
#=> true

## WebAuthn remove route exists (requires authentication)
@test.post '/auth/webauthn-remove',
  { webauthn_remove: 'credential_id' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[200, 400, 401, 403, 422].include?(@test.last_response.status)
#=> true

## WebAuthn login route exists (passwordless login)
@test.get '/auth/webauthn-login'
[200, 400, 401, 403].include?(@test.last_response.status)
#=> true

## Standard login still works with WebAuthn enabled
@test.post '/auth/login',
  { login: 'test@example.com', password: 'wrongpassword' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[400, 401, 422].include?(@test.last_response.status)
#=> true
