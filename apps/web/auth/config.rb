# apps/web/auth/config.rb
#
# frozen_string_literal: true

require 'rodauth'
require 'rodauth/tools'

module Auth
  class Config < Rodauth::Auth
    require_relative 'lib/logging'
    require_relative 'database'
    # NOTE: mailer.rb is deprecated - using Onetime::Mail instead (see config/email.rb)
    require_relative 'operations'
    require_relative 'config/base'
    require_relative 'config/email'
    require_relative 'config/features'
    require_relative 'config/hooks'

    configure do
      # =====================================================================
      # CONFIGURATION MODULES
      # =====================================================================
      #
      # Each module handles its own `enable` calls alongside configuration.
      # This keeps feature enablement co-located with feature configuration.
      #

      # Core features: base, json, login, logout, table_guard, etc.
      Base.configure(self)

      # Password hashing: argon2id (more secure than bcrypt)
      Features::Argon2.configure(self)

      # Audit logging for authentication events
      Features::AuditLogging.configure(self)

      # Account lifecycle: create, verify, close, change/reset password
      # (must come before Email.configure - provides email_base feature)
      Features::AccountManagement.configure(self)

      # Email delivery configuration (requires email_base from above)
      Email.configure(self)

      # Hooks for customizing authentication behavior
      Hooks::Account.configure(self)
      Hooks::AuditLogging.configure(self)
      Hooks::Login.configure(self)
      Hooks::Logout.configure(self)
      Hooks::Password.configure(self)
      Hooks::ErrorHandling.configure(self)

      # Security features: lockout, active sessions, remember me
      if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
        Features::Security.configure(self)
      end

      # Multi-Factor Authentication: TOTP, recovery codes
      if ENV['ENABLE_MFA'] == 'true'
        Features::MFA.configure(self)
        Hooks::MFA.configure(self)
      end

      # Passwordless authentication: email magic links
      if ENV['ENABLE_MAGIC_LINKS'] == 'true'
        Features::Passwordless.configure(self)
        Hooks::Passwordless.configure(self)
      end

      # WebAuthn: biometrics, security keys (Face ID, Touch ID, YubiKey)
      if ENV['ENABLE_WEBAUTHN'] == 'true'
        Features::WebAuthn.configure(self)
        Hooks::WebAuthn.configure(self)
      end
    end
  end
end
