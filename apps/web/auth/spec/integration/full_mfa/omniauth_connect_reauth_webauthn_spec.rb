# apps/web/auth/spec/integration/full_mfa/omniauth_connect_reauth_webauthn_spec.rb
#
# frozen_string_literal: true

# Tenant Connect re-authentication where the account's required second factor
# is a passkey (WebAuthn-as-MFA), and where the passkey is the primary
# re-authentication credential (#3849, #4411, #4414).
#
# This is the "password plus required MFA succeeds" row of the acceptance gate
# in docs/authentication/per-domain-sso.md for the WebAuthn factor; the OTP
# factor lives in omniauth_connect_reauth_mfa_spec.rb. The passkey is driven by
# the webauthn gem's WebAuthn::FakeClient against the SERVER's real challenges
# (support/webauthn_flow_helper.rb) — no verification is stubbed.
#
# What the RP-ID binding pins (lib/onetime/session/reauth_policy.rb):
#
#   - A passkey registered ON the tenant host (rp_id = tenant host,
#     surface_scope = that :custom surface) is offerable and verifiable on the
#     tenant host, both as the second factor after a password and as the
#     primary credential.
#   - A passkey registered for the PLATFORM RP ID (canonical host) is neither
#     offered nor accepted on a tenant host that declares no related origins:
#     no proof is recorded, so Connect initiation cannot mint an intent.

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require_relative '../../support/webauthn_flow_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'Tenant Connect re-authentication with a WebAuthn second factor (#3849)',
  :full_auth_mode, :oauth_flow, type: :integration do
  include MfaFlowHelper
  include WebauthnFlowHelper
  include OAuthFlowHelper
  include_context 'domains enabled'

  let(:reauth_key) { Onetime::RecentReauth::KEY }

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def initiate_sso_connect(host)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc', { connect: '1' }
  end

  # A tenant host with SSO configured, the account as an SSO-provisioned
  # member, and password sign-in enabled on the surface.
  def provision_tenant(host, account_id)
    tenant   = setup_oauth_test_domain(host)
    customer = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
    Onetime::OrganizationMembership.ensure_membership(
      tenant[:org], customer, role: 'member', domain_scope_id: tenant[:domain].objid, provisioning_source: 'sso',
    )
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
    )
    tenant
  end

  def tenant_surface(tenant)
    { 'kind' => 'custom', 'id' => tenant[:domain].identifier }
  end

  # Complete a Connect after a proof has been recorded: initiation mints the
  # intent (consuming the proof — it is single-use, so nothing may initiate
  # before this), the callback binds the asserted identity to the session
  # account and consumes the intent.
  def connect_and_bind(host, sid:, uid:, account_id:)
    initiate_sso_connect(host)
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
    expect(last_response.status).to eq(302)
    expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(true)
    expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc/callback'
    expect(last_response.status).to eq(302)
    expect(identities.where(provider: 'oidc', uid: uid).all)
      .to contain_exactly(hash_including(account_id: account_id))
    expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
  end

  context 'with the passkey registered on the tenant host' do
    it 'refuses password alone, then completes after password plus a passkey assertion' do
      host       = "passkey-connect-#{SecureRandom.hex(6)}.tenant.example.com"
      email      = unique_test_email('tenant-connect-passkey')
      uid        = "passkey-connect-sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      tenant     = provision_tenant(host, account_id)

      passkey = register_passkey(host, email: email)
      expect(auth_db[:account_webauthn_keys].where(account_id: account_id).select_map(:rp_id)).to eq([host])
      expect(JSON.parse(auth_db[:account_webauthn_keys].where(account_id: account_id).get(:surface_scope)))
        .to eq(tenant_surface(tenant))

      login_with_password_and_passkey(host, email: email, passkey: passkey)
      sid = current_sid
      # The login's own second-factor completion records a proof; the subject
      # here is the explicit re-authentication ceremony, so clear it.
      expect(Onetime::SessionSidecar.read(sid, reauth_key)).to include('methods' => %w[password webauthn])
      Onetime::SessionSidecar.delete(sid, reauth_key)

      clear_body_headers
      header 'Host', host
      header 'Accept', 'application/json'
      get '/auth/reauth-offer'
      expect(last_response.status).to eq(200)
      offer = json_body
      expect(offer['surface']).to eq(tenant_surface(tenant))
      expect(offer['methods']).to eq(%w[webauthn password])
      expect(offer['webauthn_credentials']).to eq([{ 'scope' => 'tenant', 'id' => tenant[:domain].identifier }])

      csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD)
      expect(last_response.status).to eq(200)
      password_only = json_body
      expect(password_only['mfa_required']).to eq(true)
      expect(password_only['mfa_methods']).to include('webauthn')
      expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

      setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
      begin
        initiate_sso_connect(host)
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include(Auth::Config::Hooks::OmniAuth.connect_reauth_redirect)
        expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)

        # Password + passkey: the operation issues a challenge bound to this
        # session, surface and RP ID, then verifies the signed assertion.
        csrf_json_post(
          '/auth/reauth',
          method: 'password',
          password: AuthTestConstants::TEST_PASSWORD,
          mfa_method: 'webauthn',
        )
        expect(last_response.status).to eq(200)
        challenge_body = json_body
        challenge      = challenge_body['webauthn_auth_challenge']
        expect(challenge).not_to be_nil
        expect(challenge_body['webauthn_auth_challenge_hmac']).not_to be_nil
        expect(challenge_body.dig('webauthn_auth', 'rpId')).to eq(host)
        expect(challenge_body.dig('webauthn_auth', 'allowCredentials').map { |c| c['id'] })
          .to eq([passkey.webauthn_id])
        expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

        csrf_json_post(
          '/auth/reauth',
          method: 'password',
          password: AuthTestConstants::TEST_PASSWORD,
          webauthn_auth: passkey.assert(challenge: challenge),
          webauthn_auth_challenge: challenge,
          webauthn_auth_challenge_hmac: challenge_body['webauthn_auth_challenge_hmac'],
        )
        expect(last_response.status).to eq(200), last_response.body
        expect(json_body).to eq('success' => 'Re-authentication complete')
        expect(Onetime::SessionSidecar.read(sid, reauth_key)).to include(
          'account_id' => account_id,
          'surface' => tenant_surface(tenant),
          'methods' => %w[password webauthn],
        )
        # The challenge is single-use: consumed by the verification.
        expect(Onetime::SessionSidecar.exists?(sid, Auth::Operations::Reauthenticate::CHALLENGE_FIELD)).to be(false)
        expect(auth_db[:account_webauthn_keys].where(account_id: account_id).get(:sign_count)).to be > 0

        connect_and_bind(host, sid: sid, uid: uid, account_id: account_id)
      ensure
        teardown_mock_auth
      end
    end

    it 'accepts the passkey as the primary re-authentication credential' do
      host       = "passkey-primary-#{SecureRandom.hex(6)}.tenant.example.com"
      email      = unique_test_email('tenant-connect-passkey-primary')
      uid        = "passkey-primary-sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      tenant     = provision_tenant(host, account_id)

      passkey = register_passkey(host, email: email)
      login_with_password_and_passkey(host, email: email, passkey: passkey)
      sid     = current_sid
      Onetime::SessionSidecar.delete(sid, reauth_key)

      setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
      begin
        header 'Host', host
        csrf_json_post('/auth/reauth', method: 'webauthn')
        expect(last_response.status).to eq(200)
        challenge_body = json_body
        challenge      = challenge_body['webauthn_auth_challenge']
        expect(challenge).not_to be_nil
        expect(challenge_body.dig('webauthn_auth', 'rpId')).to eq(host)
        expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

        # A challenge issued for the primary ceremony cannot be spent through
        # the second-factor path (pending['primary'] is part of the binding).
        csrf_json_post(
          '/auth/reauth',
          method: 'password',
          password: AuthTestConstants::TEST_PASSWORD,
          webauthn_auth: passkey.assert(challenge: challenge),
          webauthn_auth_challenge: challenge,
          webauthn_auth_challenge_hmac: challenge_body['webauthn_auth_challenge_hmac'],
        )
        expect(last_response.status).to eq(401)
        expect(json_body['error_code']).to eq('invalid_webauthn')
        expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

        # ...and that attempt consumed it, so a fresh challenge is required.
        csrf_json_post('/auth/reauth', method: 'webauthn')
        expect(last_response.status).to eq(200)
        challenge_body = json_body
        challenge      = challenge_body['webauthn_auth_challenge']

        csrf_json_post(
          '/auth/reauth',
          method: 'webauthn',
          webauthn_auth: passkey.assert(challenge: challenge),
          webauthn_auth_challenge: challenge,
          webauthn_auth_challenge_hmac: challenge_body['webauthn_auth_challenge_hmac'],
        )
        expect(last_response.status).to eq(200), last_response.body
        expect(Onetime::SessionSidecar.read(sid, reauth_key)).to include(
          'account_id' => account_id,
          'surface' => tenant_surface(tenant),
          'methods' => %w[webauthn],
        )

        connect_and_bind(host, sid: sid, uid: uid, account_id: account_id)
      ensure
        teardown_mock_auth
      end
    end
  end

  context 'with the only passkey registered for the platform RP ID' do
    it 'neither offers nor accepts the passkey on the tenant host, so no proof and no intent' do
      host       = "platform-passkey-#{SecureRandom.hex(6)}.tenant.example.com"
      email      = unique_test_email('tenant-connect-platform-passkey')
      uid        = "platform-passkey-sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      tenant     = provision_tenant(host, account_id)

      passkey       = register_passkey(canonical_host, email: email)
      expect(auth_db[:account_webauthn_keys].where(account_id: account_id).select_map(:rp_id)).to eq([canonical_host])
      expect(JSON.parse(auth_db[:account_webauthn_keys].where(account_id: account_id).get(:surface_scope)))
        .to eq(Onetime::SessionSurface::CANONICAL)
      signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(tenant[:domain].identifier)
      expect(signin_config.related_origin_members(current_domain: host)).to eq([])

      # The platform passkey cannot complete the login's second factor on the
      # tenant host either (Rodauth verifies against this host's RP ID), so
      # the account signs in with one of the auto-minted recovery codes.
      header 'Host', host
      csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
      expect(last_response.status).to eq(200)
      expect(json_body['mfa_required']).to eq(true)
      csrf_json_post('/auth/recovery-auth', 'recovery-code' => recovery_codes_for(account_id).fetch(0))
      expect(last_response.status).to eq(200), last_response.body
      sid = current_sid
      Onetime::SessionSidecar.delete(sid, reauth_key)

      clear_body_headers
      header 'Host', host
      header 'Accept', 'application/json'
      get '/auth/reauth-offer'
      expect(last_response.status).to eq(200)
      offer = json_body
      expect(offer['surface']).to eq(tenant_surface(tenant))
      expect(offer['methods']).to eq(%w[password])
      expect(offer['webauthn_credentials']).to eq([{ 'scope' => 'platform' }])
      expect(offer['related_origins']).to eq([])

      # Password alone: MFA is still required, and the passkey is not among
      # the completable second factors on this surface.
      csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD)
      expect(last_response.status).to eq(200)
      expect(json_body['mfa_required']).to eq(true)
      expect(json_body['mfa_methods']).not_to include('webauthn')
      expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

      # Asking for the passkey second factor: no eligible credential, no challenge.
      csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD, mfa_method: 'webauthn')
      expect(last_response.status).to eq(403)
      expect(json_body['error_code']).to eq('webauthn_unavailable')
      expect(Onetime::SessionSidecar.exists?(sid, Auth::Operations::Reauthenticate::CHALLENGE_FIELD)).to be(false)

      # Presenting an assertion the platform passkey signed for its own RP ID:
      # refused before any verification, and no proof.
      csrf_json_post(
        '/auth/reauth',
        method: 'password',
        password: AuthTestConstants::TEST_PASSWORD,
        webauthn_auth: passkey.assert(challenge: WebAuthn::Encoder.new.encode(SecureRandom.random_bytes(32))),
        webauthn_auth_challenge: 'unissued',
        webauthn_auth_challenge_hmac: 'unissued',
      )
      expect(last_response.status).to eq(403)
      expect(json_body['error_code']).to eq('webauthn_unavailable')

      # As a primary credential it is not even a valid method on this surface.
      csrf_json_post('/auth/reauth', method: 'webauthn')
      expect(last_response.status).to eq(400)
      expect(json_body['error_code']).to eq('invalid_method')
      expect(Onetime::SessionSidecar.exists?(sid, reauth_key)).to be(false)

      setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
      begin
        initiate_sso_connect(host)
        skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).to include(Auth::Config::Hooks::OmniAuth.connect_reauth_redirect)
        expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
      ensure
        teardown_mock_auth
      end
    end
  end
end
