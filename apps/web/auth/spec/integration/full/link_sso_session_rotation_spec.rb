# apps/web/auth/spec/integration/full/link_sso_session_rotation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Link-SSO password sign-in starts a new session id (#4466).
#
# POST /auth/link-sso verifies the existing password against the challenge's
# account, binds the identity, and signs in with `rodauth.login('password')`
# (apps/web/auth/routes/link_sso.rb), which runs Rodauth's login_session ->
# update_session -> clear_session, and this app's clear_session is
# `session.destroy` (apps/web/auth/config/base.rb). This example completes a
# challenge with an anonymous session already stored under the browser's
# cookie and checks the outcome: the signed-in session lives under a new id,
# the old id is ended (blob gone, SessionEnded marker set), and the old
# cookie is not signed in.
#
# The challenge is minted directly with Onetime::SsoLinkChallenge.issue, as
# the route examples in omniauth_signin_interstitial_spec.rb do: the POST
# reloads everything it needs from the token, so the callback round-trip that
# issues it is not part of this transition.
#
# Assertions follow sso_callback_session_rotation_spec.rb.
#
# RUN:
#   tests/lanes/run full-sqlite \
#     --only apps/web/auth/spec/integration/full/link_sso_session_rotation_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/sso_link_flow_helper'

RSpec.describe 'Link-SSO password sign-in starts a new session id (#4466)', type: :integration do
  include Rack::Test::Methods
  include SsoLinkFlowHelper

  before(:all) { boot_onetime_app }

  before { enable_platform_fallback }

  let(:store) { Onetime::Operations::Sessions::Store }
  let(:db) { Familia.dbclient }

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def blob_for(sid)
    key = store.find_key(db, sid)
    key && store.load_data(db, key, codec: Onetime::SessionCodec.from_config)
  end

  # GET /api/account/ (an Otto sessionauth route) for the given cookie, on a
  # fresh cookie jar so the current one is untouched.
  def account_read_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response
  end

  it 'signs in under a new id and ends the old one', :aggregate_failures do
    email      = unique_test_email('link-sso-rotation')
    uid        = "sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    extid      = auth_db[:accounts].where(id: account_id).get(:external_id)
    challenge  = Onetime::SsoLinkChallenge.issue(
      provider: 'oidc',
      issuer: 'https://issuer.example.com',
      uid: uid,
      email: OT::Utils.normalize_email(email),
      account_id: account_id,
    )

    # The anonymous session the browser holds on the interstitial, stored
    # server-side and not signed in.
    clear_cookies
    fetch_csrf_token
    old_sid = current_sid
    expect(old_sid).not_to be_nil
    expect(blob_for(old_sid)).not_to be_nil
    expect(blob_for(old_sid)['authenticated']).not_to be(true)

    result = post_link_sso(token: challenge.token, password: AuthTestConstants::TEST_PASSWORD)
    expect(result.status).to eq(200), "link-sso: #{result.status} #{result.body}"
    expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).get(:account_id)).to eq(account_id)

    new_sid = current_sid
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'account_id' => account_id, 'external_id' => extid)
    expect(blob['active_session_id_hmac']).not_to be_nil

    new_read = account_read_for(new_sid)
    expect(new_read.status).to eq(200), new_read.body
    expect(JSON.parse(new_read.body)['user_id']).to eq(extid)
    expect(account_read_for(old_sid).status).to eq(401)
  end
end
