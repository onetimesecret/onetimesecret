# apps/web/auth/spec/routes/webauthn_credentials_routes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Route module (non-integration)
# =============================================================================
#
# GET /auth/webauthn-credentials — list the current account's registered
# WebAuthn credentials (passkeys). apps/web/auth/routes/webauthn_credentials.rb
#
# WHAT IT LOCKS IN:
#   - Unauthenticated requests are rejected (401).
#   - The response shape is EXACTLY { credentials: [{ id, last_used_at }], count }
#     — the frontend is built against this contract. public_key and sign_count
#     never leave the server.
#   - Ordering is last_use DESC (most recently used first).
#   - Rows are scoped to the CURRENT account only (no cross-account leak).
#   - last_used_at is ISO8601 UTC.
#
# Runs in the spec:apps:web_auth lane (no Valkey, no app boot) via a mini Roda
# app hosting the production route module — see support/route_test_app_helper.rb.
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/route_test_app_helper'
require_relative '../../routes/webauthn_credentials'

RSpec.describe 'GET /webauthn-credentials (Auth::Routes::WebauthnCredentials)' do
  include Rack::Test::Methods
  include RouteTestAppHelper

  let(:db) { create_test_database }
  let(:app) do
    build_route_test_app(
      db: db,
      route_module: Auth::Routes::WebauthnCredentials,
      handler: :handle_webauthn_credentials_routes,
    )
  end

  let(:account_id) { seed_route_test_account(db) }
  let(:webauthn_keys) { db[:account_webauthn_keys] }

  def login(id)
    post '/test-login', account_id: id
    expect(last_response.status).to eq(200)
  end

  def seed_credential(account_id, webauthn_id:, last_use:, public_key: 'pk-material', sign_count: 3)
    webauthn_keys.insert(
      account_id: account_id,
      webauthn_id: webauthn_id,
      public_key: public_key,
      sign_count: sign_count,
      last_use: last_use,
    )
  end

  describe 'authentication gate' do
    it 'returns 401 when unauthenticated' do
      get '/webauthn-credentials'

      expect(last_response.status).to eq(401)
      expect(json_body).to eq('error' => 'Authentication required')
    end
  end

  describe 'empty list' do
    it 'returns an empty credentials array and count 0' do
      login(account_id)
      get '/webauthn-credentials'

      expect(last_response.status).to eq(200)
      expect(json_body).to eq('credentials' => [], 'count' => 0)
    end
  end

  describe 'listing and ordering' do
    it 'returns credentials ordered by last_use descending with exact shape' do
      older = Time.utc(2026, 1, 1, 10, 0, 0)
      newer = Time.utc(2026, 2, 2, 12, 30, 45)
      seed_credential(account_id, webauthn_id: 'cred-older', last_use: older)
      seed_credential(account_id, webauthn_id: 'cred-newer', last_use: newer)

      login(account_id)
      get '/webauthn-credentials'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      body = json_body
      expect(body.keys).to match_array(%w[credentials count])
      expect(body['count']).to eq(2)

      # Most recently used first.
      expect(body['credentials'].map { |c| c['id'] }).to eq(%w[cred-newer cred-older])

      # Exact per-row shape: id + last_used_at ONLY. public_key and sign_count
      # are verification material and must never appear.
      body['credentials'].each do |cred|
        expect(cred.keys).to match_array(%w[id last_used_at])
      end

      # ISO8601 UTC timestamps.
      expect(body['credentials'][0]['last_used_at']).to eq('2026-02-02T12:30:45Z')
      expect(body['credentials'][1]['last_used_at']).to eq('2026-01-01T10:00:00Z')
    end
  end

  describe 'account scoping' do
    it "does not return another account's credentials" do
      other_account_id = seed_route_test_account(db)
      seed_credential(account_id, webauthn_id: 'mine', last_use: Time.utc(2026, 3, 1))
      seed_credential(other_account_id, webauthn_id: 'theirs', last_use: Time.utc(2026, 3, 2))

      login(account_id)
      get '/webauthn-credentials'

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body['count']).to eq(1)
      expect(body['credentials'].map { |c| c['id'] }).to eq(%w[mine])
    end
  end

  describe 'feature-not-loaded visibility' do
    # The mini app deliberately does NOT enable the rodauth webauthn feature
    # (features default: base/login/logout), so this example doubles as the
    # AUTH_WEBAUTHN_ENABLED=false case: listing is management/visibility data
    # and stays available — unlike mfa-status's webauthn_enabled, which is
    # feature-gated because it steers the SPA toward the (unmounted)
    # /auth/webauthn-auth route. See the module comment in
    # routes/webauthn_credentials.rb.
    it 'still lists credentials when the rodauth webauthn feature is not loaded' do
      expect(app.rodauth.method_defined?(:webauthn_auth_route)).to be(false)

      seed_credential(account_id, webauthn_id: 'visible-anyway', last_use: Time.utc(2026, 4, 1))

      login(account_id)
      get '/webauthn-credentials'

      expect(last_response.status).to eq(200)
      expect(json_body['credentials'].map { |c| c['id'] }).to eq(%w[visible-anyway])
    end
  end

  describe 'route surface' do
    it 'does not expose a DELETE route (removal stays with Rodauth webauthn-remove)' do
      seed_credential(account_id, webauthn_id: 'keep-me', last_use: Time.utc(2026, 3, 1))

      login(account_id)
      delete '/webauthn-credentials/keep-me'

      expect(last_response.status).to eq(404)
      expect(webauthn_keys.where(account_id: account_id).count).to eq(1)
    end
  end
end
