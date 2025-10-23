# apps/web/auth/config.rb

require_relative 'base'
require_relative 'database'
require_relative 'mailer'
require_relative 'config/features'
require_relative 'config/hooks'

module Auth
  class Config < Rodauth::Auth
    configure do
      # =====================================================================
      # 1. ENABLE FEATURES (configuration methods become available after)
      # =====================================================================

      # Configured in Features::Base
      enable :json, :login, :logout

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
      enable :otp, :recovery_codes

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
      Features::Security.configure(self) if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
      Features::MFA.configure(self) if ENV['ENABLE_MFA'] == 'true'
      Features::Passwordless.configure(self) if ENV['ENABLE_MAGIC_LINKS'] == 'true'
      Features::WebAuthnConfig.configure(self) if ENV['ENABLE_WEBAUTHN'] == 'true'



      # 4. Load and configure all hooks from modular files
      [
        Hooks::Validation.configure,
        Hooks::RateLimiting.configure,
        Hooks::AccountLifecycle.configure,
        Hooks::Authentication.configure,
        Hooks::SessionIntegration.configure,
      ].each do |hook_proc|
        instance_eval(&hook_proc)
      end
    end
  end
end
