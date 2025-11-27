# apps/web/auth/config/features/security.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Security features configuration (lockout, active sessions, remember me)
  #
  module Security
    def self.configure(auth)
      # Security features (conditionally enabled via ENV in config.rb)
      auth.enable :lockout                          # Brute force protection
      auth.enable :active_sessions                  # Track active sessions
      auth.enable :login_password_requirements_base # Password validation
      auth.enable :remember                         # Remember me functionality

      # Active sessions settings
      #
      # Enables updating last_use timestamp on each request where currently_active_session? is checked
      #
      auth.session_inactivity_deadline 86_400  # 24 hours - sessions inactive for this long are removed
      auth.session_lifetime_deadline 2_592_000  # 30 days - max session lifetime

      # Lockout settings (brute force protection)
      auth.max_invalid_logins 5
      # lockout_expiration_default 3600  # 1 hour
    end
  end
end
