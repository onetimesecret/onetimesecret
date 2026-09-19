# spec/integration/full/logout_ends_active_session_spec.rb
#
# frozen_string_literal: true

# Logout must end the session on the server, not only in this response.
#
# The Rack session store is last-writer-wins and every response re-sends the
# session cookie. A request that loaded the session BEFORE a logout and
# commits AFTER it writes the whole blob back under the old id and hands the
# browser the old cookie again. Found by the #4459 browser test "a session
# ended outside the tab": with dashboard fetches in flight during a logout in
# another tab, the next GET /bootstrap/me answered `authenticated`.
#
# Before this change logout only cleared the blob, so the written-back copy
# was a complete, valid session: its active-session row was never removed.
# Logout now removes the row first (Onetime::ActiveSessionGate.end_session),
# which makes the copy refusable like any other revoked session.
#
# The in-flight request is reproduced by its effect: the blob and the cookie
# are put back exactly as they were before the logout.

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Logout ends the active session (#4451)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Logout-Test1234!' }

  before do
    @matrix_customer = anonymous_probe_customer
    establish_matrix_session!
  end

  # What a request that loaded the session before the logout holds, and what
  # its commit and its Set-Cookie put back.
  def capture_session
    db  = Familia.dbclient
    key = session_store.find_key(db, current_session_id)
    { sid: current_session_id, key: key, raw: db.get(key), ttl: db.ttl(key) }
  end

  def write_back!(captured)
    Familia.dbclient.set(captured.fetch(:key), captured.fetch(:raw), ex: captured.fetch(:ttl))
    clear_cookies
    set_cookie "onetime.session=#{captured.fetch(:sid)}"
  end

  # The two logouts a browser can reach in full mode. POST /auth/logout is
  # Rodauth's (the SPA's sign-out button); its active_sessions feature already
  # removed the row. GET /logout is Web Core's (links, the colonel, a typed
  # URL) and only cleared the blob.
  def sign_out(path)
    path == '/auth/logout' ? post_json(path, {}) : get(path)
    expect(last_response.status).to be_between(200, 302)
  end

  shared_examples 'a logout that a late write cannot undo' do |verb, path|
    it "#{verb.upcase} #{path} removes the active-session row", :aggregate_failures do
      expect(activity_count).to eq(1)

      sign_out(path)

      expect(activity_count).to eq(0)
    end

    it "#{verb.upcase} #{path}: the session written back by an in-flight request is refused", :aggregate_failures do
      captured = capture_session
      expect(request_surface(:bootstrap, request_id: 'before-logout')[:auth_status]).to eq('authenticated')

      sign_out(path)
      write_back!(captured)

      # The copy is complete — without the row it would be a valid session.
      expect(session_blob).to include('authenticated' => true, 'external_id' => @matrix_customer.extid)

      polled = request_surface(:bootstrap, request_id: 'after-logout-poll')
      expect(polled[:status]).to eq(200)
      expect(polled[:auth_status]).to eq('anonymous')
      expect(polled[:customer_exposed]).to be(false)
      expect(polled[:snapshot_keys]).to be_empty

      write_back!(captured)
      refused = request_surface(:protected_api, request_id: 'after-logout-api')
      expect(refused[:status]).to eq(401)
      expect(refused[:refusal_code]).to eq('active_session_revoked')
    end
  end

  it_behaves_like 'a logout that a late write cannot undo', :get, '/logout'
  it_behaves_like 'a logout that a late write cannot undo', :post, '/auth/logout'

  it "leaves the account's other sessions signed in", :aggregate_failures do
    other = SecureRandom.hex(32)
    test_db[:account_active_session_keys].insert(account_id: @matrix_account[:id], session_id: other)

    get '/logout'

    expect(active_session_rows.select_map(:session_id)).to eq([other])
  end
end
