# apps/web/auth/spec/integration/full_mfa/webauthn_verify_account_recovery_codes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, MFA lane)
# =============================================================================
#
# Passkey verification with MFA on adds the recovery codes to the account
# being verified.
#
# With AUTH_MFA_ENABLED, config/features/mfa.rb loads recovery_codes with
# auto_add_recovery_codes? true, so Rodauth adds an account's codes whenever a
# credential is added (recovery_codes.rb add_webauthn_credential ->
# auto_add_missing_recovery_codes). With AUTH_WEBAUTHN_VERIFY_ACCOUNT,
# POST /auth/verify-account adds the passkey inside the verify transaction
# (webauthn_verify_account.rb before_verify_account), before the account is
# verified and before the autologin. Released rodauth (2.45.0 through 2.48.0)
# keys both the recovery-code lookup and the insert on session_value
# (recovery_codes.rb recovery_codes_ds and add_recovery_code), so:
#
#   - from a browser with no signed-in session the insert writes a NULL id
#     ("NOT NULL constraint failed: account_recovery_codes.id"), the verify
#     transaction rolls back, the verification answers 500 and the account
#     stays unverified;
#   - from a browser still signed in to another account in a session the app has
#     not marked authenticated (which already_logged_in in config/base.rb lets
#     through to this route), the codes are counted, and topped up, on that
#     other account, and the account being verified gets none.
#
# The Gemfile pins rodauth to the onetimesecret fork, whose recovery_codes
# uses account_id_or_session_value (onetimesecret/rodauth#3): the account
# loaded from the verify key wins over the session. This file is the guard
# for that pin. Moving back to a released rodauth without that change fails
# both examples.
#
# This file lives in full_mfa/ because it needs the process to boot with MFA:
# Auth::Config is configured once per process, and the shared full lanes do
# not guarantee that boot (in full-pg-agnostic the guard in the before block
# fails). The full-mfa lane boots MFA, WebAuthn and verify_account on, while
# MockAuthConfig (spec/support/auth_mode_helpers.rb) keeps
# webauthn_verify_account off. So, as in
# verify_account_autologin_session_rotation_spec.rb, the examples run against
# a router subclass: it inherits the booted Auth class (MFA and its
# recovery-code settings as shipped) and applies the verify-account and
# WebAuthn modules in config.rb's order, with the three flags stubbed on. That
# is the configuration of an install with AUTH_VERIFY_ACCOUNT_ENABLED,
# AUTH_MFA_ENABLED, AUTH_WEBAUTHN_ENABLED and AUTH_WEBAUTHN_VERIFY_ACCOUNT on.
#
# The verification is Rodauth's own two-phase JSON ceremony: the first POST
# with the key answers 422 with the credential-creation options, the second
# sends the attestation the webauthn gem's FakeClient signs for them.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/webauthn_verify_account_recovery_codes_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/domains_enabled_context'
require 'rack/test'
require 'cgi'
require 'webauthn'
require 'webauthn/fake_client'

RSpec.describe 'Passkey verify-account with recovery codes auto-added', :full_auth_mode, type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  # The passkey is created for the installed canonical host, the RP ID the
  # server offers there (Auth::PublicHost.webauthn_host).
  include_context 'domains enabled'

  let(:password) { 'WebauthnRecovery-Password123!' }
  let(:codes_limit) { Auth::Config::Features::MFA::RECOVERY_CODES_LIMIT }

  before do
    allow(Onetime.auth_config).to receive_messages(
      verify_account_enabled?: true,
      webauthn_enabled?: true,
      webauthn_verify_account_enabled?: true,
    )

    router = Class.new(Auth::Router)
    router.plugin :rodauth do
      Auth::Config::Features::AccountManagement.configure(self)
      Auth::Config::Email::VerifyAccount.configure(self)
      Auth::Config::Hooks::Account.configure(self)
      Auth::Config::Features::WebAuthn.configure(self)
      Auth::Config::Hooks::WebAuthn.configure(self)
    end
    allow_any_instance_of(Auth::Application).to receive(:build_router).and_return(router) # rubocop:disable RSpec/AnyInstance

    # This file covers the shipped MFA settings; a lane that boots without
    # them cannot run it (harness breakage, so a failure rather than a skip).
    auth_class = router.rodauth
    unless auth_class.features.include?(:recovery_codes) && auth_class.allocate.auto_add_recovery_codes?
      raise 'this file covers recovery_codes with auto_add_recovery_codes? on; the lane booted without MFA'
    end

    @verify_app = build_rack_app
    # Building the middleware reinitializes DomainStrategy; keep the shared
    # context's classification of the canonical host.
    Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])

    # The delivery seam: the rendered verification emails, as the publisher
    # would receive them.
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end

    @emails = []
  end

  after do
    @emails.each do |email|
      Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))&.destroy!
    rescue StandardError
      nil
    end
  end

  def app
    @verify_app || super
  end

  def recovery_codes_for(account_id)
    auth_db[:account_recovery_codes].where(id: account_id).select_order_map(:code)
  end

  def webauthn_key_count(account_id)
    auth_db[:account_webauthn_keys].where(account_id: account_id).count
  end

  def status_of(account_id)
    auth_db[:accounts].where(id: account_id).get(:status_id)
  end

  # The account id in the server-side session blob behind the current
  # browser's cookie.
  def session_account_id
    store = Onetime::Operations::Sessions::Store
    db    = Familia.dbclient
    key   = store.find_key(db, rack_mock_session.cookie_jar['onetime.session'])
    expect(key).not_to be_nil, 'no server-side session for the current cookie'
    store.load_data(db, key, codec: Onetime::SessionCodec.from_config)['account_id']
  end

  # The key from the verification email delivered to +email+.
  def emailed_verify_key(email)
    mails = @delivered.select { |m| m[:to].to_s.include?(OT::Utils.normalize_email(email)) }
    expect(mails.size).to eq(1), "expected one email to #{email}, got #{mails.size}"
    link  = mails.first[:body].to_s[%r{https?://\S+?/verify-account\?key=\S+}]
    expect(link).not_to be_nil, 'missing /verify-account link in the delivered email'
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  # Signs up +email+ in the current browser session and returns the account row.
  def sign_up!(email)
    @emails << email
    header 'Host', canonical_host
    csrf_json_post('/auth/create-account', login: email, password: password)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['next_action']).to eq('verify_email')

    account = auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).first
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    account
  end

  # Rodauth's passkey verification: phase 1 answers 422 with the creation
  # options, phase 2 posts the attestation signed for them together with the
  # key. Leaves the phase-2 response as last_response.
  def verify_with_passkey(key)
    header 'Host', canonical_host
    csrf_json_post('/auth/verify-account', key: key)
    expect(last_response.status).to eq(422),
      "Phase-1 verify-account should return the creation options (#{last_response.status}: #{last_response.body})"
    options   = json_body
    challenge = options.fetch('webauthn_setup_challenge')
    hmac      = options.fetch('webauthn_setup_challenge_hmac')
    rp_id     = options.fetch('webauthn_setup').fetch('rp').fetch('id')
    expect(rp_id).to eq(canonical_host)

    attestation = WebAuthn::FakeClient.new("http://#{canonical_host}").create(challenge: challenge, rp_id: rp_id)

    csrf_json_post(
      '/auth/verify-account',
      key: key,
      webauthn_setup: attestation,
      webauthn_setup_challenge: challenge,
      webauthn_setup_challenge_hmac: hmac,
    )
  end

  it 'verifies the account, stores the passkey and adds the codes to that account', :aggregate_failures do
    clear_cookies
    email       = unique_test_email('webauthn-recovery')
    account     = sign_up!(email)
    rows_before = auth_db[:account_recovery_codes].count

    verify_with_passkey(emailed_verify_key(email))
    expect(last_response.status).to eq(200),
      "Phase-2 verify-account should verify the account (#{last_response.status}: #{last_response.body})"

    expect(status_of(account[:id])).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(webauthn_key_count(account[:id])).to eq(1)
    expect(recovery_codes_for(account[:id]).size).to eq(codes_limit)
    # Every code the ceremony wrote belongs to the verified account.
    expect(auth_db[:account_recovery_codes].count - rows_before).to eq(codes_limit)
    # The verify transaction committed through to the key deletion.
    expect(auth_db[:account_verification_keys].where(id: account[:id]).count).to eq(0)
  end

  # A browser that verified one account by passkey keeps that account's
  # autologin session (account_id set, `authenticated` not), which
  # already_logged_in (config/base.rb) lets through to /auth/verify-account.
  # Following a second account's link there must add the codes to the second
  # account, the one the key names, and leave the session's account alone.
  it "adds the codes to the account the key names, not the session's account", :aggregate_failures do
    clear_cookies
    first_email = unique_test_email('webauthn-recovery-first')
    first       = sign_up!(first_email)
    verify_with_passkey(emailed_verify_key(first_email))
    expect(last_response.status).to eq(200), last_response.body
    first_codes = recovery_codes_for(first[:id])
    expect(first_codes.size).to eq(codes_limit)
    expect(session_account_id).to eq(first[:id])

    # The second account signs up from another browser.
    second_email = unique_test_email('webauthn-recovery-second')
    second       = with_session(:second_browser) { sign_up!(second_email) }
    rows_before  = auth_db[:account_recovery_codes].count

    verify_with_passkey(emailed_verify_key(second_email))
    expect(last_response.status).to eq(200),
      "Phase-2 verify-account should verify the second account (#{last_response.status}: #{last_response.body})"

    expect(status_of(second[:id])).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(webauthn_key_count(second[:id])).to eq(1)
    expect(recovery_codes_for(second[:id]).size).to eq(codes_limit)
    expect(auth_db[:account_recovery_codes].count - rows_before).to eq(codes_limit)

    expect(recovery_codes_for(first[:id])).to eq(first_codes)
    expect(webauthn_key_count(first[:id])).to eq(1)
    expect(session_account_id).to eq(second[:id])
  end
end
