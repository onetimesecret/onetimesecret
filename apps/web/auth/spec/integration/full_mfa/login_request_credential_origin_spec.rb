# apps/web/auth/spec/integration/full_mfa/login_request_credential_origin_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — recipient credential origin on the magic-link and
#            verification-resend requests (RISK-2026-08-14-M03)
# =============================================================================
#
# Verified tenant host, no site.host: the account-independent preflight
# passes, but a nonmember recipient has neither a tenant nor a canonical
# credential origin, so building its email link raises
# Auth::PublicHost::MissingAllowlistedOrigin. Unguarded, that 500 only an
# existing account can produce tells it apart from a missing login (whose
# request never builds a link). PublicBaseUrl's EmailAuthOrigin and
# VerifyAccountOrigin answer it like a missing account, before any key write,
# as ResetPasswordOrigin does for reset requests.
#
# Mirrors "reset request for a recipient without a credential origin" in
# integration/full/public_host_fallback_spec.rb, which cannot mount these
# routes: email_auth and verify_account boot only in the full-mfa lane.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/login_request_credential_origin_spec.rb
# =============================================================================

# Load-time, before the suite's first boot (see magic_link_session_rotation_spec.rb).
ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'
require_relative '../../../lib/public_host'

# rubocop:disable-next RSpec/SpecFilePathFormat -- the full-mfa lane owns this integration directory
RSpec.describe Auth::PublicHost, :aggregate_failures, :full_auth_mode, :shared_db_state, type: :integration do
  include_context 'domains enabled'
  include_context 'tenant fixtures'

  let(:delivered) { [] }
  let(:account_email) { unique_test_email('nonmember') }

  around do |example|
    saved_host = OT.conf['site']['host']
    begin
      OT.conf['site']['host'] = nil
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
      example.run
    ensure
      OT.conf['site']['host'] = saved_host
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
    end
  end

  before do
    Onetime::Application::MiddlewareStack.ip_privacy_security_config
    # The tenant opts into sign-in with magic links, and into sign-up (the
    # resend is a sign-up route), so the gates pass and the request reaches
    # the account lookup.
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: test_custom_domain.identifier,
      enabled: true,
      signin_enabled: true,
      email_auth_enabled: true,
    )
    Onetime::CustomDomain::SignupConfig.create!(
      domain_id: test_custom_domain.identifier,
      enabled: true,
      signup_enabled: true,
    )
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      delivered << email
      true
    end
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    header 'Host', tenant_domain
    header 'X-Forwarded-Proto', 'https'
  end

  after do
    Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
    Onetime::CustomDomain::SignupConfig.delete_for_domain!(test_custom_domain.identifier)
    clear_auth_database
  end

  def request_from_tenant(path, login)
    clear_cookies
    csrf_json_post(path, login: login)
    [last_response.status, JSON.parse(last_response.body)]
  end

  # A Rodauth instance for a direct (non-route) call on the tenant host.
  def direct_rodauth(account_id)
    env                           = Rack::MockRequest.env_for('https://unregistered.tenant-example.com/auth')
    env['onetime.display_domain'] = tenant_domain
    auth                          = Auth::Router.new(env).rodauth
    auth.instance_variable_set(:@account, auth_db[:accounts].where(id: account_id).first)
    auth
  end

  describe 'POST /auth/email-login-request' do
    let(:path) { '/auth/email-login-request' }
    let!(:account_id) { seed_existing_account(account_email) }

    it 'answers like a missing account without writing a key or sending email' do
      response = request_from_tenant(path, account_email)

      expect(response.first).to eq(200)
      expect(response).to eq(request_from_tenant(path, unique_test_email('missing-nonmember')))
      expect(auth_db[:account_email_auth_keys].where(id: account_id).count).to eq(0)
      expect(delivered).to be_empty
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:email_auth_request_no_credential_origin, hash_including(level: :error, account_id: account_id))
    end

    it 'does not update an existing key or its resend timestamp' do
      auth_db[:account_email_auth_keys].insert(
        id: account_id,
        key: 'existing-email-auth-key',
        deadline: Time.now + 600,
        email_last_sent: Time.now - 300,
      )
      original = auth_db[:account_email_auth_keys].where(id: account_id).first

      expect(request_from_tenant(path, account_email).first).to eq(200)
      expect(auth_db[:account_email_auth_keys].where(id: account_id).first).to eq(original)
      expect(delivered).to be_empty
    end

    # QA-B02: the account-INDEPENDENT preflight in hooks/email_login_request.rb
    # (Auth::PublicHost.required_base_url!), mirroring "gives the same refusal
    # for existing and missing accounts" in public_host_fallback_spec.rb. An
    # unverified tenant host with no site.host has no allowlisted origin at
    # all, so every login is refused before the account lookup, alike.
    it 'refuses existing and missing logins identically when the host has no allowlisted origin' do
      test_custom_domain.verified = false
      test_custom_domain.save
      header 'X-Request-Id', 'qa-b02-email-login-preflight'

      existing = request_from_tenant(path, account_email)

      expect(existing.first).to eq(500)
      expect(existing).to eq(request_from_tenant(path, unique_test_email('missing-preflight')))
      expect(auth_db[:account_email_auth_keys].where(id: account_id).count).to eq(0)
      expect(delivered).to be_empty
    end

    it 'still raises for direct key creation' do
      auth = direct_rodauth(account_id)
      auth.instance_variable_set(:@email_auth_key_value, 'proposed-email-auth-key')

      expect { auth.create_email_auth_key }.to raise_error(described_class::MissingAllowlistedOrigin)
      expect(auth_db[:account_email_auth_keys].where(id: account_id).count).to eq(0)
    end
  end

  describe 'POST /auth/verify-account-resend' do
    let(:path) { '/auth/verify-account-resend' }
    let!(:account_id) do
      id = seed_existing_account(account_email)
      auth_db[:accounts].where(id: id).update(status_id: AuthTestConstants::STATUS_UNVERIFIED)
      auth_db[:account_verification_keys].insert(
        id: id,
        key: 'existing-verify-key',
        requested_at: Time.now - 3600,
        email_last_sent: Time.now - 3600,
      )
      id
    end

    before do
      unless Auth::Config.features.include?(:verify_account)
        skip 'verify_account feature disabled at boot (AUTH_VERIFY_ACCOUNT_ENABLED)'
      end
    end

    it 'answers like a missing account without touching the key or sending email' do
      original = auth_db[:account_verification_keys].where(id: account_id).first
      response = request_from_tenant(path, account_email)

      expect(response.first).to eq(200)
      expect(response).to eq(request_from_tenant(path, unique_test_email('missing-nonmember')))
      expect(auth_db[:account_verification_keys].where(id: account_id).first).to eq(original)
      expect(delivered).to be_empty
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:verify_account_resend_no_credential_origin, hash_including(level: :error, account_id: account_id))
    end

    it 'still raises for a direct resend' do
      original = auth_db[:account_verification_keys].where(id: account_id).first

      expect { direct_rodauth(account_id).verify_account_email_resend }
        .to raise_error(described_class::MissingAllowlistedOrigin)
      expect(auth_db[:account_verification_keys].where(id: account_id).first).to eq(original)
    end
  end
end
