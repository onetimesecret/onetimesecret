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
    end

    require_relative 'lib/logging'
    require_relative 'database'
    require_relative 'operations'
    require_relative 'config/base'
    require_relative 'config/email'
    require_relative 'config/features'
    require_relative 'config/hooks'
    require_relative 'config/json_mode'
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
        OT.lw '[Auth::Config] Skipping duplicate configuration (already configured)'
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

      # Password hashing: argon2id
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
      Hooks::PasswordMigration.configure(self)
      Hooks::ErrorHandling.configure(self)
      RodauthOverrides.configure(self)

      # Lockout: brute force protection
      if Onetime.auth_config.lockout_enabled?
        Features::Lockout.configure(self)
      end

      # Password requirements: strength validation
      if Onetime.auth_config.password_requirements_enabled?
        Features::PasswordRequirements.configure(self)
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

      # OmniAuth: external identity providers (SSO via OIDC)
      # Routes are registered when either:
      # - AUTH_SSO_ENABLED=true (platform-level SSO with env var credentials)
      # - ORGS_SSO_ENABLED=true (domain-level SSO with DB credentials)
      # When only orgs_sso_enabled?, platform providers may be empty but routes
      # must exist for OmniAuthTenant hook to inject tenant credentials at runtime.
      if Onetime.auth_config.omniauth_enabled? || Onetime.auth_config.orgs_sso_enabled?
        Features::OmniAuth.configure(self)
        Hooks::OmniAuth.configure(self)
        Hooks::OmniAuthTenant.configure(self)
      end

      # OAuth2/OIDC Identity Provider: this OTS instance acts as an IdP.
      # Hooks (key loading, scope/claim mapping) and seeded clients land in
      # tasks 5 and 6 of issue #3104. Configuring the feature now is safe:
      # without keys, the runtime endpoints raise, but boot is unaffected.
      if Onetime.auth_config.oauth_enabled?
        Features::OAuth.configure(self)
        Hooks::OAuth.configure(self)
      end

      # Billing: plan selection carry-through for checkout flow
      if Onetime.billing_config.enabled?
        Hooks::Billing.configure(self)
      end

      # Single owner of only_json?. Must run AFTER all hooks so the
      # consolidated exemption logic can consult Hooks::OAuth::OAUTH_EXEMPT_PATHS
      # and omniauth_prefix. See apps/web/auth/config/json_mode.rb for the
      # rationale (def_auth_value_method replaces previous definitions).
      ::Auth::JsonMode.configure(self)

      # Mark configuration complete
      Auth::Config.configured = true
    end
  end
end
