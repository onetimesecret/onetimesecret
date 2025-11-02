# apps/web/auth/config.rb

require 'rodauth'
require 'rodauth/tools'

module Auth
  class Config < Rodauth::Auth
    require_relative 'lib/logging'
    require_relative 'database'
    require_relative 'mailer'
    require_relative 'operations'
    require_relative 'config/base'
    require_relative 'config/email'
    require_relative 'config/features'
    require_relative 'config/hooks'

    configure do
      # =====================================================================
      # 1. ENABLE FEATURES (configuration methods become available after)
      # =====================================================================

      # Configured in Features::Base
      enable :base, :json, :login, :logout, :table_guard, :external_identity
      enable :hmac_secret_guard

      # Configured in Features::AccountManagement
      enable :verify_account unless ENV['RACK_ENV'] == 'test'
      enable :create_account
      enable :close_account
      enable :change_password
      enable :reset_password

      Base.configure(self)
      Email.configure(self)

      Features::AccountManagement.configure(self)

      Hooks::Account.configure(self)
      Hooks::Login.configure(self)
      Hooks::Logout.configure(self)
      Hooks::Password.configure(self)
      Hooks::ErrorHandling.configure(self)

      # Configured in Features::Security (conditionally enabled)
      if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
        enable :lockout
        enable :active_sessions
        enable :login_password_requirements_base
        enable :remember
        Features::Security.configure(self)
      end

      # Configured in Features::MFA
      if ENV['ENABLE_MFA'] == 'true'
        enable :two_factor_base
        enable :otp
        enable :recovery_codes
        Features::MFA.configure(self)
        Hooks::MFA.configure(self)
      end

      # Configured in Features::Passwordless (authentication)
      if ENV['ENABLE_MAGIC_LINKS'] == 'true'
        enable :email_auth
        Features::Passwordless.configure(self)
        Hooks::Passwordless.configure(self)
      end

      # Configured in Features::WebAuthn (authentication)
      if ENV['ENABLE_WEBAUTHN'] == 'true'
        enable :webauthn, :webauthn_login, :webauthn_modify_email if ENV['ENABLE_WEBAUTHN'] == 'true'
        enable :webauthn_verify_account if ENV['WEBAUTHN_VERIFY_ACCOUNT']
        enable :webauthn_autofill if ENV['WEBAUTHN_AUTOFILL']
        Features::WebAuthn.configure(self)
        Hooks::WebAuthn.configure(self)
      end

    end
  end
end
