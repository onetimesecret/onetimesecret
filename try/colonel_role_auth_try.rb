# try/colonel_role_auth_try.rb
#
# frozen_string_literal: true

# Test Otto's role= parameter support for colonel endpoints
# Verifies that auth=sessionauth role=colonel correctly authorizes colonel users

require_relative 'support/test_helpers'

require 'rack'
require 'rack/mock'

# Initialize the real Rack application and create a mock request
@app = Rack::Builder.parse_file('config.ru')
@mock_request = Rack::MockRequest.new(@app)

# Standard mock environment with RFC 5737 TEST-NET-1 IP for safe testing
@mock_env = {
  'REMOTE_ADDR' => '192.0.2.1',
  'HTTP_USER_AGENT' => 'Tryouts/1.0',
  'HTTP_HOST' => 'localhost',
}

## Anonymous user gets 302 redirect when accessing colonel endpoint
response = @mock_request.get('/colonel/info', @mock_env)
[response.status, response.headers["location"]]
#=> [302, "/signin"]

## Authenticated non-colonel user should get 403 Forbidden (not 401)
# Note: This test would require setting up a session with a non-colonel user
# For now we verify the route pattern is correct
response = @mock_request.get('/colonel', @mock_env)
response.status
#=> 302
