# try/integration/authentication/full_mode/env_toggles/magic_links_enabled_try.rb
#
# frozen_string_literal: true

# ENV Toggle Test: ENABLE_MAGIC_LINKS=true
#
# Tests that passwordless/magic link features (email_auth) are enabled when ENV is set.
#
# Magic link features use the pattern: ENV['ENABLE_MAGIC_LINKS'] == 'true'
# This means disabled by default, must explicitly enable.
#
# Routes provided by magic link features:
# - /auth/email-login (verify magic link token)
# - /auth/email-login-request (request a magic link)
#
# REQUIRES: Full mode with AUTHENTICATION_MODE=full and ENABLE_MAGIC_LINKS=true

require_relative '../../../../support/test_helpers'
require_relative '../../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :full

# Ensure database URL is configured for full mode
if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
  raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
end

# MUST enable magic links before boot
ENV['ENABLE_MAGIC_LINKS'] = 'true'

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
# MAGIC LINKS ENABLED (ENABLE_MAGIC_LINKS=true)
# -------------------------------------------------------------------

## Verify magic links ENV is set correctly
ENV['ENABLE_MAGIC_LINKS']
#=> 'true'

## Verify magic links ENV pattern evaluates to enabled
ENV['ENABLE_MAGIC_LINKS'] == 'true'
#=> true

## Auth app is mounted
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> true

## Auth::Config has email_auth feature methods
Auth::Config.method_defined?(:email_auth_route) || Auth::Config.private_method_defined?(:email_auth_route)
#=> true

## Auth::Config has create_email_auth_key method
Auth::Config.method_defined?(:create_email_auth_key) || Auth::Config.private_method_defined?(:create_email_auth_key)
#=> true

## Email login request route exists (POST to request magic link)
@test.post '/auth/email-login-request',
  { login: 'test@example.com' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should return success (email sent) or validation error (account not found)
[200, 400, 401, 422].include?(@test.last_response.status)
#=> true

## Email login request route returns JSON
@test.post '/auth/email-login-request',
  { login: 'test@example.com' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
@test.last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Email login route exists (GET to verify token)
# Without a valid token, should return error
@test.get '/auth/email-login'
[200, 400, 401, 422].include?(@test.last_response.status)
#=> true

## Email login route with invalid token returns error
@test.get '/auth/email-login?key=invalid_token_12345'
[400, 401, 422].include?(@test.last_response.status)
#=> true

## Standard login still works with magic links enabled
@test.post '/auth/login',
  { login: 'test@example.com', password: 'wrongpassword' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[400, 401, 422].include?(@test.last_response.status)
#=> true
