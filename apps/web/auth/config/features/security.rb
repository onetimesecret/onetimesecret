# apps/web/auth/config/features/security.rb

module Auth
  module Config
    module Features
      module Security
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Security features
            enable :lockout         # Brute force protection (includes login failure tracking)
            enable :active_sessions # Track active sessions
            enable :login_password_requirements_base
            enable :remember        # Remember me functionality

            # Table column configurations
            # All Rodauth tables use account_id as FK, not id

            # Lockout feature table configuration
            account_login_failures_table :account_login_failures
            account_login_failures_id_column :account_id
            account_lockouts_table :account_lockouts
            account_lockouts_id_column :account_id

            # Active sessions table configuration
            active_sessions_table :account_active_session_keys
            active_sessions_account_id_column :account_id

            # Remember me table configuration
            remember_table :account_remember_keys
            remember_id_column :account_id

            # Lockout settings (brute force protection)
            max_invalid_logins 5
            # lockout_expiration_default 3600  # 1 hour
          end
        end
      end
    end
  end
end
