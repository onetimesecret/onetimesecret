# apps/web/auth/config/hooks/omniauth.rb
#
# frozen_string_literal: true

#
# ==============================================================================
# USER JOURNEY: OMNIAUTH SSO AUTHENTICATION
# ==============================================================================
#
# This file configures Rodauth hooks for OmniAuth-based single sign-on (SSO),
# enabling users to authenticate via external identity providers (OIDC).
#
# OMNIAUTH OVERVIEW:
# OmniAuth provides a standardized authentication flow across providers:
# - POST /auth/sso/:provider → redirects to identity provider
# - GET /auth/sso/:provider/callback → receives auth response
#
# USER JOURNEY - NEW USER:
#
# 1. USER CLICKS "LOGIN WITH SSO"
#    - Browser POSTs to /auth/sso/oidc
#    - OmniAuth generates authorization URL with PKCE challenge
#    - User redirected to identity provider (Zitadel, etc.)
#
# 2. USER AUTHENTICATES AT PROVIDER
#    - User enters credentials or uses existing session
#    - User may consent to requested scopes (email, profile)
#    - Provider generates authorization code
#
# 3. CALLBACK PROCESSING (this file)
#    - Provider redirects to /auth/sso/oidc/callback with code
#    - OmniAuth exchanges code for tokens
#    - omniauth_auth hash populated with user claims
#    - before_omniauth_callback_route fires for logging
#
# 4. ACCOUNT LOOKUP/CREATION
#    - _account_from_omniauth searches for existing account by email
#    - If not found: new account created (omniauth_create_account? true)
#    - after_omniauth_create_account creates Customer + workspace
#    - Identity row created in account_identities table
#
# 5. SESSION SYNC
#    - rodauth-omniauth calls login("omniauth") internally
#    - This triggers the regular after_login hook (in hooks/login.rb)
#    - Session synced via SyncSession operation
#    - User redirected to dashboard, fully authenticated
#
# NOTE: Session synchronization for OmniAuth happens via the standard
# after_login hook because rodauth-omniauth calls login() internally.
#
# ==============================================================================

module Auth::Config::Hooks
  module OmniAuth
    def self.configure(auth)
      # Normalize email for case-insensitive account lookup.
      # Required because:
      # - SQLite (dev/test) uses case-sensitive string comparison
      # - Redis Customer records require exact email match
      # - IdPs may return emails with different casing than stored
      auth.account_from_omniauth do
        normalized_email = omniauth_email.to_s.strip.downcase
        _account_from_login(normalized_email)
      end

      # ========================================================================
      # JSON Mode Override for OmniAuth
      # ========================================================================
      #
      # Disable JSON-only mode for OmniAuth routes. OmniAuth flow uses browser
      # redirects from the identity provider, not JSON API responses. When IdP
      # redirects back to /auth/sso/oidc/callback, we need:
      # - Real HTTP redirects (302) instead of JSON responses
      # - Flash messages stored in session for Core app to display
      #
      # Without this override, Rodauth's JSON feature intercepts set_redirect_error_flash
      # and stores the message in json_response[:error] which is lost on redirect.
      #
      # NOTE: request.path returns the full path (e.g., /auth/sso/oidc), but
      # omniauth_prefix is relative to Rodauth routes (e.g., /sso). We must
      # combine the Auth app's mount path with omniauth_prefix for comparison.
      #
      auth.only_json? do
        full_sso_prefix = "#{Auth::Application.uri_prefix}#{omniauth_prefix}"
        !request.path.start_with?(full_sso_prefix)
      end

      # ========================================================================
      # HOOK: Before OmniAuth Callback Route
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires at the very start of callback processing, before any
      # account lookup or creation. Useful for logging and debugging.
      #
      auth.before_omniauth_callback_route do
        Auth::Logging.log_auth_event(
          :omniauth_callback_start,
          level: :info,
          provider: omniauth_provider,
          uid: omniauth_uid,
          email: OT::Utils.obscure_email(omniauth_email),
          ip: request.ip,
        )
      end

      # ========================================================================
      # HOOK: Before OmniAuth Account Creation - Domain Validation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires BEFORE Rodauth creates a new account for an SSO user.
      # Used to enforce domain restrictions for SSO signups.
      #
      # CONFIGURATION:
      # Uses the same `allowed_signup_domains` config as regular signup.
      # Set via ALLOWED_SIGNUP_DOMAIN environment variable (comma-separated).
      #
      # Example: ALLOWED_SIGNUP_DOMAIN=company.com,subsidiary.com
      #
      auth.before_omniauth_create_account do
        allowed_domains = OT.conf.dig('site', 'authentication', 'allowed_signup_domains')

        # No restrictions configured - allow all domains
        next if allowed_domains.nil? || allowed_domains.empty?

        # Extract and validate domain from email
        email       = omniauth_email.to_s.strip.downcase
        email_parts = email.split('@')

        # Reject malformed emails
        if email_parts.length != 2 || email_parts.last.to_s.empty?
          Auth::Logging.log_auth_event(
            :omniauth_invalid_email,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            provider: omniauth_provider,
          )
          throw_error_status(400, 'invalid_email', 'Invalid email address from identity provider')
        end

        email_domain = email_parts.last

        # Check if domain is allowed (case-insensitive)
        normalized_domains = allowed_domains.compact.map(&:downcase)
        unless normalized_domains.include?(email_domain)
          Auth::Logging.log_auth_event(
            :omniauth_domain_rejected,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            domain: email_domain,
            provider: omniauth_provider,
          )
          # Generic error message - don't reveal which domains are allowed
          throw_error_status(403, 'domain_not_allowed', 'Your email domain is not authorized for SSO signup')
        end

        Auth::Logging.log_auth_event(
          :omniauth_domain_validated,
          level: :debug,
          email: OT::Utils.obscure_email(email),
          provider: omniauth_provider,
        )
      end

      # ========================================================================
      # HOOK: After OmniAuth Account Creation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after Rodauth creates a new account for an SSO user.
      # Similar to after_create_account, but specific to OmniAuth flow.
      #
      auth.after_omniauth_create_account do
        Auth::Logging.log_auth_event(
          :omniauth_account_created,
          level: :info,
          account_id: account_id,
          email: OT::Utils.obscure_email(account[:email]),
          provider: omniauth_provider,
        )

        # Create Customer record (same as regular signup)
        customer = Onetime::ErrorHandler.safe_execute(
          'create_customer_omniauth',
          account_id: account_id,
          provider: omniauth_provider,
        ) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: db,
          ).call
        end

        # Create default organization and team
        if customer.is_a?(Onetime::Customer)
          Onetime::ErrorHandler.safe_execute(
            'create_default_workspace_omniauth',
            extid: customer.extid,
          ) do
            Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
          end
        end
      end

      # ========================================================================
      # Failure Configuration
      # ========================================================================
      #
      # Configure flash message and redirect for authentication failures.
      # The default omniauth_on_failure method handles the actual failure flow.
      #
      auth.omniauth_failure_error_flash 'SSO authentication failed. Please try again or use password login.'

      auth.omniauth_failure_redirect do
        # login_path returns relative path (/login), but browser redirect needs
        # full path including the Auth app mount point (/auth/login)
        "#{Auth::Application.uri_prefix}#{login_path}"
      end
    end
  end
end
