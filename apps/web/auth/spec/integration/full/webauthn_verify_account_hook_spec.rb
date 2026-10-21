# apps/web/auth/spec/integration/full/webauthn_verify_account_hook_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# after_verify_account runs when verify_account is loaded through
# webauthn_verify_account alone.
#
# AUTH_WEBAUTHN_VERIFY_ACCOUNT=true enables Rodauth's webauthn_verify_account
# (config/features/webauthn.rb), which depends on verify_account. So with the
# verify_account flag off, POST /auth/verify-account still exists and verifies
# the account. The app's after_verify_account hook (config/hooks/account.rb)
# used to be registered behind that flag alone, so in this configuration the
# SQL account was verified while the Customer stayed unverified and the
# federated claim the signup hook defers to verification never ran. The enable
# call (config/features/account_management.rb), the email template
# (config/email.rb), the hook and the signup deferral now all follow
# Onetime.auth_config.verify_account_loaded?, which counts either path.
#
# The lanes boot verify_account and webauthn OFF (spec/support/auth_mode_helpers.rb
# MockAuthConfig), and Auth::Config is configured once per process. So, as in
# verify_account_autologin_session_rotation_spec.rb, the examples run against
# a router subclass with the production modules applied in config.rb's order
# (the hook module before the WebAuthn module), with the two webauthn flags
# stubbed on and verify_account_enabled? left at the lane's false.
#
# The verification is Rodauth's own two-phase JSON ceremony
# (webauthn_verify_account.rb before_verify_account): the first POST with the
# key answers 422 with the credential-creation options, the second carries the
# attestation the webauthn gem's FakeClient signs for them, as the passkey
# specs do through support/webauthn_flow_helper.rb. That helper is not
# required here: requiring it sets AUTH_WEBAUTHN_ENABLED for the whole
# process, and this file runs in the lanes that boot without webauthn.
#
# RUN:
#   tests/lanes/run full-sqlite \
#     --only apps/web/auth/spec/integration/full/webauthn_verify_account_hook_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/domains_enabled_context'
require 'rack/test'
require 'cgi'
require 'webauthn'
require 'webauthn/fake_client'

RSpec.describe 'after_verify_account with verify_account loaded by webauthn_verify_account only',
  type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  # The passkey is created for the installed canonical host, the RP ID the
  # server offers there (Auth::PublicHost.webauthn_host), as in the full_mfa
  # passkey specs.
  include_context 'domains enabled'

  let(:password) { 'WebauthnVerify-Password123!' }
  let(:account_email) { unique_test_email('webauthn-verify') }
  let(:normalized_email) { OT::Utils.normalize_email(account_email) }

  before do
    # The configuration under test is the one the lane cannot boot: the
    # webauthn_verify_account sub-feature on, the verify_account flag off. A
    # lane that boots the flag on cannot run this file (harness breakage, so
    # a failure rather than a skip).
    if Onetime.auth_config.verify_account_enabled?
      raise 'this file covers verify_account OFF; the lane booted it on (AUTH_VERIFY_ACCOUNT_ENABLED)'
    end

    allow(Onetime.auth_config).to receive_messages(webauthn_enabled?: true, webauthn_verify_account_enabled?: true)

    router = Class.new(Auth::Router)
    router.plugin :rodauth do
      Auth::Config::Features::AccountManagement.configure(self)
      Auth::Config::Email::VerifyAccount.configure(self)
      Auth::Config::Hooks::Account.configure(self)
      Auth::Config::Features::WebAuthn.configure(self)
      Auth::Config::Hooks::WebAuthn.configure(self)

      # The lanes boot MFA (the mock's default), and with recovery_codes
      # loaded Rodauth adds the account's codes whenever a credential is
      # added: add_webauthn_credential -> auto_add_missing_recovery_codes,
      # since auto_add_recovery_codes? is on in features/mfa.rb. The insert is
      # keyed on session_value (rodauth 2.45.0 recovery_codes.rb,
      # add_recovery_code), which the verify-account ceremony does not have
      # yet: the autologin comes after the hook. So the passkey verification
      # fails with "NOT NULL constraint failed: account_recovery_codes.id"
      # before verify_account runs, in production too when AUTH_MFA_ENABLED
      # and AUTH_WEBAUTHN_VERIFY_ACCOUNT are both on. That is the
      # webauthn_verify_account + recovery_codes interplay, not what this file
      # covers, so the ceremony here runs without the auto-add.
      auto_add_recovery_codes? false if auth.features.include?(:recovery_codes)
    end
    allow_any_instance_of(Auth::Application).to receive(:build_router).and_return(router) # rubocop:disable RSpec/AnyInstance

    @verify_app = build_rack_app
    # Building the middleware reinitializes DomainStrategy; keep the shared
    # context's classification of the canonical host.
    Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])

    # The delivery seam: the rendered verification email, as the publisher
    # would receive it.
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end

    allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:new).and_call_original
    allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for).and_call_original
  end

  after do
    Onetime::Customer.find_by_email(normalized_email)&.destroy!
  rescue StandardError
    nil
  end

  def app
    @verify_app || super
  end

  def customer
    Onetime::Customer.find_by_email(normalized_email)
  end

  def verification_key_rows(account_id)
    auth_db[:account_verification_keys].where(id: account_id).count
  end

  # The key from the one delivered verification email.
  def emailed_verify_key
    expect(@delivered.size).to eq(1), "expected one delivered email, got #{@delivered.size}"
    link = @delivered.first[:body].to_s[%r{https?://\S+?/verify-account\?key=\S+}]
    expect(link).not_to be_nil, 'missing /verify-account link in the delivered email'
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  def sign_up!
    clear_cookies
    header 'Host', canonical_host
    csrf_json_post('/auth/create-account', login: account_email, password: password)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['next_action']).to eq('verify_email')

    account = auth_db[:accounts].where(email: normalized_email).first
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    account
  end

  # Rodauth's passkey verification: phase 1 answers 422 with the creation
  # options (and the field error for the missing attestation), phase 2 posts
  # the attestation signed for those options together with the key.
  def verify_with_passkey!(key)
    csrf_json_post('/auth/verify-account', key: key)
    expect(last_response.status).to eq(422),
      "Phase-1 verify-account should return the creation options (#{last_response.status}: #{last_response.body})"
    options   = json_body
    challenge = options.fetch('webauthn_setup_challenge')
    hmac      = options.fetch('webauthn_setup_challenge_hmac')
    rp_id     = options.fetch('webauthn_setup').fetch('rp').fetch('id')
    expect(rp_id).to eq(canonical_host)

    client      = WebAuthn::FakeClient.new("http://#{canonical_host}")
    attestation = client.create(challenge: challenge, rp_id: rp_id)

    csrf_json_post(
      '/auth/verify-account',
      key: key,
      webauthn_setup: attestation,
      webauthn_setup_challenge: challenge,
      webauthn_setup_challenge_hmac: hmac,
    )
    expect(last_response.status).to eq(200),
      "Phase-2 verify-account should verify the account (#{last_response.status}: #{last_response.body})"
  end

  it 'verifies the Customer, removes the key row and runs the deferred claim', :aggregate_failures do
    account = sign_up!
    expect(verification_key_rows(account[:id])).to eq(1)
    expect(customer.verified?).to be(false)

    verify_with_passkey!(emailed_verify_key)

    expect(auth_db[:accounts].where(id: account[:id]).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(auth_db[:account_webauthn_keys].where(account_id: account[:id]).count).to eq(1)
    expect(verification_key_rows(account[:id])).to eq(0)

    verified = customer
    expect(verified.verified?).to be(true)
    expect(verified.verified_by).to eq('email')
    expect(Auth::Operations::EnsureDefaultWorkspace).to have_received(:claim_pending_federation_for)
      .with(an_object_having_attributes(extid: verified.extid))

    # What the operator tooling reads: no pending verification for the account.
    diagnosis = Auth::Operations::Customers::Diagnose.new(customer: verified).call
    expect(diagnosis.sections.fetch(:verification)).to include(available: true, pending: false)
  end

  it 'defers the federated claim at signup, as the verify_account flag does', :aggregate_failures do
    sign_up!

    expect(Auth::Operations::EnsureDefaultWorkspace).to have_received(:new)
      .with(hash_including(require_verification: true))
    expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
  end
end
