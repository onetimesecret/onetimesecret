# apps/web/auth/config/features/hardening.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Hardening features: attack prevention via brute force protection
  # and password requirements.
  #
  # ENV: AUTH_HARDENING_ENABLED (default: enabled, set to 'false' to disable)
  #
  module Hardening
    def self.configure(auth)
      auth.enable :lockout                          # Brute force protection
      auth.enable :login_password_requirements_base # Password validation

      # Lockout settings (brute force protection)
      auth.max_invalid_logins 5
      # auth.lockout_expiration_default 3600  # 1 hour
    end
  end
end
