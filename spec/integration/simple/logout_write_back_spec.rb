# spec/integration/simple/logout_write_back_spec.rb
#
# frozen_string_literal: true

# RISK-2026-09-19-01: a request in flight during a logout must not be able to
# undo it.
#
# The session store is last-writer-wins and every response re-sends the
# session cookie. A request that LOADED the session before it was ended and
# COMMITS after it used to write the whole blob back under the old id and hand
# the browser the old cookie. Full mode refuses that copy through the missing
# active-session row (spec/integration/full/logout_ends_active_session_spec.rb).
# Simple mode has no row: the copy was a complete, valid session.
#
# Unlike the full-mode spec, which puts the blob back by hand, this one runs
# the real thing: one request is held open between its session read and its
# session write while a second one ends the session, so the late write goes
# through Onetime::Session#write_session. The second request runs on its own
# thread and is joined before the first continues, which makes the
# interleaving exact rather than timed.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'A request in flight cannot undo the end of its session (RISK-2026-09-19-01)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'WriteBack-Test1234!' }
  let(:app) do
    @simple_write_back_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    @matrix_customer = anonymous_probe_customer
    establish_simple_matrix_session!
  end

  def blob_key_for(sid)
    session_store.find_key(Familia.dbclient, sid)
  end

  # The logout as another tab of the same browser sends it: same cookie, its
  # own Rack::Test session so the held request's cookie jar is untouched.
  def logout_from_another_tab(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/logout'
    other.last_response
  end

  it 'refuses the late write after GET /logout: no blob, no cookie, and the old id is signed out', :aggregate_failures do
    sid = current_session_id
    expect(request_surface(:bootstrap, request_id: 'write-back-before')[:auth_status]).to eq('authenticated')

    logout_status = nil
    held          = hold_request_while { logout_status = logout_from_another_tab(sid).status }

    # The held request was authenticated when it was decided, and answers so.
    expect(logout_status).to be_between(200, 302)
    expect(held.status).to eq(200)

    # Its write was refused: the blob is gone and the old cookie is not
    # handed back.
    expect(blob_key_for(sid)).to be_nil
    expect(held.headers['set-cookie'].to_s).not_to include(sid)

    # A browser still holding the old cookie is signed out, and is moved off
    # the ended id so its anonymous session can be saved.
    clear_cookies
    set_cookie "onetime.session=#{sid}"
    polled = request_surface(:bootstrap, request_id: 'write-back-after')
    expect(polled).to include(status: 200, auth_status: 'anonymous', authenticated: false)
    expect(current_session_id).not_to eq(sid)
  end

  it 'refuses the late write after a colonel revokes the session', :aggregate_failures do
    sid = current_session_id

    held = hold_request_while do
      Onetime::Operations::Sessions::RevokeForCustomer.new(
        custid: @matrix_customer.extid,
        session_id: sid,
        actor: @matrix_customer,
      ).call
    end

    expect(held.status).to eq(200)
    expect(blob_key_for(sid)).to be_nil

    clear_cookies
    set_cookie "onetime.session=#{sid}"
    expect(request_surface(:protected_api, request_id: 'write-back-revoked')[:status]).to eq(401)
  end

  it 'keeps no copy of the session id in the marker', :aggregate_failures do
    sid = current_session_id
    logout_from_another_tab(sid)

    key = Onetime::SessionEnded.key_for(sid)
    expect(Familia.dbclient.exists?(key)).to be(true)
    expect(key).not_to include(sid)
    expect(key).not_to include('session')
    expect(Familia.dbclient.ttl(key)).to be_between(1, Onetime::SessionEnded::TTL)
    expect(Familia.dbclient.get(key)).to eq('1')
  end

  it 'does not disturb an ordinary request: the session is written and stays signed in' do
    expect(request_surface(:protected_api, request_id: 'write-back-ordinary')[:status]).to eq(200)
    expect(session_blob).to include('authenticated' => true)
  end
end
