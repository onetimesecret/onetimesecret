# spec/integration/api/error_response_shape_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Regression guard for ADR-013 (4xx/5xx API Error Response Wire Format).
#
# Otto router fallbacks (`router.not_found` / `router.server_error`) configured
# in BaseJSONAPI (V3) and V2::Application MUST emit:
#
#   { "error": <user-facing message>, "error_type": <class name> }
#
# A future refactor of the Otto router config could silently drift back to the
# old `{ message, code }` shape; these specs fail loudly if that happens.
#
# Out of scope: V1. Frozen by policy; still emits `{ error: "Not Found" }` with
# no `error_type`. See V1::Application docstring and ADR-013 "Out of Scope".
#
# RUN:
#   bundle exec rspec spec/integration/api/error_response_shape_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../integration_spec_helper'
require 'json'

RSpec.describe 'API error response wire format (ADR-013)', type: :integration do
  include Rack::Test::Methods

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_get(path)
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get path
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    # Discover & require all apps/*/application.rb files so V1/V2/V3 mount
    # mappings are populated. Without this, Rack::URLMap has no entries for
    # /api/v3 etc. and returns a default text/plain 404, which would mask the
    # router-fallback wire shape we're trying to assert.
    Onetime::Application::Registry.prepare_application_registry
  end

  # ---------------------------------------------------------------------------
  # V3 (BaseJSONAPI subclass)
  # ---------------------------------------------------------------------------
  describe 'V3 router.not_found fallback (BaseJSONAPI)' do
    before { json_get '/api/v3/__no_such_route__' }

    it 'returns HTTP 404' do
      expect(last_response.status).to eq(404)
    end

    it 'returns application/json content type' do
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns ADR-013 shape: { error, error_type }' do
      body = JSON.parse(last_response.body)
      expect(body).to eq(
        'error'      => 'Not Found',
        'error_type' => 'NotFound',
      )
    end

    it 'does NOT include legacy `message` field' do
      body = JSON.parse(last_response.body)
      expect(body).not_to have_key('message')
    end

    it 'does NOT include legacy `code` field' do
      body = JSON.parse(last_response.body)
      expect(body).not_to have_key('code')
    end
  end

  # ---------------------------------------------------------------------------
  # V2 (direct OttoHooks consumer; configured in V2::Application#build_router)
  # ---------------------------------------------------------------------------
  describe 'V2 router.not_found fallback' do
    before { json_get '/api/v2/__no_such_route__' }

    it 'returns HTTP 404' do
      expect(last_response.status).to eq(404)
    end

    it 'returns application/json content type' do
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns ADR-013 shape: { error, error_type }' do
      body = JSON.parse(last_response.body)
      expect(body).to eq(
        'error'      => 'Not Found',
        'error_type' => 'NotFound',
      )
    end

    it 'does NOT include legacy `message` field' do
      body = JSON.parse(last_response.body)
      expect(body).not_to have_key('message')
    end

    it 'does NOT include legacy `code` field' do
      body = JSON.parse(last_response.body)
      expect(body).not_to have_key('code')
    end
  end

  # ---------------------------------------------------------------------------
  # router.server_error fallback
  #
  # Otto's server_error path only fires on uncaught exceptions inside route
  # dispatch. Triggering one from a request spec without invasive plumbing
  # (registering a test-only route that raises, or stubbing a controller to
  # bomb) is not worth the surface area: both `not_found` and `server_error`
  # bodies are configured in the same hash literal in BaseJSONAPI#build_router
  # and V2::Application#build_router, so the not_found tests above already
  # catch drift in that block.
  #
  # We do, however, assert the *configured* shape directly to guard against
  # someone editing only the server_error line without exercising it.
  # ---------------------------------------------------------------------------
  describe 'router.server_error fallback (config-level assertion)' do
    # Build router instances the same way the apps do, then inspect the
    # configured server_error tuple. This sidesteps the need to trigger a
    # real 500 over HTTP while still pinning the wire shape.
    def configured_server_error(app_class)
      app = app_class.new
      router = app.send(:build_router)
      router.server_error
    end

    it 'V3 (BaseJSONAPI) emits ADR-013 shape on 500' do
      status, headers, body = configured_server_error(V3::Application)
      expect(status).to eq(500)
      expect(headers['content-type']).to include('application/json')
      expect(JSON.parse(body.first)).to eq(
        'error'      => 'Internal Server Error',
        'error_type' => 'ServerError',
      )
    end

    it 'V2 emits ADR-013 shape on 500' do
      status, headers, body = configured_server_error(V2::Application)
      expect(status).to eq(500)
      expect(headers['content-type']).to include('application/json')
      expect(JSON.parse(body.first)).to eq(
        'error'      => 'Internal Server Error',
        'error_type' => 'ServerError',
      )
    end

    it 'V2 and V3 server_error bodies are byte-identical' do
      _, _, v2_body = configured_server_error(V2::Application)
      _, _, v3_body = configured_server_error(V3::Application)
      expect(v2_body.first).to eq(v3_body.first)
    end
  end
end
