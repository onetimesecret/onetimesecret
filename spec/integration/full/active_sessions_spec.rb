# spec/integration/full/active_sessions_spec.rb
#
# frozen_string_literal: true

# Integration tests for active sessions management in full auth mode.
# Tests the complete HTTP flow: account creation, login, session listing,
# and session management endpoints.
#
# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb). The :full_auth_mode tag
# triggers automatic setup of an in-memory SQLite database shared across
# all tagged specs in the suite.

require 'spec_helper'

RSpec.describe 'Active Sessions Management', type: :integration do
  include_context 'auth_rack_test'
  # AuthAccountFactory and test_db are provided by :full_auth_mode tag

  let(:test_password) { 'Test1234!@' }

  # Helper to login via HTTP - raises on failure for explicit test failures
  def login!(email:, password: test_password)
    post_json '/auth/login', { login: email, password: password }
    unless last_response.status == 200
      raise "Login failed for #{email}: #{last_response.status} - #{last_response.body}"
    end

    true
  end

  describe 'authentication requirements' do
    it 'GET /auth/active-sessions returns 401 without session' do
      get_json '/auth/active-sessions'
      expect(last_response.status).to eq(401)
    end

    it 'POST /auth/remove-all-active-sessions returns 401 without session' do
      post_json '/auth/remove-all-active-sessions', {}
      expect(last_response.status).to eq(401)
    end
  end

  describe 'with authenticated session' do
    let(:test_email) { "sessions-test-#{SecureRandom.hex(8)}@example.com" }

    before do
      # Create account directly in database for faster setup
      @account = create_verified_account(db: test_db, email: test_email, password: test_password)
      # Login via HTTP to establish session - raises if login fails
      login!(email: test_email)
    end

    # Onetime::ActiveSessionGate (terms defined there): the active-session
    # row in account_active_session_keys is now load-bearing for EVERY
    # authenticated request, not just the sessions page. Revoking it — a user
    # from another device, or an operator in Rodauth Admin — refuses the Rack
    # session on its next request. Before the gate the Rack session kept
    # answering `authenticated` until it expired.
    def account_rows
      test_db[:account_active_session_keys].where(account_id: @account[:id])
    end

    describe 'per-request enforcement of the active-session row' do
      it 'serves an authenticated API request while the active-session row exists' do
        expect(account_rows.count).to be >= 1

        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body
      end

      it 'refuses the same Rack session once its active-session row has been revoked' do
        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body

        account_rows.delete

        get '/api/account/'
        expect(last_response.status).to eq(401)
      end

      it 'refuses the Rack session when its active-session row cannot be checked (authdb down, fail closed)' do
        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body

        allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

        get '/api/account/'
        expect(last_response.status).to eq(401)
      end

      it 'keeps refreshing the active-session row last_use so the inactivity sweep sees activity' do
        stale = Time.now - (Onetime::ActiveSessionGate::TOUCH_INTERVAL + 60)
        account_rows.update(last_use: stale)

        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body

        expect(Time.now - account_rows.first[:last_use]).to be < 5
      end
    end

    # The /auth surface authenticates on rodauth.logged_in?, which reads only
    # the Rack session. The router consults the gate ahead of every /auth
    # route so a revoked Rack session cannot keep reading the account,
    # unlinking identities or revoking everyone else's rows there.
    describe 'on the /auth surface' do
      it 'refuses GET /auth/account once the active-session row has been revoked, as a session_expired' do
        get_json '/auth/account'
        expect(last_response.status).to eq(200), last_response.body

        account_rows.delete

        get_json '/auth/account'
        expect(last_response.status).to eq(401)
        expect(json_response['error']).to eq('web.auth.security.session_expired')
      end

      it 'refuses GET /auth/active-sessions and POST /auth/remove-all-active-sessions once revoked' do
        account_rows.delete

        get_json '/auth/active-sessions'
        expect(last_response.status).to eq(401)

        post_json '/auth/remove-all-active-sessions', {}
        expect(last_response.status).to eq(401)
      end

      it 'refuses a Rodauth login-required route once revoked' do
        account_rows.delete

        post_json '/auth/change-password', { password: test_password, 'new-password': 'Another1234!@' }
        expect(last_response.status).to eq(401)
      end

      it 'refuses /auth/account when the active-session row cannot be checked (fail closed)' do
        allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

        get_json '/auth/account'
        expect(last_response.status).to eq(401)
        expect(json_response['error_type']).to eq('SessionUnverified')
      end

      # Signing out grants nothing, so it is the one thing an unverifiable
      # Rack session may still do during an authdb outage.
      it 'still lets the Rack session log out while the authdb is unreachable' do
        allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

        post_json '/auth/logout', {}
        expect(last_response.status).to eq(200), last_response.body

        allow(Auth::Database).to receive(:connection).and_call_original
        get '/api/account/'
        expect(last_response.status).to eq(401)
      end

      # The revoked Rack session is destroyed on this surface (not merely
      # refused) so a login on the same cookie is not refused by its own
      # stale session.
      it 'lets the same cookie sign in again after its row was revoked' do
        account_rows.delete
        get_json '/auth/account'
        expect(last_response.status).to eq(401)

        login!(email: test_email)

        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body
        expect(account_rows.count).to eq(1)
      end

      # The motivating case: an operator revokes the browser, the SPA sends
      # the user to sign-in, and the FIRST /auth request on the stale cookie
      # is the login itself. It must succeed, not bounce off its own session.
      it 'signs in when the login is the first request after revocation' do
        account_rows.delete

        login!(email: test_email)

        get '/api/account/'
        expect(last_response.status).to eq(200), last_response.body
      end

      # Answered by the router itself, not Rodauth: the Rack session is already
      # destroyed, and a revoked browser's global logout must not touch the
      # account's other rows.
      it 'lets a revoked Rack session log out (success, nothing else revoked)' do
        other_row = { account_id: @account[:id], session_id: 'b' * 64 }
        test_db[:account_active_session_keys].insert(other_row)
        account_rows.exclude(session_id: 'b' * 64).delete

        post_json '/auth/logout', { global_logout: '1' }
        expect(last_response.status).to eq(200), last_response.body

        expect(test_db[:account_active_session_keys].where(other_row).count).to eq(1)
        get '/api/account/'
        expect(last_response.status).to eq(401)
      end
    end

    # The join key is stamped into the Rack session at login by
    # apps/web/auth/config/features/active_sessions.rb. Since the gate joins
    # on it and skips Rack sessions without one, a login whose stamp fails
    # must not succeed: it would mint a Rack session no revocation could end.
    describe 'when the join-key stamp fails at login' do
      let(:other_email) { "stamp-fail-#{SecureRandom.hex(8)}@example.com" }

      before do
        create_verified_account(db: test_db, email: other_email, password: test_password)
        allow(OT).to receive(:le).and_call_original
        # The computation is stubbed, not the stamp itself, so the stamp's
        # rescue (error log, clear_session, re-raise) is what runs.
        allow_any_instance_of(Auth::Config) # rubocop:disable RSpec/AnyInstance -- Rodauth instantiates per request
          .to receive(:active_session_join_key).and_raise(RuntimeError, 'hmac_secret missing')
      end

      it 'refuses the login loudly instead of minting an unrevocable Rack session' do
        post_json '/auth/login', { login: other_email, password: test_password }
        expect(last_response.status).to eq(500)
        expect(OT).to have_received(:le).with(/join-key stamp failed.*hmac_secret missing/)

        get '/api/account/'
        expect(last_response.status).to eq(401)
        expect(test_db[:account_active_session_keys].where(account_id: test_db[:accounts].where(email: other_email).get(:id)).count).to eq(0)
      end
    end

    describe 'GET /auth/account' do
      before { get_json '/auth/account' }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'includes active_sessions_count field' do
        expect(json_response).to have_key('active_sessions_count')
      end

      it 'reports at least 1 active session (current session)' do
        expect(json_response['active_sessions_count']).to be >= 1
      end
    end

    describe 'GET /auth/active-sessions' do
      before { get_json '/auth/active-sessions' }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'contains sessions array' do
        expect(json_response).to have_key('sessions')
        expect(json_response['sessions']).to be_an(Array)
      end

      it 'has at least one session (current session)' do
        expect(json_response['sessions'].length).to be >= 1
      end

      it 'marks current session with is_current flag' do
        current = json_response['sessions'].find { |s| s['is_current'] }
        expect(current).not_to be_nil
      end

      it 'includes required session fields' do
        session = json_response['sessions'].first
        expect(session).to include('id', 'created_at', 'last_activity_at')
      end

      # Regression guard: the active-session row is joined to the SessionMetadata
      # sidecar on the sidecar's stored active_session_id_hmac. When that join
      # breaks, created_at/last_activity_at silently fall back to the Rodauth
      # row and hide the failure, but ip_address has no fallback and goes nil —
      # so it is the field that proves the join actually matched.
      it 'populates ip_address on the current session from the metadata sidecar' do
        current = json_response['sessions'].find { |s| s['is_current'] }
        expect(current['ip_address']).not_to be_nil
      end
    end

    describe 'DELETE /auth/active-sessions/:id (current session)' do
      it 'returns 400 when attempting to delete current session' do
        # Get current session ID
        get_json '/auth/active-sessions'
        current_session_id = json_response['sessions'].find { |s| s['is_current'] }['id']

        delete_json "/auth/active-sessions/#{current_session_id}"
        expect(last_response.status).to eq(400)
      end

      it 'includes error message about current session' do
        get_json '/auth/active-sessions'
        current_session_id = json_response['sessions'].find { |s| s['is_current'] }['id']

        delete_json "/auth/active-sessions/#{current_session_id}"
        expect(json_response['error']).to include('current session')
      end
    end

    describe 'POST /auth/remove-all-active-sessions' do
      before { post_json '/auth/remove-all-active-sessions', {} }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'indicates success in response' do
        expect(json_response).to have_key('success')
      end

      it 'leaves only current session remaining' do
        get_json '/auth/active-sessions'
        expect(json_response['sessions'].length).to eq(1)
      end

      it 'remaining session is marked as current' do
        get_json '/auth/active-sessions'
        expect(json_response['sessions'].first['is_current']).to be true
      end
    end

    describe 'POST /auth/logout' do
      it 'returns 200' do
        post_json '/auth/logout', {}
        expect(last_response.status).to eq(200)
      end

      it 'invalidates session (subsequent requests return 401)' do
        post_json '/auth/logout', {}
        get_json '/auth/active-sessions'
        expect(last_response.status).to eq(401)
      end
    end
  end
end
