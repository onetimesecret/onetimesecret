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

  # POST with JSON content type
  def post_json(path, params = {}, headers = {})
    post path,
      params.to_json,
      headers.merge(
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json'
      )
  end

  # GET with JSON accept header
  def get_json(path, params = {}, headers = {})
    get path,
      params,
      headers.merge('HTTP_ACCEPT' => 'application/json')
  end

  # DELETE with JSON accept header
  def delete_json(path, params = {}, headers = {})
    delete path,
      params,
      headers.merge('HTTP_ACCEPT' => 'application/json')
  end

  # PUT with JSON content type
  def put_json(path, params = {}, headers = {})
    put path,
      params.to_json,
      headers.merge(
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json'
      )
  end
end
