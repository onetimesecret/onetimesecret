# frozen_string_literal: true

module Auth
  module Config
    module Features
      module Security
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Security features
            enable :lockout   # Brute force protection
            enable :active_sessions  # Track active sessions
            enable :login_password_requirements_base

            # Lockout settings (brute force protection)
            max_invalid_logins 5
            # lockout_expiration_default 3600  # 1 hour
          end
        end
      end
    end
  end
end
