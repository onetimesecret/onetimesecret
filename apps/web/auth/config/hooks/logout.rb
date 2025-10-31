# apps/web/auth/config/hooks/login.rb

module Auth::Config::Hooks
  module Logout
    def self.configure(auth)

      #
      # Hook: Before Logout
      #
      # This hook is triggered just before the session is destroyed on logout.
      #
      auth.before_logout do
        loggable_email = Onetime::Utils.obscure_email(session['email'] || 'n/a')
        OT.info "[auth] User logging out: #{loggable_email}"
        Auth::Logging.log_auth_event(
          :before_logout,
          level: :info,
          email: loggable_email,
          session_id: session.id,
        )
        response.headers['set-cookie'] = Rack::Utils.delete_set_cookie_header('onetime.session')
      end

      #
      # Hook: After Logout
      #
      # This hook is triggered after the user has been logged out.
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
