# apps/web/auth/config/features/security.rb

module Auth
module Config
  module Features
    module Security
      def self.configure(auth)

          # Security features
          # enable :lockout         # Brute force protection (includes login failure tracking)
          # enable :active_sessions # Track active sessions
          # enable :login_password_requirements_base
          # enable :remember        # Remember me functionality

          # Table column configurations
          # All Rodauth tables use account_id as FK, not id

          # Lockout feature table configuration
          auth.account_login_failures_table :account_login_failures
          auth.account_login_failures_id_column :account_id
          auth.account_lockouts_table :account_lockouts
          auth.account_lockouts_id_column :account_id

          # Active sessions table configuration
          auth.active_sessions_table :account_active_session_keys
          auth.active_sessions_account_id_column :account_id

          # Remember me table configuration
          auth.remember_table :account_remember_keys
          auth.remember_id_column :account_id

          # Lockout settings (brute force protection)
          auth.max_invalid_logins 5
          # lockout_expiration_default 3600  # 1 hour
        end
      end
    end
  end
end
