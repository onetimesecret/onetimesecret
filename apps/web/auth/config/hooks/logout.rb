# apps/web/auth/config/hooks/logout.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  module Logout
    def self.configure(auth)
      #
      # Hook: Before Logout
      #
      # This hook is triggered just before the session is destroyed on logout.
      #
      auth.before_logout do
        # Clear the recent full re-authentication proof (#4420) BEFORE the
        # session is destroyed. delete_session purges every sidecar key for the
        # sid, but that purge is best-effort; this explicit clear is the cheap
        # guarantee the proof is gone even when the destruction is partial.
        Onetime::RecentReauth.clear(session)

        loggable_email = Onetime::Utils.obscure_email(session['email'] || 'n/a')
        OT.info "[auth] User logging out: #{loggable_email}"
        Auth::Logging.log_auth_event(
          :before_logout,
          level: :info,
          email: loggable_email,
          session_id: session.id,
        )
      end

      #
      # Hook: After Logout
      #
      # This hook is triggered after the user has been logged out and the session
      # has been destroyed (via clear_session override that calls session.destroy).
      # The session store's delete_session method has been called, which deletes
      # the session from Redis and returns a new session ID for the response.
      #
      auth.after_logout do
        OT.info '[auth] Logout complete'
        Auth::Logging.log_auth_event(
          :after_logout,
          level: :info,
          session_id: session.id,
        )
      end
    end
  end
end
