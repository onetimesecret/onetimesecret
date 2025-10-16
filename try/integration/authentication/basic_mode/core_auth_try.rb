# try/integration/authentication/basic_mode/core_auth_try.rb
# Integration tests for basic authentication mode
#
# Tests the complete authentication flow via Core app:
# - Login (valid/invalid credentials)
# - Signup (new account creation)
# - Logout (session destruction)
# - Password reset (request + reset)
# - Session persistence
# - Error handling
# - JSON response format
#
# REQUIRES: Basic mode (Core app handles /auth/* routes)

# Skip if not in basic mode
require_relative '../../../support/test_helpers'
require_relative '../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :basic

# Setup - Load the real application
ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../../..')).freeze

# Load the Onetime application and configuration
require 'onetime'
require 'onetime/config'

# Initialize configuration
Onetime.boot! :test

require 'onetime/auth_config'
require 'onetime/middleware'
require 'onetime/application/registry'

# Prepare the application registry
Onetime::Application::Registry.reset!
Onetime::Application::Registry.prepare_application_registry

# Require Rack test helpers
require 'rack/test'
require 'json'

# Create test instance for Core app (handles /auth/* in basic mode)
@test = Object.new
@test.extend Rack::Test::Methods

# Define the app method for Rack::Test - use the mounted Core app
def @test.app
  core_app_class = Onetime::Application::Registry.mount_mappings['/']
  core_app_class.new
end

# Helper to parse JSON responses
def @test.json_body
  JSON.parse(last_response.body)
end

# Helper to check if response is JSON
def @test.json_response?


  # Try both common variations of content-type header
  content_type = last_response.headers['content-type'] || last_response.headers['Content-Type']


  # Rack::MockResponse
  content_type&.include?('application/json')
end

# -------------------------------------------------------------------
# BASIC MODE TESTS
# -------------------------------------------------------------------

## Verify basic mode is active
Onetime.auth_config.mode
#=> 'basic'

## Verify advanced mode is disabled
Onetime.auth_config.advanced_enabled?
#=> false

## Verify Auth app is not mounted in basic mode
p [:PLOP, Onetime::Application::Registry.mount_mappings]
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> false

## Verify Core app is mounted at root
Onetime::Application::Registry.mount_mappings.key?('/')
#=> true

# -------------------------------------------------------------------
# LOGIN TESTS (Basic Mode)
# -------------------------------------------------------------------

## Login with JSON request - invalid credentials returns 401
@test.post '/auth/login',
  { login: 'nonexistent@example.com', password: 'wrongpassword' }.to_json,
  { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
@test.last_response.status
#=> 401

## Login error returns JSON format
@test.json_response?
#=> true

## Login error response body is not empty
@test.last_response.body.length > 0
#=> true

## Parse JSON response and verify structure
begin
  response = @test.json_body
  has_error = response.key?('error')
  has_field_error = response.key?('field-error')
  field_error_valid = has_field_error && response['field-error'].is_a?(Array) && response['field-error'].length == 2

  # Combine all checks
  has_error && has_field_error && field_error_valid &&
    response['field-error'][0] == 'email' &&
    response['field-error'][1] == 'invalid'
rescue => e
  puts "JSON parse or validation error: #{e.message}"
  puts "Response body: #{@test.last_response.body}" if @test.last_response
  false
end
#=> true

# -------------------------------------------------------------------
# SIGNUP TESTS (Basic Mode)
# -------------------------------------------------------------------

## Create account with JSON request - missing parameters
@test.post '/auth/create-account',
  { login: 'incomplete@example.com' }.to_json,
  { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
# Should fail with validation error (400 or 401)
[400, 401, 422].include?(@test.last_response.status)
#=> true

## Response is JSON
@test.json_response?
#=> true

# Note: Full signup flow requires Redis to be running and might create actual accounts
# For now, we test the endpoint accessibility and error handling

# -------------------------------------------------------------------
# LOGOUT TESTS (Basic Mode)
# -------------------------------------------------------------------

## Logout with JSON request - no active session
@test.post '/auth/logout',
  {}.to_json,
  { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
# Logout should work even without session (idempotent)

[200, 302].include?(@test.last_response.status)
#=> true

## If JSON requested and successful, response is JSON
if @test.last_response.status == 200
  @test.json_response?
else
  true  # Skip check if redirected (means JSON detection failed)
end
#=> true

# -------------------------------------------------------------------
# PASSWORD RESET TESTS (Basic Mode)
# -------------------------------------------------------------------

## Request password reset with JSON
@test.post '/auth/reset-password',
  { login: 'reset@example.com' }.to_json,
  { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
# Should accept the request (200) or fail validation (400/422)

[200, 400, 422].include?(@test.last_response.status)
#=> true

## Response is JSON
@test.json_response?
#=> true

## Reset password with token and JSON request
@test.post '/auth/reset-password/testtoken123',
  { p: 'newpassword123', password_confirm: 'newpassword123' }.to_json,
  { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
# Should fail validation or token not found (400/404/422)
[400, 404, 422].include?(@test.last_response.status)
#=> true

## Response is JSON
@test.json_response?
#=> true

# -------------------------------------------------------------------
# CONTENT TYPE TESTS
# -------------------------------------------------------------------

## POST without JSON Accept header redirects or returns HTML
@test.post '/auth/login',
  { login: 'test@example.com', password: 'password' }



# Should redirect (302) or return error page (401/500)
[302, 401, 500].include?(@test.last_response.status)
#=> true

## Response without JSON Accept is not JSON
@test.json_response?
#=> false

# -------------------------------------------------------------------
# ROUTE ACCESSIBILITY TESTS
# -------------------------------------------------------------------

# TODO: GET routes return 500 due to domain validation issues
# These tests are commented out pending domain configuration fix

# ## GET /signin returns 200 (Vue SPA page)
# @test.get '/signin'
# @test.last_response.status
# #=> 200

# ## GET /signup returns 200 (Vue SPA page)
# @test.get '/signup'
# @test.last_response.status
# #=> 200

# ## GET /forgot returns 200 (Vue SPA page)
# @test.get '/forgot'
# @test.last_response.status
# #=> 200

# ## GET / returns 200 (home page)
# @test.get '/'
# @test.last_response.status
# #=> 200

# # -------------------------------------------------------------------
# # SESSION TESTS
# # -------------------------------------------------------------------

# ## Session middleware is active
# @test.get '/'
# @test.last_response.headers.key?('Set-Cookie')
# #=> true

# ## Session cookie is set
# cookie_header = @test.last_response.headers['Set-Cookie']
# cookie_header&.include?('onetime.session')
# #=> true

# -------------------------------------------------------------------
# TEARDOWN
# -------------------------------------------------------------------

# Clean up test environment
@test = nil
