# apps/web/auth/config/features/remember_me.rb
#
# frozen_string_literal: true

require 'onetime/session/remember_me'
require 'onetime/session/active_session_gate'

module Auth::Config::Features
  # Remember me: the login form's checkbox makes THIS session last a fixed 14
  # days from sign-in instead of the rolling 24 hours. The mechanism, and why
  # it is not Rodauth's remember feature, is described in
  # lib/onetime/session/remember_me.rb.
  #
  # ENV: AUTH_REMEMBER_ME_ENABLED (default: enabled, set to 'false' to disable).
  # Disabled, the `remember-me` parameter is ignored, and a session stamped
  # while it was on is held to the default lifetime again: the blob and
  # cookie stop being sized to the stamp and the row loses its inactivity
  # exemption. Its stamp still ends it when the 14 days are up.
  #
  # Rodauth's :remember feature is NOT enabled. Before this, it was, and
  # nothing ever called remember_login or load_memory, so the checkbox did
  # nothing. account_remember_keys stays in the schema, and is still cleared
  # on account deletion (operations/remove_authentication_data.rb).
  #
  # ## Which logins
  #
  # Any login that fires after_login and carries a truthy `remember-me`
  # parameter (Onetime::RememberMe::TRUTHY): the SPA's password form sends
  # it; the email-auth, WebAuthn and OmniAuth routes would honour it the same
  # way, but no client sends it there today. The autologins
  # (create_account, verify_account, reset_password) do not fire after_login
  # and are never remembered.
  #
  # ## Two-phase (MFA) logins
  #
  # The parameter arrives with the password, but the session is not signed in
  # until the second factor. So a login that still owes a second factor only
  # records the choice (`remember_me_pending`), and the session is
  # remembered when after_two_factor_authentication completes it; the 14
  # days run from then. A login abandoned at the second factor stays a
  # default session and its choice expires with it. The active-session row
  # exists from the first phase (login_session inserts it), so the second
  # phase stamps the same row.
  #
  # ## What is stamped
  #
  # The active-session row first, in the database's clock (the clock the gate
  # decides in), then the Rack session (Onetime::RememberMe.stamp), which the
  # session store turns into the blob TTL and the cookie lifetime. If the row
  # cannot be stamped, neither is, and the login proceeds as a default
  # session: a Rack session that outlived its row's inactivity deadline would
  # only be refused, so stamping one without the other buys nothing.
  #
  # The UPDATE runs in its own savepoint. It executes inside Rodauth's login
  # (or second-factor) transaction, and on PostgreSQL a failed statement
  # aborts the whole transaction: rescuing the error would leave the login
  # to roll back its own active-session row, or fail on the audit insert
  # that follows. The savepoint confines a failure to the stamp.
  module RememberMe
    # Rack session key for the choice held across the second factor.
    PENDING_KEY = 'remember_me_pending'

    def self.configure(auth)
      # rubocop:disable Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        # Called from after_login (config/hooks/login.rb).
        def remember_me_after_login(second_factor_pending:)
          return unless Onetime::RememberMe.requested?(raw_param(Onetime::RememberMe::PARAM))

          if second_factor_pending
            session[Auth::Config::Features::RememberMe::PENDING_KEY] = true
          else
            remember_this_session
          end
        end

        # Called from after_two_factor_authentication (config/hooks/two_factor.rb).
        def remember_me_after_two_factor
          return unless session.delete(Auth::Config::Features::RememberMe::PENDING_KEY)

          remember_this_session
        end

        def remember_this_session
          return unless stamp_active_session_remember_until

          Onetime::RememberMe.stamp(session)
        rescue StandardError => ex
          session.delete(Onetime::RememberMe::SESSION_KEY)
          OT.le "[remember_me] session not remembered (account_id=#{account_id}): #{ex.class}: #{ex.message}"
        end

        # True when there is no row to stamp (active_sessions off) or the
        # row was stamped.
        def stamp_active_session_remember_until
          join_key = session['active_session_id_hmac']
          return true unless Onetime.auth_config.active_sessions_enabled? && !join_key.to_s.empty?

          updated = db.transaction(savepoint: true) do
            db[Onetime::ActiveSessionGate::TABLE]
              .where(account_id: account_id, session_id: join_key)
              .update(remember_until: Sequel.date_add(Sequel::CURRENT_TIMESTAMP, seconds: Onetime::RememberMe::DURATION))
          end
          return true if updated == 1

          OT.lw "[remember_me] no active-session row to stamp; session not remembered (account_id=#{account_id})"
          false
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
    end
  end
end
