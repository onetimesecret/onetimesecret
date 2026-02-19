# apps/web/auth/config/features/password_requirements.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Password strength requirements.
  #
  # ENV: AUTH_PASSWORD_REQUIREMENTS_ENABLED (default: enabled, set to 'false' to disable)
  #
  module PasswordRequirements
    def self.configure(auth)
      auth.enable :login_password_requirements_base
    end
  end
end
