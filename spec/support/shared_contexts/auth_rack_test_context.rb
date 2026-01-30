# spec/support/shared_contexts/auth_rack_test_context.rb
#
# frozen_string_literal: true

require 'rack/test'
require 'json'

# Provides Rack::Test helpers for auth integration specs.
#
# Usage:
#   RSpec.describe 'Auth Endpoints', :full_auth_mode do
#     include_context 'auth_rack_test'
#
#     it 'returns JSON response' do
#       get_json '/auth/account'
#       expect(json_response).to have_key('email')
#     end
#   end
#
# CSRF tokens are automatically included in POST/PUT/DELETE requests
# to auth routes. The token is cached and updated from response headers
# after each request to maintain session continuity.
#
RSpec.shared_context 'auth_rack_test' do
  include Rack::Test::Methods

  let(:app) do
    require 'onetime/application/registry'
    Onetime::Application::Registry.prepare_application_registry unless Onetime::Application::Registry.mount_mappings.any?
    Onetime::Application::Registry.generate_rack_url_map
  end

  # Parse JSON response body
  def json_response
    JSON.parse(last_response.body)
  end

  # Fetch a fresh CSRF token for the current session
  #
  # Always makes a GET request to retrieve the current session's token.
  # This is necessary because auth operations (create-account, login, logout)
  # can change the session and invalidate previously cached tokens.
  def fetch_csrf_token
    get '/auth', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.headers['X-CSRF-Token']
  end

  # POST with JSON content type and CSRF token
  #
  # Fetches a fresh token before each POST to ensure session continuity.
  def post_json(path, params = {}, headers = {})
    csrf_token = fetch_csrf_token

    post path,
      params.merge(shrimp: csrf_token).to_json,
      headers.merge(
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => csrf_token
      )
  end

  # GET with JSON accept header
  def get_json(path, params = {}, headers = {})
    get path,
      params,
      headers.merge('HTTP_ACCEPT' => 'application/json')
  end

  # DELETE with JSON accept header and CSRF token
  def delete_json(path, params = {}, headers = {})
    csrf_token = fetch_csrf_token

    delete path,
      params.merge(shrimp: csrf_token),
      headers.merge(
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => csrf_token
      )
  end

  # PUT with JSON content type and CSRF token
  def put_json(path, params = {}, headers = {})
    csrf_token = fetch_csrf_token

    put path,
      params.merge(shrimp: csrf_token).to_json,
      headers.merge(
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => csrf_token
      )
  end
end
