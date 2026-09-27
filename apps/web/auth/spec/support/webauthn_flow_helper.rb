# apps/web/auth/spec/support/webauthn_flow_helper.rb
#
# frozen_string_literal: true

require_relative 'auth_test_constants'
require_relative 'auth_request_helper'
require_relative 'account_seed_helper'

# =============================================================================
# WebAuthn Lane Helper (integration/full_mfa/)
# =============================================================================
#
# Passkey provisioning and assertion through Rodauth's OWN JSON ceremonies,
# driven by the webauthn gem's WebAuthn::FakeClient (a software authenticator
# that signs real challenges for a real origin/RP ID). Nothing in the server
# path is stubbed: the stored public key, sign counter, rp_id and surface_scope
# are exactly what production writes.
#
# LOAD-TIME SIDE EFFECT — AUTH_WEBAUTHN_ENABLED: requiring this file sets
# AUTH_WEBAUTHN_ENABLED=true. In a :full_auth_mode context the auth config
# config.rb consults at boot is AuthModeHelpers::MockAuthConfig
# (spec/support/auth_mode_helpers.rb), whose webauthn_enabled default reads
# this variable; Auth::Config is one-shot per process, so it must be set before
# the suite's FIRST boot. RSpec loads every spec file before any hook runs, so
# setting it at require time is early enough — the same reason
# support/mfa_flow_helper.rb sets AUTH_MFA_ENABLED. The full:mfa rake task and
# tests/lanes/full-mfa/env export it too, so the lane is explicit; this line
# makes a direct `rspec <one file>` invocation work. Requiring this file
# outside the full_mfa lane would leak WebAuthn into that process's boot —
# don't.
#
# Usage (after `require_relative '../../spec_helper'`):
#
#   require_relative '../../support/mfa_flow_helper'
#   require_relative '../../support/webauthn_flow_helper'
#
#   RSpec.describe '...', :full_auth_mode, type: :integration do
#     include MfaFlowHelper
#     include WebauthnFlowHelper
#
#     it '...' do
#       account_id = seed_account_with_password(email)
#       passkey    = register_passkey(host, email: email)
#       # later, on `host`:
#       login_with_password_and_passkey(host, email: email, passkey: passkey)
#     end
#   end
#
# =============================================================================

ENV['AUTH_WEBAUTHN_ENABLED'] = 'true'

require 'webauthn'
require 'webauthn/fake_client'

module WebauthnFlowHelper
  # A registered passkey: the fake authenticator holding the private key, plus
  # the origin and RP ID it was registered against and the credential id the
  # server stored.
  Passkey = Struct.new(:client, :origin, :rp_id, :webauthn_id, keyword_init: true) do
    # Sign a server-issued challenge. The RP ID defaults to the registration
    # RP ID: a fake authenticator only holds keys for the RP it created them
    # for, exactly like hardware.
    def assert(challenge:, rp_id: self.rp_id)
      client.get(challenge: challenge, rp_id: rp_id)
    end
  end

  def self.included(base)
    base.include Rack::Test::Methods
    base.include AuthRequestHelper
    base.include AccountSeedHelper

    # Hard-fail (not skip): a file that includes this helper EXISTS to cover
    # the passkey path, so a boot without the webauthn feature is harness
    # breakage, not an environment quirk.
    base.before(:all) do
      webauthn_loaded = Auth::Config.method_defined?(:webauthn_auth_route) ||
                        Auth::Config.private_method_defined?(:webauthn_auth_route)
      unless webauthn_loaded
        raise 'Rodauth webauthn feature not loaded — this suite must boot with ' \
              'AUTH_WEBAUTHN_ENABLED=true in a fresh process (Auth::Config is one-shot)'
      end
    end
  end

  # The origin Rack::Test presents for a bare Host header: plain http, default
  # port. Auth::PublicHost.webauthn_base_url rebuilds the same value from
  # request.scheme/port, so the fake client and the server agree.
  def passkey_origin(host)
    "http://#{host}"
  end

  # ==========================================================================
  # Passkey registration — through Rodauth's OWN JSON setup flow on `host`:
  #   phase 1: POST /auth/webauthn-setup {password} -> 422 + { webauthn_setup (the
  #            creation options incl. rp.id), webauthn_setup_challenge,
  #            webauthn_setup_challenge_hmac }
  #   phase 2: POST /auth/webauthn-setup {webauthn_setup: <attestation>,
  #            webauthn_setup_challenge, webauthn_setup_challenge_hmac,
  #            password}                       -> 200
  # after_webauthn_setup (config/hooks/webauthn.rb) then stamps rp_id and
  # surface_scope from THIS request's host, which is what makes the credential
  # a tenant credential (or a platform one) for Onetime::ReauthPolicy.
  #
  # Logs the account in with its password first (the account must not yet
  # require a second factor) and clears cookies on the way out, so the flow
  # under test starts from an unauthenticated browser.
  # ==========================================================================
  def register_passkey(host, email:, password: AuthTestConstants::TEST_PASSWORD)
    header 'Host', host
    csrf_json_post('/auth/login', login: email, password: password)
    expect(last_response.status).to eq(200),
      "Precondition failed: password login for passkey setup (#{last_response.status}: #{last_response.body})"
    expect(json_body['mfa_required']).to be_nil,
      'Precondition failed: passkey setup expects an account with no second factor yet'

    # Rodauth checks the password BEFORE the setup param, so phase 1 must
    # carry it too (otherwise: 401 "invalid password" with the options attached).
    csrf_json_post('/auth/webauthn-setup', password: password)
    expect(last_response.status).to eq(422),
      "Phase-1 webauthn-setup should return the creation options with a field error (#{last_response.status}: #{last_response.body})"
    setup     = json_body
    challenge = setup['webauthn_setup_challenge']
    hmac      = setup['webauthn_setup_challenge_hmac']
    rp_id     = setup.dig('webauthn_setup', 'rp', 'id')
    expect(challenge).not_to be_nil
    expect(hmac).not_to be_nil
    expect(rp_id).to eq(host), "Server offered RP ID #{rp_id.inspect} for host #{host}"

    client      = WebAuthn::FakeClient.new(passkey_origin(host))
    attestation = client.create(challenge: challenge, rp_id: rp_id)

    csrf_json_post(
      '/auth/webauthn-setup',
      webauthn_setup: attestation,
      webauthn_setup_challenge: challenge,
      webauthn_setup_challenge_hmac: hmac,
      password: password,
    )
    expect(last_response.status).to eq(200),
      "Phase-2 webauthn-setup should store the credential (#{last_response.status}: #{last_response.body})"

    clear_cookies
    Passkey.new(client: client, origin: passkey_origin(host), rp_id: rp_id, webauthn_id: attestation['id'])
  end

  # ==========================================================================
  # Password login followed by the passkey second factor, on `host`:
  #   POST /auth/login                    -> 200 mfa_required
  #   POST /auth/webauthn-auth {}         -> 422 + { webauthn_auth (request
  #                                          options), webauthn_auth_challenge,
  #                                          webauthn_auth_challenge_hmac }
  #   POST /auth/webauthn-auth {assertion, challenge, hmac} -> 200
  # Ends with after_two_factor_authentication having run, i.e. a fully
  # authenticated session whose authenticated_by is ['password', 'webauthn'].
  # ==========================================================================
  def login_with_password_and_passkey(host, email:, passkey:, password: AuthTestConstants::TEST_PASSWORD)
    header 'Host', host
    csrf_json_post('/auth/login', login: email, password: password)
    expect(last_response.status).to eq(200),
      "Precondition failed: password login (#{last_response.status}: #{last_response.body})"
    expect(json_body['mfa_required']).to eq(true),
      "Precondition failed: login should demand a second factor (#{last_response.body})"

    csrf_json_post('/auth/webauthn-auth', {})
    expect(last_response.status).to eq(422),
      "Phase-1 webauthn-auth should return the request options with a field error (#{last_response.status}: #{last_response.body})"
    options   = json_body
    challenge = options['webauthn_auth_challenge']
    hmac      = options['webauthn_auth_challenge_hmac']
    expect(challenge).not_to be_nil
    expect(hmac).not_to be_nil

    csrf_json_post(
      '/auth/webauthn-auth',
      webauthn_auth: passkey.assert(challenge: challenge),
      webauthn_auth_challenge: challenge,
      webauthn_auth_challenge_hmac: hmac,
    )
    expect(last_response.status).to eq(200),
      "Passkey second factor should complete the login (#{last_response.status}: #{last_response.body})"
    last_response
  end

  # Recovery codes Rodauth auto-minted alongside the passkey
  # (auto_add_recovery_codes? is on in this deploy; the codes are stored as
  # plain rows). Used where a login on a host the passkey is NOT bound to still
  # has to complete its second factor.
  def recovery_codes_for(account_id)
    auth_db[:account_recovery_codes].where(id: account_id).select_map(:code)
  end
end
