# apps/web/auth/spec/integration/full/recent_reauth_clear_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue #4420 — Onetime::RecentReauth.clear has four callers, one per event
# that invalidates a recent full re-authentication proof (#4410):
#
#   1. logout                (config/hooks/logout.rb, before_logout)
#   2. password change       (config/hooks/account.rb, after_change_password)
#   3. WebAuthn key removal  (config/hooks/webauthn.rb, after_webauthn_remove)
#   4. successful Connect    (config/hooks/omniauth_connect.rb,
#                             bind_omniauth_connect_identity)
#
# One example per site: seed a proof under the session's sidecar key, drive
# the event through the real Rodauth route, assert the key is gone.
#
# Sites 1 and 2 are ALSO covered by session destruction (logout destroys the
# session; change_password :renew-rotates the sid and delete_session purges
# every sidecar key for the old sid). Those examples therefore additionally
# spy on RecentReauth.clear so the explicit call — the guarantee that holds
# when the best-effort purge does not — is what is proven, not the purge.
#
# Site 3 runs against an inline Rodauth app: spec/auth.test.yaml pins
# full.features.webauthn false, so the booted app has no webauthn routes. The
# inline app mounts the PRODUCTION hook module (Auth::Config::Hooks::WebAuthn)
# behind the PRODUCTION session middleware (Onetime::Session), because the
# proof is keyed on the Rack session id and Roda's own sessions plugin has no
# id at all.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true \
#     bundle exec rspec apps/web/auth/spec/integration/full/recent_reauth_clear_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'bcrypt'
require 'webauthn/fake_client'

RSpec.describe 'RecentReauth.clear call sites (#4420)', :full_auth_mode, type: :integration do
  include Rack::Test::Methods
  include_context 'domains enabled'

  let(:identities) { auth_db[:account_identities] }

  # The plain (64-hex) session id behind the current Rack::Test cookie jar —
  # the sid the sidecar keys are derived from.
  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def proof_live?(sid)
    Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)
  end

  # A fresh canonical-surface password proof for `account_id`, written the
  # same way the login hooks write one.
  def seed_reauth_proof(sid, account_id, surface: Onetime::SessionSurface::CANONICAL, methods: %w[password])
    Onetime::SessionSidecar.write(
      sid,
      Onetime::RecentReauth::KEY,
      { 'account_id' => Integer(account_id), 'at' => Time.now.utc.to_i, 'surface' => surface, 'methods' => methods },
    )
    expect(proof_live?(sid)).to be(true), 'Precondition failed: proof was not seeded'
  end

  # Record the sid of every session RecentReauth.clear is handed, AT CALL TIME.
  # Both events re-key the session before the example can look, so the session
  # object's id is already the rotated one by the time a have_received matcher
  # would inspect it.
  def spy_on_clear
    cleared = []
    allow(Onetime::RecentReauth).to receive(:clear).and_wrap_original do |original, session|
      cleared << session&.id&.public_id
      original.call(session)
    end
    cleared
  end

  describe 'logout (before_logout)' do
    it 'clears the proof explicitly before the session is destroyed' do
      email = unique_test_email('reauth-clear-logout')
      seed_account_with_password(email)
      csrf_login(email)
      sid = current_sid
      # The password login recorded a proof; replace it with a known one.
      seed_reauth_proof(sid, auth_db[:accounts].where(email: email).get(:id))

      cleared = spy_on_clear

      csrf_json_post('/auth/logout')
      expect(last_response.status).to be_between(200, 302),
        "Logout failed (#{last_response.status}): #{last_response.body}"

      expect(cleared).to include(sid)
      expect(proof_live?(sid)).to be(false)
    end
  end

  describe 'password change (after_change_password)' do
    it 'clears the proof on the pre-rotation sid and leaves none on the rotated one' do
      email      = unique_test_email('reauth-clear-change')
      account_id = seed_account_with_password(email)
      csrf_login(email)
      sid        = current_sid
      seed_reauth_proof(sid, account_id)

      cleared = spy_on_clear
      # Keep the example off the broker: the sweep enqueue is a post-commit
      # side effect of the hook, not the subject here.
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_session_revocation_sweep).and_return(true)

      csrf_json_post(
        '/auth/change-password',
        password: AuthTestConstants::TEST_PASSWORD,
        'new-password': "Rotated-#{SecureRandom.hex(8)}",
      )
      expect(last_response.status).to eq(200),
        "Password change failed (#{last_response.status}): #{last_response.body}"

      expect(cleared).to include(sid)
      expect(proof_live?(sid)).to be(false)

      rotated_sid = current_sid
      expect(rotated_sid).not_to eq(sid), 'Precondition failed: change_password did not rotate the sid'
      expect(proof_live?(rotated_sid)).to be(false)
    end
  end

  describe 'WebAuthn credential removal (after_webauthn_remove)' do
    let(:db) { create_test_database }
    let(:password) { 'correct horse battery staple' }
    let(:email) { "reauth-clear-webauthn-#{SecureRandom.hex(6)}@integration-test.example.com" }

    let(:account_id) do
      id = db[:accounts].insert(email: email, status_id: AuthTestConstants::STATUS_VERIFIED)
      db[:account_password_hashes].insert(id: id, password_hash: BCrypt::Password.create(password))
      id
    end

    # Production session middleware in front of a Rodauth app that enables the
    # webauthn feature and mounts the production WebAuthn hook module.
    let(:app) do
      app_db = db

      Class.new(Roda) do
        # key/expire_after are passed explicitly, as middleware_stack.rb does:
        # Onetime::Session's `unless defined?(DEFAULT_OPTIONS)` guard sees the
        # constant inherited from Rack::Session::Abstract::Persisted, so its
        # own defaults (key 'onetime.session', 24h) never install.
        use Onetime::Session, secret: SecureRandom.hex(64), secure: false, key: 'onetime.session', expire_after: 86_400
        plugin :json
        plugin :json_parser
        plugin :halt

        plugin :rodauth do
          db app_db
          enable :base, :json, :login, :logout, :webauthn
          only_json? true
          login_column :email
          hmac_secret SecureRandom.hex(32)
          webauthn_remove_route 'webauthn-remove'

          Auth::Config::Hooks::WebAuthn.configure(self)
        end

        route do |r|
          r.rodauth

          # Test seam: mark the session as having completed WebAuthn as the
          # second factor. Once a key row exists Rodauth requires the session
          # to be two-factor authenticated before it may remove a credential
          # (exactly the state a real user is in when they remove a passkey);
          # the JSON webauthn-auth ceremony cannot be driven without a real
          # authenticator, so the session is stamped the way Rodauth's own
          # webauthn_auth route stamps it (two_factor_update_session).
          r.post 'two-factor-complete' do
            rodauth.send(:two_factor_update_session, 'webauthn')
            {}
          end
        end
      end
    end

    def post_json(path, body)
      post(path, body.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json')
      last_response
    end

    # Drives a REAL registration through Rodauth's webauthn-setup route with
    # the webauthn gem's FakeClient, so the production after_webauthn_setup
    # body runs against a real credential. At HEAD before the fix the hook
    # called `param(webauthn_setup_webauthn_id_param)` — an accessor rodauth
    # 2.45 does not define — and every registration died with NameError
    # inside the setup transaction.
    it 'registers a credential through webauthn-setup and runs after_webauthn_setup' do
      db.alter_table(:account_webauthn_keys) do
        add_column :surface_scope, String
        add_column :rp_id, String
      end
      logger = instance_spy(SemanticLogger::Logger, 'Auth::WebAuthn logger')
      allow(Onetime).to receive(:get_logger).and_call_original
      allow(Onetime).to receive(:get_logger).with('Auth::WebAuthn').and_return(logger)

      account_id
      post_json('/login', login: email, password: password)
      expect(last_response.status).to eq(200), "Login failed (#{last_response.status}): #{last_response.body}"

      # Step 1 of Rodauth's two-step JSON setup: a POST without the attestation
      # returns the creation options + HMAC'd challenge with a 422.
      post_json('/webauthn-setup', password: password)
      expect(last_response.status).to eq(422), "Setup options failed (#{last_response.status}): #{last_response.body}"
      options    = JSON.parse(last_response.body)
      expect(options).to include('webauthn_setup_challenge', 'webauthn_setup_challenge_hmac')
      client     = WebAuthn::FakeClient.new('http://example.org')
      credential = client.create(challenge: options['webauthn_setup_challenge'])

      post_json(
        '/webauthn-setup',
        webauthn_setup: JSON.generate(credential),
        webauthn_setup_challenge: options['webauthn_setup_challenge'],
        webauthn_setup_challenge_hmac: options['webauthn_setup_challenge_hmac'],
        password: password,
      )
      expect(last_response.status).to eq(200),
        "WebAuthn setup failed (#{last_response.status}): #{last_response.body}"

      row = db[:account_webauthn_keys].where(account_id: account_id).first
      expect(row).to include(webauthn_id: credential['id'], rp_id: 'example.org')
      expect(logger).to have_received(:info)
        .with('WebAuthn credential registered', hash_including(account_id: account_id, webauthn_id: credential['id']))
      expect(logger).not_to have_received(:error)
    end

    it 'clears the proof once the credential row is deleted' do
      account_id
      post_json('/login', login: email, password: password)
      expect(last_response.status).to eq(200), "Login failed (#{last_response.status}): #{last_response.body}"
      sid = current_sid
      expect(sid).to match(/\A\h{64}\z/), 'Precondition failed: no Onetime::Session cookie'

      # Seeded AFTER login so the session was established without a pending
      # second factor; the remove route only needs the row to exist now.
      webauthn_id = "cred-#{SecureRandom.hex(8)}"
      db[:account_webauthn_user_ids].insert(id: account_id, webauthn_id: SecureRandom.hex(16))
      db[:account_webauthn_keys].insert(
        account_id: account_id, webauthn_id: webauthn_id, public_key: 'pk', sign_count: 0,
      )
      post_json('/two-factor-complete', {})
      expect(last_response.status).to eq(200)
      seed_reauth_proof(sid, account_id, methods: %w[password webauthn])

      post_json('/webauthn-remove', webauthn_remove: webauthn_id, password: password)
      expect(last_response.status).to eq(200),
        "WebAuthn removal failed (#{last_response.status}): #{last_response.body}"
      expect(db[:account_webauthn_keys].where(account_id: account_id).count).to eq(0)

      expect(proof_live?(sid)).to be(false)
    end
  end

  describe 'successful identity bind (bind_omniauth_connect_identity)' do
    before { enable_platform_fallback }

    def initiate_sso_connect(provider: :oidc)
      clear_body_headers
      post "/auth/sso/#{provider}", { connect: '1' }
      last_response.status
    end

    it 'clears a proof recorded between initiation and the callback' do
      email      = unique_test_email('reauth-clear-bind')
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      csrf_login(email)

      setup_mock_auth(email: email, uid: uid)
      begin
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if initiate_sso_connect == 404

        sid = current_sid
        expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(true),
          'Connect initiation must set the intent sidecar key'
        # Initiation consumed the login's proof; a NEW one recorded during the
        # IdP round trip must not survive the bind.
        expect(proof_live?(sid)).to be(false)
        seed_reauth_proof(sid, account_id)

        clear_body_headers
        post '/auth/sso/oidc/callback'
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404

        expect(last_response.status).to eq(302),
          "Expected a post-bind redirect, got #{last_response.status}: #{last_response.body}"
        expect(last_response.location.to_s).not_to include('auth_error='),
          "Bind must not refuse. Location: #{last_response.location.inspect}"
        expect(identities.where(provider: 'oidc', uid: uid).all)
          .to contain_exactly(hash_including(account_id: account_id))

        expect(proof_live?(sid)).to be(false)
      ensure
        teardown_mock_auth
      end
    end
  end
end
