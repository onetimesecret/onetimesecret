# apps/web/auth/config/features/security.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Security features configuration (lockout, active sessions, remember me)
  #
  module Security
    def self.configure(auth)

      # Security features
      # enable :lockout         # Brute force protection (includes login failure tracking)
      # enable :active_sessions # Track active sessions
      # enable :login_password_requirements_base
      # enable :remember        # Remember me functionality

      # Active sessions settings
      #
      # Enables updating last_use timestamp on each request where currently_active_session? is checked
      #
      auth.session_inactivity_deadline 86400  # 24 hours - sessions inactive for this long are removed
      auth.session_lifetime_deadline 2592000  # 30 days - max session lifetime

      # Lockout settings (brute force protection)
      auth.max_invalid_logins 5
      # lockout_expiration_default 3600  # 1 hour
    end
  end
end
