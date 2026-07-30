# spec/api/v2/basicauth_fallthrough_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Rack-level, real Otto strategy chain)
# =============================================================================
#
# Regression guard for the silent anonymous fallback
# (docs/security/audits/2026-07-29-api.md item 1).
#
# V2 secrets routes declare auth=basicauth,noauth and Otto's RouteAuthWrapper
# treats the list as OR logic. Before the fix, a request presenting INVALID
# Basic credentials (wrong key, unknown username, UUIDv7 owner_id used as
# username, wrong scheme) fell through to NoAuthStrategy and succeeded as
# anonymous — a silent 200 with null owner instead of a 401.
#
# Fixed behavior (fail closed):
#   1. Authorization header present + credentialed strategy rejects it -> 401
#   2. No Authorization header -> anonymous path unchanged
#   3. Valid credentials -> authenticated, unchanged
#
# Control case: GET /api/v2/receipt/recent is basicauth-ONLY (no noauth) and
# must keep 401ing on bad or missing credentials exactly as before.
#
# RUN:
#   bundle exec rspec spec/api/v2/basicauth_fallthrough_spec.rb
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../integration/integration_spec_helper'
require 'json'
require 'base64'
require 'securerandom'

RSpec.describe 'API v2 Basic auth anonymous fallthrough (fail closed)', type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Populate V1/V2/V3 mount mappings; without this Rack::URLMap has no
    # /api/v2 entry and every request 404s at the map level, masking the
    # auth behavior under test.
    Onetime::Application::Registry.prepare_application_registry
  end

  def basic_header(username, password)
    "Basic #{Base64.strict_encode64("#{username}:#{password}")}"
  end

  def json_get(path, authorization: nil)
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    header 'Authorization', authorization
    get path
  end

  # An identifier that does not resolve to a stored secret. Anonymous callers
  # get 404 (MissingSecret) on it — which is exactly the point: reaching the
  # logic layer at all proves the request was allowed through as anonymous.
  let(:unknown_secret_path) { "/api/v2/secret/nosuchsecret#{SecureRandom.hex(8)}" }

  # ---------------------------------------------------------------------------
  # 1. Invalid presented credentials on a basicauth,noauth route -> 401
  # ---------------------------------------------------------------------------
  describe 'GET /api/v2/secret/:identifier (auth=basicauth,noauth) with bad credentials' do
    it 'returns 401 for an unknown username (no anonymous fallthrough)' do
      json_get unknown_secret_path,
        authorization: basic_header("nobody_#{SecureRandom.uuid}@example.com", 'not_a_real_key')
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 for a UUIDv7 used as the Basic username (real-world trigger)' do
      # The incident that surfaced this: a customer used a UUIDv7 owner_id as
      # the Basic username. Only customer extid or email resolve, so auth
      # failed — and the request previously proceeded as anonymous with 200s.
      json_get unknown_secret_path,
        authorization: basic_header('0190b6f0-7d1a-7c3e-8f4a-2b9c1d0e5a6b', 'some_api_key')
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 for an unrecognized Authorization scheme (Bearer)' do
      json_get unknown_secret_path, authorization: 'Bearer some_token_here'
      expect(last_response.status).to eq(401)
    end

    it 'surfaces the credential failure in the JSON error body' do
      json_get unknown_secret_path,
        authorization: basic_header("nobody_#{SecureRandom.uuid}@example.com", 'not_a_real_key')
      body = JSON.parse(last_response.body)
      expect(body['message']).to include('CREDENTIALS_INVALID')
    end
  end

  # ---------------------------------------------------------------------------
  # 2. No Authorization header -> anonymous path unchanged
  # ---------------------------------------------------------------------------
  describe 'GET /api/v2/secret/:identifier without an Authorization header' do
    it 'reaches the logic layer as anonymous (404 for unknown secret, not 401)' do
      json_get unknown_secret_path
      expect(last_response.status).to eq(404)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Valid credentials -> authenticated, unchanged
  # ---------------------------------------------------------------------------
  describe 'GET /api/v2/secret/:identifier with valid credentials' do
    let(:test_email) { "fallthrough_spec_#{SecureRandom.uuid}@example.com" }
    let(:test_apikey) { SecureRandom.hex(20) }

    before do
      @test_customer = Onetime::Customer.new(email: test_email)
      @test_customer.save
      @test_customer.apitoken = test_apikey
      @test_customer.save
    end

    after do
      @test_customer&.delete!
    end

    it 'is not rejected by the auth layer (no 401)' do
      json_get unknown_secret_path, authorization: basic_header(test_email, test_apikey)
      expect(last_response.status).not_to eq(401)
    end
  end

  # ---------------------------------------------------------------------------
  # Control: basicauth-ONLY route keeps its pre-existing behavior
  # ---------------------------------------------------------------------------
  describe 'GET /api/v2/receipt/recent (auth=basicauth, no noauth)' do
    it 'returns 401 on invalid credentials (unchanged)' do
      json_get '/api/v2/receipt/recent',
        authorization: basic_header("nobody_#{SecureRandom.uuid}@example.com", 'not_a_real_key')
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 with no Authorization header (unchanged)' do
      json_get '/api/v2/receipt/recent'
      expect(last_response.status).to eq(401)
    end
  end
end
