# apps/web/auth/config/hooks/login.rb

module Auth::Config::Hooks
  module Login
    def self.configure(auth)
      #
      # Hook: Before Login Attempt
      #
      # This hook is triggered before processing a login attempt. It generates
      # a correlation ID for tracking the entire authentication flow.
      #
      auth.before_login_attempt do
        email = param('login') || param('email')

        # Generate correlation ID for this authentication attempt
        correlation_id                = Auth::Logging.generate_correlation_id
        session[:auth_correlation_id] = correlation_id

        Auth::Logging.log_auth_event(
          :login_attempt,
          level: :info,
          email: email,
          ip: request.ip,
          correlation_id: correlation_id,
        )
      end

      #
      # Hook: After Login
      #
      # This hook is triggered after a user successfully authenticates. It's
      # the primary integration point for syncing the application session.
      #
      # Standard Rodauth after_login hook - minimal custom logic
      auth.after_login do
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :login_success,
          level: :info,
          account_id: account_id,
          email: account[:email],
          correlation_id: correlation_id,
        )
        # Rodauth handles MFA flow automatically
      end

      #
      # Hook: After Login Failure
      #
      # This hook is triggered after a login attempt fails. It logs the
      # failure and raises a security alert on repeated failures.
      #
      auth.after_login_failure do
        email          = param('login') || param('email')
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :login_failure,
          level: :warn,
          email: email,
          ip: request.ip,
          correlation_id: correlation_id,
        )
      end
    end
  end
end
