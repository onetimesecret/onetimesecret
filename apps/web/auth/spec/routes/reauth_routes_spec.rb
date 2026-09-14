# apps/web/auth/spec/routes/reauth_routes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Route module (non-integration)
# =============================================================================
#
# GET /auth/reauth-offer — the surface-aware re-authentication offer
# (#4414). apps/web/auth/routes/reauth.rb
#
# WHAT IT LOCKS IN:
#   - Unauthenticated requests are rejected (401).
#   - The response is EXACTLY { surface, methods, webauthn_credentials,
#     related_origins }; no verification material (public keys, sign
#     counters, credential ids) is present in the projection.
#   - Cache-Control: no-store is set — the offer is per-session state
#     and intermediaries must not cache it.
#   - The endpoint proxies straight to Auth::Operations::ReauthOffer;
#     the offer's logic is exercised in operations/reauth_offer_spec.rb,
#     not re-tested here.
#
# Runs in the spec:apps:web_auth lane (no Valkey, no app boot) via a mini
# Roda app hosting the production route module — see
# support/route_test_app_helper.rb.
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/route_test_app_helper'
require_relative '../../routes/reauth'

RSpec.describe 'Reauthentication routes (Auth::Routes::Reauth)' do
  include Rack::Test::Methods
  include RouteTestAppHelper

  let(:db) { create_test_database }
  let(:app) do
    build_route_test_app(
      db: db,
      route_module: Auth::Routes::Reauth,
      handler: :handle_reauth_routes,
    )
  end

  let(:account_id) { seed_route_test_account(db) }

  def login(id)
    post '/test-login', account_id: id
    expect(last_response.status).to eq(200)
  end

  before do
    # The endpoint delegates to ReauthOffer, which is exercised in its
    # own spec. Stub it here so this file is about wire framing only.
    stub_offer(
      surface: { kind: :canonical },
      methods: %w[password],
      webauthn_credentials: [],
      related_origins: [],
    )
  end

  def stub_offer(payload)
    frozen_payload = payload.merge(
      webauthn_credentials: payload[:webauthn_credentials].freeze,
    ).freeze
    allow_any_instance_of(Auth::Operations::ReauthOffer)
      .to receive(:call).and_return(frozen_payload)
  end

  describe 'authentication gate' do
    it 'returns 401 for an unauthenticated offer request' do
      get '/reauth-offer'

      expect(last_response.status).to eq(401)
      expect(json_body).to eq('error' => 'Authentication required')
    end

    it 'returns 401 for an unauthenticated completion request' do
      post '/reauth', JSON.generate(method: 'webauthn'), 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(401)
      expect(json_body).to eq('error' => 'Authentication required')
    end
  end

  describe 'wire framing' do
    before { login(account_id) }

    it 'returns { surface, methods, webauthn_credentials, related_origins } exactly' do
      get '/reauth-offer'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')
      expect(json_body.keys).to match_array(%w[surface methods webauthn_credentials related_origins])
    end

    it 'sets Cache-Control: no-store so intermediaries do not cache per-account state' do
      get '/reauth-offer'

      expect(last_response.headers['Cache-Control']).to eq('no-store')
      expect(last_response.headers['Pragma']).to eq('no-cache')
    end

    it 'serializes the canonical surface descriptor with string keys and values' do
      get '/reauth-offer'

      expect(json_body['surface']).to eq('kind' => 'canonical')
    end

    it 'serializes a nil surface as JSON null' do
      stub_offer(surface: nil, methods: [], webauthn_credentials: [], related_origins: [])
      get '/reauth-offer'

      expect(json_body['surface']).to be_nil
      expect(json_body['methods']).to eq([])
    end

    it 'serializes a :custom surface descriptor with id preserved' do
      stub_offer(
        surface: { kind: :custom, id: 'tenant-a' },
        methods: %w[password],
        webauthn_credentials: [],
        related_origins: [],
      )
      get '/reauth-offer'

      expect(json_body['surface']).to eq('kind' => 'custom', 'id' => 'tenant-a')
    end

    it 'serializes webauthn credentials as scope-only entries (no verification material)' do
      stub_offer(
        surface: { kind: :canonical },
        methods: %w[webauthn password],
        webauthn_credentials: [
          { scope: :platform },
          { scope: :tenant, id: 'tenant-a' },
        ],
        related_origins: [],
      )
      get '/reauth-offer'

      expect(json_body['webauthn_credentials']).to eq(
        [
          { 'scope' => 'platform' },
          { 'scope' => 'tenant', 'id' => 'tenant-a' },
        ],
      )
    end

    it 'serializes related_origins as exact browser origins' do
      stub_offer(
        surface: { kind: :custom, id: 'tenant-a' },
        methods: %w[webauthn password],
        webauthn_credentials: [{ scope: :platform }],
        related_origins: [
          { origin: 'https://example.com', surface: { kind: :canonical } },
          { origin: 'https://tenant.example:8443', surface: { kind: :custom, id: 'tenant-a' } },
        ],
      )
      get '/reauth-offer'

      expect(json_body['related_origins']).to eq(
        ['https://example.com', 'https://tenant.example:8443'],
      )
    end
  end

  describe 'POST /reauth' do
    before { login(account_id) }

    it 'rebuilds the offer and delegates completion for the current account' do
      result = Auth::Operations::Reauthenticate::Result.new(
        status: 200,
        body: { 'success' => 'Re-authentication complete' },
        password_verified: false,
      )
      operation = instance_double(Auth::Operations::Reauthenticate, call: result)
      allow(Auth::Operations::Reauthenticate).to receive(:new).and_return(operation)

      post '/reauth', JSON.generate(method: 'webauthn'), 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(json_body).to eq('success' => 'Re-authentication complete')
      expect(operation).to have_received(:call).with(
        account_id: account_id,
        offer: hash_including(methods: %w[password]),
        params: hash_including('method' => 'webauthn'),
      )
    end

    it 'sets no-store headers on completion responses' do
      result = Auth::Operations::Reauthenticate::Result.new(
        status: 400,
        body: { 'error' => 'Unsupported re-authentication method.', 'error_code' => 'invalid_method' },
        password_verified: false,
      )
      allow_any_instance_of(Auth::Operations::Reauthenticate).to receive(:call).and_return(result)

      post '/reauth', JSON.generate(method: 'bogus'), 'CONTENT_TYPE' => 'application/json'

      expect(last_response.headers['Cache-Control']).to eq('no-store')
      expect(last_response.headers['Pragma']).to eq('no-cache')
    end
  end

  describe 'offer construction' do
    before { login(account_id) }

    it 'tells the offer whether the WebAuthn feature is loaded (mini app: it is not)' do
      offer = { surface: { kind: :canonical }, methods: %w[password], webauthn_credentials: [], related_origins: [] }
      operation = instance_double(Auth::Operations::ReauthOffer, call: offer)
      allow(Auth::Operations::ReauthOffer).to receive(:new).and_return(operation)

      get '/reauth-offer'

      expect(last_response.status).to eq(200)
      expect(Auth::Operations::ReauthOffer).to have_received(:new).with(db, webauthn_loaded: false)
    end
  end

  describe 'failure handling' do
    before { login(account_id) }

    it 'returns 500 with a generic error body when the offer raises' do
      allow_any_instance_of(Auth::Operations::ReauthOffer).to receive(:call).and_raise('boom')

      get '/reauth-offer'

      expect(last_response.status).to eq(500)
      expect(json_body).to eq('error' => 'Failed to build reauth offer')
    end
  end
end
