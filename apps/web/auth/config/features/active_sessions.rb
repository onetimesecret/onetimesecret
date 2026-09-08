# apps/web/auth/config/features/active_sessions.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Active sessions feature: track and manage user sessions across devices.
  # Allows users to view where they're logged in and revoke sessions.
  #
  # ENV: AUTH_ACTIVE_SESSIONS_ENABLED (default: enabled, set to 'false' to disable)
  #
  module ActiveSessions
    def self.configure(auth)
      auth.enable :active_sessions

      # Session lifetime settings
      #
      # Enables updating last_use timestamp on each request where
      # currently_active_session? is checked.
      #
      auth.session_inactivity_deadline 86_400   # 24 hours - sessions inactive for this long are removed
      auth.session_lifetime_deadline 2_592_000  # 30 days - max session lifetime

      # Stamp the Rodauth-side JOIN KEY into the app session.
      #
      # WHY: Rodauth mints its OWN opaque token in add_active_session
      # (`active_session_id`, a random urlsafe_base64) and persists only
      # HMAC(active_session_id) in account_active_session_keys. It never sees the
      # Onetime Rack sid. The Onetime::SessionMetadata sidecar is keyed by that
      # PLAIN sid. The two records therefore share NO value, and HMACing the sid
      # does not produce the column Rodauth stored — the digests are of different
      # inputs and can never match. Carrying the digest across is the only way the
      # active-sessions route can attach browser/network detail to a Rodauth row.
      #
      # WHY HERE: compute_hmac needs the Rodauth instance (it keys off
      # hmac_secret), which Onetime::Operations::Sessions::TrackMetadata does not
      # have. So the digest is computed at auth time and copied verbatim into the
      # sidecar at session-write time — the same stamp-then-copy path
      # `session['auth_method']` already uses.
      #
      # WHY update_session: it is the single seam EVERY path that mints an
      # active_session_id passes through. Rodauth's own active_sessions override is
      # `remove_current_session; super; add_active_session`, so by the time `super`
      # returns here the new token is in the session. Hooking after_login instead
      # would miss the remember-cookie login and the create_account /
      # reset_password / verify_account autologins, which call login_session
      # directly and never fire after_login.
      #
      # The RAW token is deliberately NOT carried: the sidecar is not encrypted at
      # rest, and Rodauth itself persists only the digest.
      #
      # LOAD-BEARING: Onetime::ActiveSessionGate joins every authenticated
      # request to its active-session row on this stamp, and a Rack session
      # without one is exempt from revocation (it cannot be joined). The stamp
      # therefore cannot be best-effort: a login whose stamp fails would mint a
      # Rack session that no revocation could ever end. So a failed stamp
      # refuses the login instead: the Rack session is cleared (Rodauth's
      # `super` has already marked it authenticated) and the error propagates,
      # loudly, to the router's error handler; Rodauth's login transaction
      # rolls the freshly inserted active-session row back with it. The only
      # Rack sessions without a stamp are the ones minted before it existed.
      #
      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        def update_session
          super
          stamp_active_session_join_key
        end

        def stamp_active_session_join_key
          # String key matches the app-session convention (SyncSession,
          # 'auth_method'); read back by Sessions::TrackMetadata and joined on
          # by Onetime::ActiveSessionGate.
          session['active_session_id_hmac'] = active_session_join_key
        rescue StandardError => ex
          OT.le '[active_sessions] join-key stamp failed; login refused and Rack session cleared: ' \
                "#{ex.class}: #{ex.message}"
          clear_session
          raise
        end

        # HMAC(active_session_id), the form Rodauth persists. Its own method so
        # the refusal above can be exercised without stubbing compute_hmac,
        # which Rodauth's add_active_session also calls.
        def active_session_join_key
          token = session[session_id_session_key]
          raise "no #{session_id_session_key} in the Rack session after update_session" if token.nil?

          compute_hmac(token)
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
