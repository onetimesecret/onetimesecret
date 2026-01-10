# apps/web/auth/config.rb
#
# frozen_string_literal: true

#
# IMPORTANT: Test files should NOT require this file or anything below it.
#
# This file triggers the full boot chain (database.rb → Onetime.auth_config)
# which requires production config files and database connections.
#
# For specs that need constants from config/features/*.rb, use:
#   require_relative 'spec/support/auth_test_constants'
#   include AuthTestConstants
#
# This provides test-safe copies of MFA limits, status IDs, etc.

require 'rodauth'
require 'rodauth/tools'

module Auth
  class Config < Rodauth::Auth
    # Track configuration state to prevent duplicate configuration.
    # In test environments, this file may be required multiple times
    # (via specs and Application Registry discovery). Rodauth's configure
    # block runs each time it's called, so we guard against re-entry.
    @configured = false

    class << self
      attr_accessor :configured

      # Reset configuration state (for testing only)
      def reset_configuration!
        @configured = false
      end
    end

    require_relative 'lib/logging'
    require_relative 'database'
    require_relative 'operations'
    require_relative 'config/base'
    require_relative 'config/email'
    require_relative 'config/features'
    require_relative 'config/hooks'
    require_relative 'config/rodauth_overrides'

    configure do
      # =====================================================================
      # CONFIGURATION GUARD
      # =====================================================================
      #
      # Skip if already configured. This prevents errors when the configure
      # block is called multiple times (e.g., in test environments).
      # Use `next` not `return` because we're in an instance_exec context.
      #
      if Auth::Config.configured
        OT.ld '[Auth::Config] Skipping duplicate configuration (already configured)'
        next
      end

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
      RodauthOverrides.configure(self)

      # Hardening: brute force protection, password requirements
      if Onetime.auth_config.hardening_enabled?
        Features::Hardening.configure(self)
      end

      # Active sessions: track and manage sessions across devices
      if Onetime.auth_config.active_sessions_enabled?
        Features::ActiveSessions.configure(self)
      end

      # Remember me: persistent login across browser sessions
      if Onetime.auth_config.remember_me_enabled?
        Features::RememberMe.configure(self)
      end

      # Multi-Factor Authentication: TOTP, recovery codes
      if Onetime.auth_config.mfa_enabled?
        Features::MFA.configure(self)
        Hooks::MFA.configure(self)
      end

      # Email auth: passwordless login via email links (aka magic links)
      if Onetime.auth_config.email_auth_enabled?
        Features::EmailAuth.configure(self)
        Hooks::EmailAuth.configure(self)
      end

      # WebAuthn: biometrics, security keys (Face ID, Touch ID, YubiKey)
      if Onetime.auth_config.webauthn_enabled?
        Features::WebAuthn.configure(self)
        Hooks::WebAuthn.configure(self)
      end

      # Mark configuration complete
      Auth::Config.configured = true
    end
  end
end
