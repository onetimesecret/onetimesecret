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
      enable :json, :login, :logout, :table_guard, :external_identity

      table_guard_mode :error
      table_guard_sequel_mode :skip
      table_guard_logger Onetime.get_logger('Auth')

      # Configure which columns to load from accounts table
      # IMPORTANT: Include external_id for Redis-SQL synchronization
      # external_identity_column :external_id
      # external_identity_check_columns :autocreate

      # Configured in Features::AccountManagement
      enable :verify_account unless ENV['RACK_ENV'] == 'test'
      enable :create_account
      enable :close_account
      enable :change_password
      enable :reset_password

      # Configured in Features::Security (conditionally enabled)
      if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
        enable :lockout
        enable :active_sessions
        enable :login_password_requirements_base
        enable :remember
      end

      # Configured in Features::MFA
      enable :two_factor_base
      enable :otp
      enable :recovery_codes

      # Configured in Features::Passwordless (authentication)
      enable :email_auth if ENV['ENABLE_MAGIC_LINKS'] == 'true'

      # Configured in Features::WebAuthn (authentication)
      enable :webauthn if ENV['ENABLE_WEBAUTHN'] == 'true'

      # =====================================================================
      # 2. BASE CONFIGURATION (database, HMAC, JSON, session)
      # =====================================================================
      Base.configure(self)
      Email.configure(self)

      # =====================================================================
      # 3. FEATURE CONFIGURATION
      # =====================================================================
      Features::AccountManagement.configure(self)

      Hooks::Account.configure(self)
      Hooks::Login.configure(self)
      Hooks::Logout.configure(self)
      Hooks::Password.configure(self)

      if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
        Features::Security.configure(self)
      end

      if ENV['ENABLE_MFA'] == 'true'
        Features::MFA.configure(self)
        Hooks::MFA.configure(self)
      end

      if ENV['ENABLE_MAGIC_LINKS'] == 'true'
        Features::Passwordless.configure(self)
        Hooks::Passwordless.configure(self)
      end

      if ENV['ENABLE_WEBAUTHN'] == 'true'
        Features::WebAuthn.configure(self)
        Hooks::WebAuthn.configure(self)
      end

    end
  end
end
