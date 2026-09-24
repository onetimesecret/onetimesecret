# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'Tenant Connect re-authentication with MFA (#4411/#3849)',
  :full_auth_mode, :oauth_flow, type: :integration do
  include MfaFlowHelper
  include OAuthFlowHelper
  include_context 'domains enabled'

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def initiate_sso_connect(host)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc', { connect: '1' }
  end

  it 'refuses password alone when MFA is required, then completes after password plus OTP' do
    host       = "mfa-connect-#{SecureRandom.hex(6)}.tenant.example.com"
    email      = unique_test_email('tenant-connect-mfa')
    uid        = "mfa-connect-sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    tenant     = setup_oauth_test_domain(host)
    customer   = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
    Onetime::OrganizationMembership.ensure_membership(
      tenant[:org], customer, role: 'member', domain_scope_id: tenant[:domain].objid, provisioning_source: 'sso',
    )
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
    )

    header 'Host', host
    secret, _recovery_codes = provision_totp(email)
    header 'Host', host
    allow_immediate_otp_reuse!(account_id)
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200)
    expect(json_body['mfa_required']).to eq(true)
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
    expect(last_response.status).to eq(200)

    sid = current_sid
    Onetime::SessionSidecar.delete(sid, Onetime::RecentReauth::KEY)

    clear_body_headers
    header 'Host', host
    header 'Accept', 'application/json'
    get '/auth/reauth-offer'
    expect(last_response.status).to eq(200)
    expect(json_body['surface']).to eq('kind' => 'custom', 'id' => tenant[:domain].identifier)
    expect(json_body['methods']).to include('password')

    csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200)
    password_only = json_body
    expect(password_only['mfa_required']).to eq(true)
    expect(password_only['mfa_methods']).to include('otp')
    expect(Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)).to be(false)

    setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
    begin
      initiate_sso_connect(host)
      skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).to include(Auth::Config::Hooks::OmniAuth.connect_reauth_redirect)
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)

      allow_immediate_otp_reuse!(account_id)
      csrf_json_post(
        '/auth/reauth',
        method: 'password',
        password: AuthTestConstants::TEST_PASSWORD,
        otp_code: ROTP::TOTP.new(secret).now,
      )
      expect(last_response.status).to eq(200)
      expect(Onetime::SessionSidecar.read(sid, Onetime::RecentReauth::KEY)).to include(
        'account_id' => account_id,
        'surface' => { 'kind' => 'custom', 'id' => tenant[:domain].identifier },
        'methods' => %w[password totp],
      )

      initiate_sso_connect(host)
      expect(last_response.status).to eq(302)
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(true)
      expect(Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)).to be(false)

      clear_body_headers
      header 'Host', host
      post '/auth/sso/oidc/callback'
      expect(last_response.status).to eq(302)
      expect(identities.where(provider: 'oidc', uid: uid).all)
        .to contain_exactly(hash_including(account_id: account_id))
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
    ensure
      teardown_mock_auth
    end
  end
end
