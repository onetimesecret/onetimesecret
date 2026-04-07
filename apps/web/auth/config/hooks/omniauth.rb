# apps/web/auth/config/hooks/omniauth.rb
#
# frozen_string_literal: true

#
# OmniAuth callback hooks for SSO authentication.
# All hooks are provider-agnostic — they use omniauth_provider/omniauth_email
# from the standard OmniAuth auth hash. Adding new providers requires no
# changes here.
#
# Flow: POST /auth/sso/{provider} → IdP → callback → hooks below → login
# Session sync happens via the standard after_login hook (hooks/login.rb).
#
# See: docs/authentication/omniauth-sso.md (full configuration guide)
# See: features/omniauth.rb (provider registration)
#

module Auth::Config::Hooks
  module OmniAuth
    def self.configure(auth)
      # Normalize email for case-insensitive account lookup.
      # Required because:
      # - SQLite (dev/test) uses case-sensitive string comparison
      # - Redis Customer records require exact email match
      # - IdPs may return emails with different casing than stored
      # Uses NFC normalization and :fold for international email addresses.
      auth.account_from_omniauth do
        normalized_email = OT::Utils.normalize_email(omniauth_email)
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
        # Use trailing slash to avoid matching unrelated paths like /auth/sso-admin.
        # Also handle exact match for /auth/sso (the SSO index/landing, if any).
        is_sso_route    = request.path.start_with?("#{full_sso_prefix}/") || request.path == full_sso_prefix
        !is_sso_route
      end

      # ========================================================================
      # ⚠️  CRITICAL: CSRF Bypass for OmniAuth Routes - DO NOT REMOVE
      # ========================================================================
      #
      # CSRF protection operates at two layers here:
      #
      #   1. Rack::Protection::AuthenticityToken (Rack middleware)
      #      - Configured in: lib/onetime/middleware/security.rb
      #      - Uses 'shrimp' parameter name, stores token in session[:csrf]
      #      - Skipped for /auth/sso/* via allow_if callback
      #
      #   2. Rodauth's route_csrf plugin (application layer)
      #      - Auto-loaded when plugin :rodauth is called
      #      - Uses different token format than Rack::Protection
      #      - Runs during omniauth_request_validation_phase
      #
      # WHY THIS HOOK EXISTS:
      # The default omniauth_request_validation_phase calls `check_csrf if check_csrf?`
      # which invokes route_csrf validation. This FAILS because:
      #   - Rack::Protection is skipped → no token in session[:csrf]
      #   - route_csrf tries to decode nil → "encoded token is not a string"
      #
      # OAuth's state parameter provides CSRF protection for the SSO flow:
      #   1. Request phase: OmniAuth generates random state, stores in session
      #   2. Callback phase: Provider returns state, OmniAuth validates match
      #
      # WHAT HAPPENS IF YOU REMOVE THIS HOOK:
      # SSO login breaks immediately with error:
      #   "Roda::RodaPlugins::RouteCsrf::InvalidToken: encoded token is not a string"
      #
      # See: https://github.com/janko/rodauth-omniauth (request validation docs)
      # See: lib/onetime/middleware/security.rb (Rack::Protection config)
      #
      auth.omniauth_request_validation_phase do
        # ⚠️  INTENTIONALLY EMPTY - DO NOT ADD CODE HERE
        #
        # This empty block skips Roda's route_csrf validation.
        # OAuth state parameter provides CSRF protection instead.
        # Removing this block breaks SSO with "encoded token is not a string".
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

          # Join domain's organization if SSO came from a custom domain
          # This enables domain-based org selection in OrganizationLoader
          domain_id = session[:omniauth_tenant_domain_id]
          if domain_id
            Onetime::ErrorHandler.safe_execute(
              'join_domain_organization_omniauth',
              extid: customer.extid,
              domain_id: domain_id,
            ) do
              Auth::Operations::JoinDomainOrganization.new(
                customer: customer,
                domain_id: domain_id,
              ).call
            end
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

      # ========================================================================
      # HOOK: OmniAuth Failure Handler
      # ========================================================================
      #
      # Override to add debug logging before redirecting on failure.
      # The omniauth_error_type and omniauth_error are populated by rodauth-omniauth
      # from OmniAuth's env['omniauth.error.type'] and env['omniauth.error'].
      #
      auth.omniauth_on_failure do
        # Extract error details with safe fallbacks for logging.
        # Use safe navigation and || fallbacks to avoid exceptions.
        error_type  = (omniauth_error_type if respond_to?(:omniauth_error_type)) || :unknown
        error_msg   = omniauth_error&.message || 'No error message'
        error_class = omniauth_error&.class&.name || 'Unknown'

        # Debug: write to stderr so it shows in overmind/terminal
        warn "[OmniAuth FAILURE] type=#{error_type} class=#{error_class} msg=#{error_msg} path=#{request.path}"

        Auth::Logging.log_auth_event(
          :omniauth_failure,
          level: :warn,
          error_type: error_type,
          error_message: error_msg,
          path: request.path,
          ip: request.ip,
        )

        redirect omniauth_failure_redirect
      end

      auth.omniauth_failure_redirect do
        # Redirect to Vue frontend login page with error indicator.
        # Query param allows frontend to display appropriate error message.
        '/signin?auth_error=sso_failed'
      end
    end
  end
end
