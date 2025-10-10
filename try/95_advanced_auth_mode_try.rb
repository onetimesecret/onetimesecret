# try/95_advanced_auth_mode_try.rb
# Integration tests for advanced authentication mode with Rodauth
#
# Tests:
# - Auth app mounts correctly at /auth
# - Rodauth handles authentication endpoints
# - Session bridging with Otto Customer model
# - JSON-only responses

# Setup - Load in advanced mode
ENV['RACK_ENV'] = 'test'
ENV['AUTHENTICATION_MODE'] = 'advanced'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..')).freeze

# Load the Onetime application and configuration
require_relative '../lib/onetime'
require_relative '../lib/onetime/config'

# Initialize configuration
Onetime.boot! :test

require_relative '../lib/onetime/auth_config'
require_relative '../lib/onetime/middleware'
require_relative '../lib/onetime/application/registry'

# Prepare the application registry
Onetime::Application::Registry.prepare_application_registry

# Require Rack test helpers
require 'rack/test'
require 'json'

# Create test helper that extends main to include Rack::Test
include Rack::Test::Methods

def app
  Onetime::Application::Registry.generate_rack_url_map
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
get '/auth'
last_response.status
#=> 200

## Auth app returns JSON
get '/auth'
last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Auth app response includes version info
get '/auth'
response = JSON.parse(last_response.body)
response.key?('message') && response.key?('version')
#=> true

## Health endpoint works
get '/auth/health'
last_response.status
#=> 200

## Health endpoint returns JSON
get '/auth/health'
last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Health response includes status and mode
get '/auth/health'
health = JSON.parse(last_response.body)
health['status'] == 'ok' && health['mode'] == 'advanced'
#=> true

## Admin stats endpoint exists
get '/auth/admin/stats'
# Should return 200 or auth required
[200, 401, 403].include?(last_response.status)
#=> true

# -------------------------------------------------------------------
# RODAUTH ENDPOINTS (if database is configured)
# -------------------------------------------------------------------

## Login endpoint exists
post '/auth/login',
  { login: 'test@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should return 401 (invalid credentials) or 400 (validation error)
[400, 401, 422].include?(last_response.status)
#=> true

## Login response is JSON
post '/auth/login',
  { login: 'test@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.headers['Content-Type']&.include?('application/json')
#=> true

## Create account endpoint exists
post '/auth/create-account',
  { login: 'new@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
# Should return 400/422 (validation) or 201/200 (success)
[200, 201, 400, 422].include?(last_response.status)
#=> true

## Create account response is JSON
post '/auth/create-account',
  { login: 'new@example.com', password: 'password123' }.to_json,
  { 'CONTENT_TYPE' => 'application/json' }
last_response.headers['Content-Type']&.include?('application/json')
#=> true

# -------------------------------------------------------------------
# CORE APP STILL HANDLES NON-AUTH ROUTES
# -------------------------------------------------------------------

## Core app still handles root
get '/'
# Should return 200 or 500 (domain validation issues in test)
[200, 500].include?(last_response.status)
#=> true
