# apps/web/auth/spec/integration/full_mfa/magic_link_session_rotation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, full-mfa lane)
# =============================================================================
#
# Magic-link sign-in starts a new session id (#4466).
#
# POST /auth/email-login is Rodauth's email_auth route, which signs in with
# `login('email_auth')` (rodauth 2.45.0 lib/rodauth/features/email_auth.rb):
# login_session -> update_session -> clear_session, and this app's
# clear_session is `session.destroy` (apps/web/auth/config/base.rb). This
# example requests a link, follows the emailed key with an anonymous session
# already stored under the browser's cookie, and checks the outcome: the
# signed-in session lives under a new id, the old id is ended (blob gone,
# SessionEnded marker set), and the old cookie is not signed in.
#
# WHY THIS LANE: email_auth is one-shot per process (Auth::Config configures
# once) and only the full-mfa lane boots with AUTH_EMAIL_AUTH_ENABLED=true
# (tests/lanes/full-mfa/env). The :full_auth_mode tag is explicit because the
# path-derived tag only matches /integration/full/.
#
# Assertions follow
# apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/magic_link_session_rotation_spec.rb
# =============================================================================

# Load-time, before the suite's first boot (see
# omniauth_connect_email_auth_spec.rb): the lane exports it already; this keeps
# a single-file run from booting without the feature it exercises.
ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require 'cgi'

RSpec.describe 'Magic-link sign-in starts a new session id (#4466)', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  before(:all) do
    next if Auth::Config.method_defined?(:email_auth_route)

    raise 'Rodauth email_auth feature not loaded — this suite must boot with ' \
          'AUTH_EMAIL_AUTH_ENABLED=true in a fresh process (run via ' \
          '`tests/lanes/run full-mfa`; Auth::Config is one-shot)'
  end

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
    other.get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_COOKIE' => "onetime.session=#{sid}" }
    other.last_response
  end

  # The key from the one delivered magic-link email, as a mail client finds it.
  def emailed_login_key(delivered)
    expect(delivered.size).to eq(1), "expected one delivered email, got #{delivered.size}"
    body = delivered.first[:body].to_s
    link = body[%r{https?://\S+?/email-login\?key=[^\s"<]+}]
    expect(link).not_to be_nil, "no /email-login link in the delivered body:\n#{body[0, 600]}"
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  it 'signs in under a new id and ends the old one', :aggregate_failures do
    email      = unique_test_email('magic-link-rotation')
    account_id = seed_existing_account(email)
    extid      = auth_db[:accounts].where(id: account_id).get(:external_id)

    # The delivery seam (Auth::Config::Email::Delivery hands the rendered mail
    # to the publisher as a plain hash).
    delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |mail, **_kwargs|
      delivered << mail
      true
    end

    csrf_json_post('/auth/email-login-request', login: email)
    expect(last_response.status).to eq(200), "email-login-request: #{last_response.status} #{last_response.body}"
    key = emailed_login_key(delivered)

    # The anonymous session the browser holds when it follows the link,
    # stored server-side and not signed in.
    fetch_csrf_token
    old_sid = current_sid
    expect(old_sid).not_to be_nil
    expect(blob_for(old_sid)).not_to be_nil
    expect(blob_for(old_sid)['authenticated']).not_to be(true)

    csrf_json_post('/auth/email-login', key: key)
    expect(last_response.status).to eq(200), "email-login: #{last_response.status} #{last_response.body}"

    new_sid = current_sid
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'account_id' => account_id, 'external_id' => extid)
    expect(blob['auth_method']).to eq('email_auth')

    new_read = account_read_for(new_sid)
    expect(new_read.status).to eq(200), new_read.body
    expect(JSON.parse(new_read.body)['user_id']).to eq(extid)
    expect(account_read_for(old_sid).status).to eq(401)
  end
end
