# apps/web/auth/config/features/lockout.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Brute force lockout protection.
  #
  # ENV: AUTH_LOCKOUT_ENABLED (default: enabled, set to 'false' to disable)
  #
  module Lockout
    def self.configure(auth)
      auth.enable :lockout

      # Lockout settings (brute force protection)
      auth.max_invalid_logins 5
      # auth.lockout_expiration_default 3600  # 1 hour
    end
  end
end
