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
      # NOTE: Missing: No account_from_omniauth override. Rodauth-omniauth's default
      # looks up by email from omniauth_email but may need customization if the
      # accounts table has different email handling.

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
        login_path
      end
    end
  end
end
