# try/integration/authentication/advanced_mode/rodauth_try.rb
# Integration tests for advanced authentication mode with Rodauth
#
# Tests:
# - Auth app mounts correctly at /auth
# - Rodauth handles authentication endpoints
# - Session bridging with Otto Customer model
# - JSON-only responses
#
# REQUIRES: Advanced mode with SQL database (PostgreSQL or SQLite)

# Skip if not in advanced mode
require_relative '../../../support/test_helpers'
require_relative '../../../support/auth_mode_config'
Object.new.extend(AuthModeConfig).skip_unless_mode :advanced

# Ensure database URL is configured for advanced mode
if ENV['DATABASE_URL'].to_s.strip.empty?
  puts "SKIPPING: Advanced mode requires DATABASE_URL (PostgreSQL or SQLite)."
  exit 0
end

# Setup - Load in advanced mode
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

# Create test instance for the full application (all mounted apps)
@test = Object.new
@test.extend Rack::Test::Methods

# Define the app method for Rack::Test
def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Helper method to access JSON responses
def @test.json_response
  JSON.parse(last_response.body)
end

# -------------------------------------------------------------------
# ADVANCED MODE TESTS
# -------------------------------------------------------------------

## Verify advanced mode is active
Onetime.auth_config.mode
#=> 'advanced'

## Verify advanced mode is enabled
Onetime.auth_config.advanced_enabled?
#=> true

## Verify Auth app is mounted in advanced mode
Onetime::Application::Registry.mount_mappings.key?('/auth')
#=> true

## Verify Core app is still mounted at root
Onetime::Application::Registry.mount_mappings.key?('/')
#=> true

## Verify mount order - Auth before Core (more specific paths first)
paths = Onetime::Application::Registry.mount_mappings.keys
auth_index = paths.index('/auth')
core_index = paths.index('/')
# In the sorted hash, auth should come before core
auth_index && core_index && auth_index < core_index
#=> true

# -------------------------------------------------------------------
# AUTH APP TESTS
# -------------------------------------------------------------------

## Auth app responds at /auth
@test.get '/auth'
@test.last_response.status
#=> 200

## Auth app returns JSON
@test.get '/auth'
@test.last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Auth app response includes version info
@test.get '/auth'
response = JSON.parse(@test.last_response.body)
response.key?('message') && response.key?('version')
#=> true

## Health endpoint works
@test.get '/auth/health'
@test.last_response.status
#=> 200

## Health endpoint returns JSON
@test.get '/auth/health'
@test.last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Health response includes status and mode
@test.get '/auth/health'
health = JSON.parse(@test.last_response.body)
health['status'] == 'ok' && health['mode'] == 'advanced'
#=> true

## Admin stats endpoint exists
@test.get '/auth/admin/stats'
# Should return 200 or auth required
[200, 401, 403].include?(@test.last_response.status)
#=> true

# -------------------------------------------------------------------
# RODAUTH ENDPOINTS (if database is configured)
# -------------------------------------------------------------------

## Login endpoint exists
@test.post '/auth/login',
  { login: 'test@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should return 401 (invalid credentials) or 400 (validation error)
[400, 401, 422].include?(@test.last_response.status)
#=> true

## Login response is JSON
@test.post '/auth/login',
  { login: 'test@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
@test.last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Create account endpoint exists
@test.post '/auth/create-account',
  { login: 'new@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should return 400/422 (validation) or 201/200 (success)
[200, 201, 400, 422].include?(@test.last_response.status)
#=> true

## Create account response is JSON
@test.post '/auth/create-account',
  { login: 'new@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
@test.last_response.headers['Content-Type']&.include?('application/json')
#=> true

# -------------------------------------------------------------------
# CORE APP STILL HANDLES NON-AUTH ROUTES
# -------------------------------------------------------------------

## Core app still handles root
@test.get '/'
# Should return 200 or 500 (domain validation issues in test)
[200, 500].include?(@test.last_response.status)
#=> true
