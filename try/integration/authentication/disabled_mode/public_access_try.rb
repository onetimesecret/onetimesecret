# try/integration/authentication/disabled_mode/public_access_try.rb
# Integration tests for disabled authentication mode
#
# Tests public access when authentication is completely disabled
# This mode is for users who want the simplest possible deployment
# without any authentication requirements
#
# REQUIRES: Disabled authentication mode

# Set authentication mode before skip check
ENV['AUTHENTICATION_MODE'] = 'disabled'

# Skip if not in disabled mode
require_relative '../../../support/test_helpers'
require_relative '../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :disabled

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
Onetime::Application::Registry.prepare_application_registry

# Require Rack test helpers
require 'rack/test'
require 'json'

# Create test instance
@test = Object.new
@test.extend Rack::Test::Methods

# Define the app method for Rack::Test
def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# -------------------------------------------------------------------
# DISABLED MODE TESTS
# -------------------------------------------------------------------

## Verify disabled mode is active
ENV['AUTHENTICATION_MODE']
#=> 'disabled'

## Auth app should NOT be mounted in disabled mode
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> false

## Core app is still mounted at root
Onetime::Application::Registry.mount_mappings.key?('/')
#=> true

# -------------------------------------------------------------------
# ROUTE BEHAVIOR IN DISABLED MODE
# -------------------------------------------------------------------

## Login endpoint does not exist
@test.post '/auth/login', { login: 'test@example.com', password: 'password' }
@test.last_response.status
#=> 404

## Signup endpoint does not exist
@test.post '/auth/create-account', { login: 'new@example.com', password: 'password' }
@test.last_response.status
#=> 404

## Logout endpoint does not exist
@test.post '/auth/logout'
@test.last_response.status
#=> 404

## Reset password endpoint does not exist
@test.post '/auth/reset-password', { login: 'test@example.com' }
@test.last_response.status
#=> 404

## No sign-in page
@test.get '/signin'
# Should return 404 or redirect to home
[302, 404].include?(@test.last_response.status)
#=> true

## No sign-up page
@test.get '/signup'
[302, 404].include?(@test.last_response.status)
#=> true

# -------------------------------------------------------------------
# PUBLIC ACCESS TESTS
# -------------------------------------------------------------------

## API status endpoint is accessible without auth
@test.get '/api/v2/status'
@test.last_response.status
#=> 200

## Can create secrets without authentication
@test.post '/api/v2/secret',
  { secret: 'test-secret', ttl: 300 }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should succeed or fail with validation, not auth error
[200, 201, 400, 422].include?(@test.last_response.status)
#=> true

## Protected endpoints are accessible (no protection)
@test.get '/dashboard'
# In disabled mode, normally protected endpoints should be accessible
# or return 404 if the route doesn't exist
[200, 302, 404].include?(@test.last_response.status)
#=> true

# -------------------------------------------------------------------
# SESSION BEHAVIOR
# -------------------------------------------------------------------

## Homepage is accessible without authentication
@test.get '/'
@test.last_response.status
#=> 200

## No session cookie is set in disabled mode
@test.get '/'
@test.last_response['Set-Cookie']
#=> nil

# -------------------------------------------------------------------
# TEARDOWN
# -------------------------------------------------------------------

# Clean up test environment
@test = nil
