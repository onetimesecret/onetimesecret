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
        existing         = _account_from_login(normalized_email)

        if existing
          # SECURITY (H-3): reached ONLY when no account_identities row exists
          # for (provider, uid) — `existing` has never linked THIS identity.
          # Returning it would let create_omniauth_identity link the caller's
          # IdP identity to it and log them in → account takeover (an attacker
          # controlling a provider that emits the victim's email is signed in
          # as the victim). Refuse to auto-link by email; require explicit,
          # authenticated linking from account settings instead.
          #
          # This MUST redirect (halt) — returning nil here would fall through to
          # omniauth_create_account (omniauth_create_account? is true), which
          # inserts a row with the duplicate login and violates the unique
          # accounts.email index → 500. redirect halts the callback so we never
          # reach create_omniauth_identity or omniauth_create_account. The
          # domain-validation hook below also runs only on the CREATE path, so
          # the email-link path would bypass it entirely.
          #
          # FOLLOW-UP: no authenticated "link SSO from account settings" flow
          # exists yet, so this strands users who created a password account
          # first and expect SSO to match by email. Ship a companion linking UI.
          Auth::Logging.log_auth_event(
            :omniauth_link_refused_existing_account,
            level: :warn,
            email: OT::Utils.obscure_email(normalized_email),
            provider: omniauth_provider,
          )
          set_redirect_error_flash 'An account with this email already exists. ' \
                                   'Sign in with your existing method, then link SSO from account settings.'
          redirect '/signin?auth_error=account_exists_link_required'
        end

        # Genuinely new email → allow JIT create (subject to the domain checks
        # in before_omniauth_create_account below).
        nil
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

      # NOTE: before_omniauth_callback_route is OWNED by omniauth_tenant.rb
      # (hooks don't chain; a second definition here would be clobbered — or
      # worse, clobber the tenant validation). The :omniauth_callback_start
      # logging that used to live here moved into that hook.

      # ========================================================================
      # HOOK: Before OmniAuth Account Creation - Domain Validation
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires BEFORE Rodauth creates a new account for an SSO user.
      # Used to enforce domain restrictions for SSO signups.
      #
      # RESOLUTION ORDER:
      # 1. Per-domain SignupConfig (if custom domain and config enabled)
      # 2. Global allowed_signup_domains config (fallback)
      #
      # CONFIGURATION:
      # Per-domain: Configure via CustomDomain::SignupConfig
      # Global: Set via ALLOWED_SIGNUP_DOMAIN environment variable (comma-separated)
      #
      auth.before_omniauth_create_account do
        email       = omniauth_email.to_s.strip.downcase
        email_parts = email.split('@')

        # Reject unusable emails from IdP (distinct from policy rejection): a
        # missing/empty claim, or one without both a local part and a domain.
        # Redirect with a stable error code so Login.vue can show a localized
        # message — matches the email_auth/omniauth_on_failure convention.
        # Inline JSON via throw_error_status was clobbered by omniauth_on_failure,
        # collapsing the specific code into the generic sso_failed. Failing here
        # (rather than letting a blank local part like "@example.com" fall
        # through to account creation, which 500s on the PG valid_email CHECK)
        # keeps the user on a localized error instead of a frozen screen (#3478).
        if email_parts.length != 2 || email_parts.first.to_s.empty? || email_parts.last.to_s.empty?
          Auth::Logging.log_auth_event(
            :omniauth_invalid_email,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            provider: omniauth_provider,
          )
          redirect '/signin?auth_error=invalid_email'
        end

        # Get display_domain from DomainStrategy middleware (already in env)
        display_domain = request.env['onetime.display_domain']

        # Use shared validation module for per-domain + global fallback
        unless Onetime::SignupValidation.valid_signup_email?(email, display_domain: display_domain)
          Auth::Logging.log_auth_event(
            :omniauth_domain_rejected,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            domain: email_parts.last,
            display_domain: display_domain,
            provider: omniauth_provider,
          )
          # Generic error code — don't reveal which domains are allowed.
          redirect '/signin?auth_error=domain_not_allowed'
        end

        Auth::Logging.log_auth_event(
          :omniauth_domain_validated,
          level: :debug,
          email: OT::Utils.obscure_email(email),
          display_domain: display_domain,
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

        # Capture the signup domain so it can be set on the new Customer in a
        # single write (instead of save-then-update). Lookup is cheap and pure;
        # leave it outside safe_execute so failures still surface.
        display_domain   = request.env['onetime.display_domain']
        custom_domain    = display_domain ? Onetime::CustomDomain.load_by_display_domain(display_domain) : nil
        signup_domain_id = custom_domain&.identifier

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
            provisioning_origin: 'sso_jit',
            signup_domain_id: signup_domain_id,
          ).call
        end

        # Organization assignment for new SSO accounts.
        #
        # MUTUALLY EXCLUSIVE paths — tenant SSO users join the tenant org,
        # canonical SSO users get a default workspace. Never both.
        #
        # Consuming domain_id via session.delete ensures after_login sees nil
        # and skips for new accounts — preventing a redundant idempotent call.
        if customer.is_a?(Onetime::Customer)
          domain_id = session.delete(:validated_omniauth_domain_id)

          if domain_id
            # Tenant domain SSO → join the domain's organization only
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

            # IMPORTANT: Do NOT create a fallback workspace here.
            #
            # If JoinDomainOrganization failed, the user authenticated via
            # tenant-domain SSO to join a *specific* organization. Creating
            # an unrelated personal workspace would:
            #   1. Leave them outside the org they intended to join
            #   2. Give them a full account with no org affiliation
            #   3. Bury the join failure — no one investigates
            #
            # The correct response is to fail visibly so the org admin
            # and ops can diagnose why the join didn't stick.
            if customer.organization_instances.to_a.empty?
              OT.le '[omniauth] CRITICAL: Tenant SSO join produced no org membership ' \
                    "for #{customer.external_identifier} (domain_id=#{domain_id}). Orphaned account — admin must investigate."
              redirect '/signin?auth_error=org_join_failed'
            end
          else
            # Canonical domain SSO → create default workspace
            Onetime::ErrorHandler.safe_execute(
              'create_default_workspace_omniauth',
              extid: customer.extid,
            ) do
              Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
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
