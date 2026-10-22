# apps/web/auth/spec/support/passkey_signup_helper.rb
#
# frozen_string_literal: true

require_relative 'auth_test_constants'
require_relative 'auth_request_helper'
require 'cgi'
require 'webauthn'
require 'webauthn/fake_client'

# =============================================================================
# Passkey Signup Helper (integration/full_webauthn_verify*/)
# =============================================================================
#
# Signup and email verification with a passkey through Rodauth's own
# webauthn_verify_account JSON ceremony (webauthn_verify_account.rb
# before_verify_account), for the full-webauthn-verify lane's two processes:
# the account is created with a password, and the emailed key is redeemed
# together with a new passkey instead of a password.
#
# The ceremony has two phases. The first POST with the key answers 422 with
# the credential-creation options (and the field error for the missing
# attestation); the second carries the attestation the webauthn gem's
# FakeClient signs for those options. They are separate methods so a spec can
# assert on the first and treat the second differently (the MFA probe marks
# everything after phase 1 pending).
#
# Unlike support/webauthn_flow_helper.rb, requiring this file sets no ENV:
# the lane exports AUTH_WEBAUTHN_ENABLED and AUTH_WEBAUTHN_VERIFY_ACCOUNT.
#
# Usage:
#
#   RSpec.describe 'Passkey signup', :full_auth_mode, type: :integration do
#     include PasskeySignupHelper
#     include_context 'domains enabled'   # passkey_signup! takes canonical_host
#
#     it '...' do
#       account = passkey_signup!(email, password: password, host: canonical_host)
#       key     = emailed_verify_key
#       options = passkey_setup_options(key, host: canonical_host)
#       submit_passkey_setup(key, options, host: canonical_host)
#     end
#   end
#
# =============================================================================

module PasskeySignupHelper
  def self.included(base)
    base.include Rack::Test::Methods
    base.include AuthRequestHelper

    # The delivery seam: the rendered verification email, as the publisher
    # would receive it.
    base.before do
      @delivered_emails = []
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
        @delivered_emails << email
        true
      end
    end
  end

  # Create the account on +host+ and assert it waits on verification.
  #
  # @return [Hash] the accounts row
  def passkey_signup!(email, password:, host:)
    clear_cookies
    header 'Host', host
    csrf_json_post('/auth/create-account', login: email, password: password)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['next_action']).to eq('verify_email')

    account = auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).first
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    account
  end

  # The key from the one delivered verification email.
  def emailed_verify_key
    expect(@delivered_emails.size).to eq(1), "expected one delivered email, got #{@delivered_emails.size}"
    link = @delivered_emails.first[:body].to_s[%r{https?://\S+?/verify-account\?key=\S+}]
    expect(link).not_to be_nil, 'missing /verify-account link in the delivered email'
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  def verification_key_rows(account_id)
    auth_db[:account_verification_keys].where(id: account_id).count
  end

  # Phase 1: the key alone. Asserts the 422 and the RP ID the server offers on
  # +host+ (Auth::PublicHost.webauthn_host).
  #
  # @return [Hash] the creation options, challenge and challenge HMAC
  def passkey_setup_options(key, host:)
    csrf_json_post('/auth/verify-account', key: key)
    expect(last_response.status).to eq(422),
      "Phase-1 verify-account should return the creation options (#{last_response.status}: #{last_response.body})"
    options = json_body
    expect(options.fetch('webauthn_setup').fetch('rp').fetch('id')).to eq(host)
    options
  end

  # Phase 2: the key with the attestation signed for +options+. Asserts
  # nothing; the response is the caller's to judge.
  def submit_passkey_setup(key, options, host:)
    challenge   = options.fetch('webauthn_setup_challenge')
    client      = WebAuthn::FakeClient.new("http://#{host}")
    attestation = client.create(challenge: challenge, rp_id: options.fetch('webauthn_setup').fetch('rp').fetch('id'))

    csrf_json_post(
      '/auth/verify-account',
      key: key,
      webauthn_setup: attestation,
      webauthn_setup_challenge: challenge,
      webauthn_setup_challenge_hmac: options.fetch('webauthn_setup_challenge_hmac'),
    )
  end
end
