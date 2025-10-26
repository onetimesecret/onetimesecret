# apps/web/auth/config/features/security.rb

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

      # Lockout settings (brute force protection)
      auth.max_invalid_logins 5
      # lockout_expiration_default 3600  # 1 hour

      # Active sessions configuration
      auth.active_sessions_account_id_column :account_id  # Foreign key in account_active_session_keys
    end
  end
end
