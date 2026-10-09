# apps/web/auth/spec/integration/full_mfa/passkey_login_session_rotation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, full-mfa lane)
# =============================================================================
#
# Passkey sign-in starts a new session id (#4466).
#
# POST /auth/webauthn-login is Rodauth's webauthn_login route, which signs in
# with `login('webauthn')` (rodauth 2.45.0
# lib/rodauth/features/webauthn_login.rb): login_session -> update_session ->
# clear_session, and this app's clear_session is `session.destroy`
# (apps/web/auth/config/base.rb). This example registers a passkey, then
# signs in with it alone from an anonymous session already stored under the
# browser's cookie, and checks the outcome: the signed-in session lives under
# a new id, the old id is ended (blob gone, SessionEnded marker set), and the
# old cookie is not signed in.
#
# The ceremony is the real one: support/webauthn_flow_helper.rb registers the
# credential through Rodauth's JSON setup flow with the webauthn gem's
# FakeClient, and the assertion below is signed for the challenge the server
# issues. In JSON mode the first POST without an assertion answers 422 with
# the request options (rodauth json.rb before_webauthn_login_route).
#
# WHY THIS LANE: the webauthn features are one-shot per process and only the
# full-mfa lane boots with AUTH_WEBAUTHN_ENABLED=true (tests/lanes/full-mfa/env).
#
# Assertions follow
# apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/passkey_login_session_rotation_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require_relative '../../support/webauthn_flow_helper'

RSpec.describe 'Passkey sign-in starts a new session id (#4466)', :full_auth_mode, type: :integration do
  include MfaFlowHelper
  include WebauthnFlowHelper

  # The passkey is registered for, and asserted on, the installed canonical
  # host (the RP ID the server offers there), as in
  # omniauth_connect_reauth_webauthn_spec.rb.
  include_context 'domains enabled'

  let(:store) { Onetime::Operations::Sessions::Store }
  let(:db) { Familia.dbclient }

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def blob_for(sid)
    key = store.find_key(db, sid)
    key && store.load_data(db, key, codec: Onetime::SessionCodec.from_config)
  end

  # GET /api/account/ (an Otto sessionauth route) for the given cookie on the
  # canonical host, on a fresh cookie jar so the current one is untouched.
  def account_read_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    env   = {
      'HTTP_ACCEPT' => 'application/json',
      'HTTP_HOST' => canonical_host,
      'HTTP_COOKIE' => "onetime.session=#{sid}",
    }
    other.get '/api/account/', {}, env
    other.last_response
  end

  it 'signs in under a new id and ends the old one', :aggregate_failures do
    email      = unique_test_email('passkey-rotation')
    account_id = seed_account_with_password(email)
    extid      = auth_db[:accounts].where(id: account_id).get(:external_id)

    passkey = register_passkey(canonical_host, email: email)
    expect(auth_db[:account_webauthn_keys].where(account_id: account_id).count).to eq(1)

    # Phase 1: the request options for this account's passkey.
    header 'Host', canonical_host
    csrf_json_post('/auth/webauthn-login', login: email)
    expect(last_response.status).to eq(422),
      "Phase-1 webauthn-login should return the request options (#{last_response.status}: #{last_response.body})"
    challenge = json_body['webauthn_auth_challenge']
    hmac      = json_body['webauthn_auth_challenge_hmac']
    expect(challenge).not_to be_nil
    expect(hmac).not_to be_nil

    # The anonymous session the browser holds when it signs in, stored
    # server-side and not signed in.
    old_sid = current_sid
    expect(old_sid).not_to be_nil
    expect(blob_for(old_sid)).not_to be_nil
    expect(blob_for(old_sid)['authenticated']).not_to be(true)
    expect(blob_for(old_sid)['account_id']).to be_nil

    csrf_json_post(
      '/auth/webauthn-login',
      login: email,
      webauthn_auth: passkey.assert(challenge: challenge),
      webauthn_auth_challenge: challenge,
      webauthn_auth_challenge_hmac: hmac,
    )
    expect(last_response.status).to eq(200), "webauthn-login: #{last_response.status} #{last_response.body}"
    expect(json_body['mfa_required']).to be_nil

    new_sid = current_sid
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'account_id' => account_id, 'external_id' => extid)
    expect(Array(blob['authenticated_by'])).to include('webauthn')

    new_read = account_read_for(new_sid)
    expect(new_read.status).to eq(200), new_read.body
    expect(JSON.parse(new_read.body)['user_id']).to eq(extid)
    expect(account_read_for(old_sid).status).to eq(401)
  end
end
