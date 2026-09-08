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
#
# LANE: spec:integration:full (lib/tasks/spec.rake). Run it as
#
#   bundle exec rake spec:integration:full
#
# The lane starts the process with ORGS_SSO_ENABLED=true, which registers
# the /auth/sso/* routes the SSO examples below drive. Those examples are
# tagged `lane_env:` so a bare `bundle exec rspec` of this file, which is
# not a lane, fails them with a message naming the lane instead of a 401
# that reads like a gate bug (spec/support/helpers/lane_env_helpers.rb).

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

  # The gate's premise is that every full-mode login runs through Rodauth's
  # login_session, which stamps the join key
  # (apps/web/auth/config/features/active_sessions.rb). But
  # Core::Controllers::Authentication also answers POST /auth/login
  # (apps/web/core/routes.txt, the simple-mode sign-in) and writes
  # `authenticated` with neither account_id nor join key: a Rack session the
  # gate would exempt from revocation forever. What keeps it off the /auth
  # surface in full mode is mount order alone: Auth::Application at /auth is
  # mounted ahead of Core::Application at /, so URLMap never hands /auth/*
  # to core. Pin that at the mount table and on the wire, so a registry
  # change cannot quietly hand full-mode logins to the controller that mints
  # unrevocable sessions.
  describe 'the /auth surface is Rodauth in full mode' do
    let(:test_email) { "auth-surface-#{SecureRandom.hex(8)}@example.com" }

    def session_blob(sid)
      db    = Familia.dbclient
      dbkey = Onetime::Operations::Sessions::Store.find_key(db, sid)
      codec = Onetime::SessionCodec.from_config
      Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: codec)
    end

    it 'mounts Auth::Application at /auth ahead of Core::Application at /' do
      mappings = Onetime::Application::Registry.mount_mappings
      expect(mappings['/auth']).to eq(Auth::Application)
      expect(mappings['/']).to eq(Core::Application)
    end

    it 'mints a login session carrying account_id and the join key, the shape only login_session writes' do
      account = create_verified_account(db: test_db, email: test_email, password: test_password)
      login!(email: test_email)

      blob = session_blob(rack_mock_session.cookie_jar['onetime.session'])
      expect(blob['account_id']).to eq(account[:id])
      expect(blob['active_session_id_hmac']).to be_a(String)
      expect(blob['active_session_id_hmac']).not_to be_empty

      row_key = test_db[:account_active_session_keys].where(account_id: account[:id]).get(:session_id)
      expect(row_key).to eq(blob['active_session_id_hmac'])
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

      # Rodauth's deadlines are decided in the gate's SELECT (see the gate's
      # module doc): the same request that would have refreshed last_use
      # refuses the Rack session and removes the row instead.
      it 'refuses the Rack session once its row is past the inactivity deadline, and removes the row' do
        account_rows.update(last_use: Time.now - (Onetime::ActiveSessionGate::INACTIVITY_DEADLINE + 60))

        get '/api/account/'
        expect(last_response.status).to eq(401)
        expect(account_rows.count).to eq(0)
      end

      it 'refuses the Rack session once its row is past the lifetime deadline, however active' do
        account_rows.update(created_at: Time.now - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE + 60), last_use: Time.now)

        get '/api/account/'
        expect(last_response.status).to eq(401)
        expect(account_rows.count).to eq(0)
      end

      it 'applies the same two deadlines Rodauth itself is configured with' do
        deadlines = Auth::Config.internal_request_eval { [session_inactivity_deadline, session_lifetime_deadline] }
        expect(deadlines).to eq([Onetime::ActiveSessionGate::INACTIVITY_DEADLINE, Onetime::ActiveSessionGate::LIFETIME_DEADLINE])
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

      # Login is not the only route a stale cookie presents a credential
      # on. Every route Rodauth serves without a login continues as the
      # anonymous request the destroyed session leaves behind, instead of a
      # 401 that only self-heals on retry; an OmniAuth callback has no retry.
      describe 'other routes Rodauth serves without a login' do
        let(:new_email) { "revoked-signup-#{SecureRandom.hex(8)}@example.com" }

        # A plain sign-up does not auto-login (only an invite signup does), so
        # the proof is the account, not a new row.
        it 'lets the revoked Rack session sign up a new account' do
          account_rows.delete

          post_json '/auth/create-account',
            {
              login: new_email,
              'login-confirm': new_email,
              password: test_password,
              'password-confirm': test_password,
            }
          expect(last_response.status).to eq(200), last_response.body
          expect(test_db[:accounts].where(email: new_email).count).to eq(1)
        end

        it 'lets the revoked Rack session request a password reset' do
          account_rows.delete

          post_json '/auth/reset-password-request', { login: test_email }
          expect(last_response.status).to eq(200), last_response.body
        end

        # The SSO routes exist only when the full lane's ORGS_SSO_ENABLED=true
        # registered them; without it they 404 and the gate never sees them,
        # so the tag fails the example loudly instead of testing nothing.
        it 'does not refuse the SSO request and callback routes as session_expired',
          lane_env: { 'ORGS_SSO_ENABLED' => 'true' } do
          account_rows.delete

          get '/auth/sso/oidc'
          expect(last_response.status).not_to eq(401)

          # The request above destroyed the Rack session; mint a fresh one
          # and revoke it so the callback is also reached while :revoked.
          login!(email: test_email)
          account_rows.delete
          get '/auth/sso/oidc/callback'
          expect(last_response.status).not_to eq(401)
        end

        it 'still refuses a login-required route (the exemption is by route, not blanket)' do
          account_rows.delete

          get_json '/auth/account'
          expect(last_response.status).to eq(401)
          expect(json_response['error']).to eq('web.auth.security.session_expired')
        end
      end

      # Every branch of the gate on this surface leaves a line an operator
      # can match a user report against: which route, how it was answered,
      # and what the Rack session was carrying mid-flow when it was cleared.
      describe 'what the gate logs' do
        before { allow(Auth::Logging).to receive(:log_auth_event).and_call_original }

        def current_cookie_sid
          rack_mock_session.cookie_jar['onetime.session']
        end

        # Rewrite the live session blob through the same Store + Codec the
        # session admin verbs use, so the router reads the key back exactly
        # as OmniAuth's request phase would have left it.
        def stash_in_session_blob(key, value)
          db        = Familia.dbclient
          dbkey     = Onetime::Operations::Sessions::Store.find_key(db, current_cookie_sid)
          codec     = Onetime::SessionCodec.from_config
          data      = Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: codec)
          data[key] = value
          db.set(dbkey, codec.encode(data), keepttl: true)
        end

        it 'names the outcome of a refused route, with nothing in flight' do
          account_rows.delete

          get_json '/auth/account'

          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :active_session_revoked,
            hash_including(path: '/account', outcome: :refused, omniauth_keys: [], sidecar_fields: []),
          )
          expect(Auth::Logging).not_to have_received(:log_auth_event).with(:active_session_revoked_mid_flow, any_args)
        end

        it 'names the outcome of a route that continues anonymously' do
          account_rows.delete

          post_json '/auth/reset-password-request', { login: test_email }

          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :active_session_revoked,
            hash_including(path: '/reset-password-request', outcome: :continued_anonymous),
          )
        end

        # The case the exemption cannot save: revoked between an SSO flow's
        # request phase and its callback. The callback runs, but the clear
        # drops the OmniAuth state it verifies against and strands the
        # sidecar hand-off. The warn line names both so the SSO failure the
        # user then sees can be tied to the revocation, and the stranded
        # stash is purged with the clear: Rodauth's clear_session keeps the
        # sid and never reaches the store's delete path, so without the
        # router's own purge the explicit-use stash would outlive the
        # sign-out until its TTL.
        it 'warns, naming the dropped OmniAuth keys and stranded sidecar fields, and purges them, when revoked mid-SSO',
          lane_env: { 'ORGS_SSO_ENABLED' => 'true' } do
          sid = current_cookie_sid
          stash_in_session_blob('omniauth.state', 'abc123')
          Onetime::SessionSidecar.write(sid, 'sso_connect_intent', @account[:id])
          expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(true)
          account_rows.delete

          get '/auth/sso/oidc/callback'
          expect(last_response.status).not_to eq(401)

          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :active_session_revoked_mid_flow,
            hash_including(
              path: '/sso/oidc/callback',
              outcome: :continued_anonymous,
              omniauth_keys: ['omniauth.state'],
              sidecar_fields: ['sso_connect_intent'],
              consequence: /authorization code is spent/,
            ),
          )
          expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
        end

        it 'purges the sidecar hand-off stash when a refused route signs the session out' do
          sid = current_cookie_sid
          Onetime::SessionSidecar.write(sid, 'link_sso_pending_bind', { 'account_id' => @account[:id].to_s })
          account_rows.delete

          get_json '/auth/account'
          expect(last_response.status).to eq(401)

          expect(Onetime::SessionSidecar.exists?(sid, 'link_sso_pending_bind')).to be(false)
        end

        it 'logs each request an authdb outage refuses, and the logout it answers' do
          allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

          get_json '/auth/account'
          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :active_session_unverified,
            hash_including(path: '/account', outcome: :refused, account_id: @account[:id]),
          )

          post_json '/auth/logout', {}
          expect(Auth::Logging).to have_received(:log_auth_event).with(
            :active_session_unverified,
            hash_including(path: '/logout', outcome: :logout_answered),
          )
        end
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

  # #4391 — invite-signup auto-login must go through a real Rodauth
  # login-session so its Rack session is gate-enforced like a browser login's.
  #
  # The invite endpoint (apps/api/invite/logic/invites/signup_and_accept.rb)
  # creates the account via Rodauth's internal_request, which runs no login
  # path — so before this fix nothing stamped the active_session_id_hmac join
  # key or INSERTed the account_active_session_keys row, and every invite
  # session was exempt from the gate (:skipped) forever. SignupAndAccept#setup_session
  # now calls #establish_active_session, exercised here against the real authdb:
  # it must INSERT the row, stamp the join key, and produce a session the gate
  # rules :active — and :revoked once the row is deleted, proving the exemption
  # is closed. (The setup_session merge/wiring is unit-covered in
  # apps/api/invite/spec/logic/invites/signup_and_accept_spec.rb; this proves the
  # Rodauth mechanics the fix depends on and the gate transition end to end.)
  describe 'invite-signup auto-login is gate-enforced (#4391)' do
    require 'invite/logic'

    let(:invite_email) { "invite-gate-#{SecureRandom.hex(8)}@example.com" }

    # #establish_active_session reads no instance state (only its account_id
    # argument and Auth::Config), so allocate + send drives the production
    # method with zero duplication and no drift risk.
    def establish(account_id)
      InviteAPI::Logic::Invites::SignupAndAccept.allocate
        .send(:establish_active_session, account_id)
    end

    def gate_session(rodauth_session)
      # setup_session stringifies keys onto the Rack session before it is
      # persisted; mirror that so the gate sees what a real request would.
      rodauth_session.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    it 'INSERTs the active-session row and stamps the join key through login_session' do
      account = create_verified_account(db: test_db, email: invite_email)

      rows = test_db[:account_active_session_keys].where(account_id: account[:id])
      expect(rows.count).to eq(0)

      rodauth_session = establish(account[:id])

      expect(rows.count).to eq(1)
      expect(rodauth_session['account_id']).to eq(account[:id])
      expect(rodauth_session['active_session_id_hmac']).to be_a(String)
      expect(rodauth_session['active_session_id_hmac']).not_to be_empty
      # The stamp is HMAC(raw active_session_id) and equals the row's session_id.
      expect(rows.get(:session_id)).to eq(rodauth_session['active_session_id_hmac'])
    end

    it 'produces a session the gate rules :active, then :revoked once the row is deleted' do
      account = create_verified_account(db: test_db, email: invite_email)
      session = gate_session(establish(account[:id]))

      expect(Onetime::ActiveSessionGate.verdict(session)).to eq(:active)

      test_db[:account_active_session_keys].where(account_id: account[:id]).delete

      expect(Onetime::ActiveSessionGate.verdict(session)).to eq(:revoked)
    end

    # The bug: an invite session without a join key is exempt forever. Prove the
    # fix does not leave that hole — the produced session carries the join key,
    # so it is NOT the :skipped verdict the pre-fix hand-written session got.
    it 'is no longer exempt from the gate (join key present, not :skipped)' do
      account = create_verified_account(db: test_db, email: invite_email)
      session = gate_session(establish(account[:id]))

      expect(session['active_session_id_hmac']).not_to be_nil
      expect(Onetime::ActiveSessionGate.verdict(session)).not_to eq(:skipped)
    end
  end
end
