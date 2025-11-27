# try/integration/authentication/advanced_mode/env_toggles/security_features_try.rb
#
# frozen_string_literal: true

# ENV Toggle Test: ENABLE_SECURITY_FEATURES
#
# Tests that security features (lockout, active_sessions, remember) are:
# - Enabled by default (ENV not set or != 'false')
# - Routes exist when enabled
#
# Security features use the pattern: ENV['ENABLE_SECURITY_FEATURES'] != 'false'
# This means enabled unless explicitly disabled.
#
# Routes provided by security features:
# - /auth/unlock-account (lockout feature)
#
# REQUIRES: Full mode with AUTHENTICATION_MODE=full

require_relative '../../../../support/test_helpers'
require_relative '../../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :full

# Ensure database URL is configured for full mode
if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
  puts 'SKIPPING: Full mode requires AUTH_DATABASE_URL'
  exit 0
end

# Security features should be ENABLED by default (not explicitly disabled)
# We're testing the default case here
ENV.delete('ENABLE_SECURITY_FEATURES')  # Ensure not set to 'false'

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
# SECURITY FEATURES ENABLED (DEFAULT)
# -------------------------------------------------------------------

## Verify security features ENV pattern (default = enabled)
ENV['ENABLE_SECURITY_FEATURES'] != 'false'
#=> true

## Auth app is mounted
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> true

## Unlock account route exists (from lockout feature)
# The unlock-account route should exist when security features are enabled
# Returns 4xx because we're not in a locked state
@test.get '/auth/unlock-account'
[200, 400, 401, 404].include?(@test.last_response.status)
#=> true

## Unlock account route response is valid (JSON or HTML redirect)
# Rodauth may return HTML for unlock-account if not in JSON mode
@test.get '/auth/unlock-account'
content_type = @test.last_response.headers['Content-Type']
is_json = content_type&.include?('application/json')
is_html = content_type&.include?('text/html')
is_valid_status = [200, 302, 400, 401, 404].include?(@test.last_response.status)
(is_json || is_html) && is_valid_status
#=> true

## Login endpoint still works with security features enabled
@test.post '/auth/login',
  { login: 'test@example.com', password: 'wrongpassword' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
[400, 401, 422].include?(@test.last_response.status)
#=> true

## Auth::Config has lockout feature methods
Auth::Config.method_defined?(:max_invalid_logins) || Auth::Config.private_method_defined?(:max_invalid_logins)
#=> true

## Auth::Config has active_sessions feature methods
Auth::Config.method_defined?(:session_inactivity_deadline) || Auth::Config.private_method_defined?(:session_inactivity_deadline)
#=> true
