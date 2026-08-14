# apps/web/core/controllers/base.rb
#
# frozen_string_literal: true

require_relative '../views'
require 'onetime/helpers/session_helpers'
require 'onetime/helpers/homepage_mode_helpers'
require 'onetime/controllers/organization_context'
require 'onetime/logic/signup_config_resolution'

module Core
  module Controllers
    module Base
      include Onetime::LoggerMethods
      include Onetime::Helpers::SessionHelpers
      include Onetime::Helpers::HomepageModeHelpers
      include Onetime::Controllers::OrganizationContext
      include Onetime::Logic::SignupConfigResolution

      attr_reader :req, :res, :locale

      def initialize(req, res)
        @req    = req
        @res    = res
        @locale = req.locale
      end

      def index
        # Determine homepage mode based on CIDR/header before rendering
        # This sets a flag in the request env that the view layer can serialize
        req.env['onetime.homepage_mode'] = determine_homepage_mode

        # Simplified: BaseView now extracts everything from req
        view     = Core::Views::VuePoint.new(req)
        res.body = view.render
      end

      # Access the current customer from Otto auth middleware or session
      def cust
        @cust ||= load_current_customer
      end

      # Access the current session
      def session
        req.env['rack.session']
      end

      # Validates a given URL and ensures it can be safely redirected to.
      #
      # @param url [String] the URL to validate
      # @return [URI::HTTP, nil] the validated URI object if valid, otherwise nil
      def validate_url(url)
        # This is named validate_url and not validate_uri because we aim to return
        # an appropriate value that can be safely redirected to. A path or other portion
        # of a URI can't be properly validated whereas a complete URL describes a
        # specific location to attempt to navigate to.
        return nil if url.nil? || url.to_s.strip.empty?

        uri = nil
        begin
          # Attempt to parse the URL
          uri = URI.parse(url)
        rescue URI::InvalidURIError => ex
          # Log an error message if the URL is invalid
          http_logger.error 'Invalid URI in URL validation',
            {
              exception: ex,
              url: url,
            }
        else
          # Set a default host if the host is missing
          uri.host ||= OT.conf['site']['host']
          # Ensure the scheme is HTTPS if SSL is enabled in the configuration
          if (OT.conf.dig('site', 'ssl') != false) && (uri.scheme.nil? || uri.scheme != 'https')
            uri.scheme = 'https'
          end
          # Set uri to nil if it is not an HTTP or HTTPS URI
          uri        = nil unless uri.is_a?(URI::HTTP)
          # Log an info message with the validated URI
          OT.info "[validate_url] Validated URI: #{uri}"
        end

        # Return the validated URI or nil if invalid
        uri
      end

      def not_found
        not_found_response ''
      end

      def server_error(status = 500, _message = nil)
        res.status          = status
        res['content-type'] = 'text/html'
        res.body            = <<-HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>500 Internal Server Error</title>
        </head>
        <body>
            <h1>500 - Internal Server Error</h1>
            <p>Something went wrong on our end. Please try again later.</p>
        </body>
        </html>
        HTML
      end

      # Handles requests for routes that don't match any defined server-side
      # routes. Instead of returning a 404 status, it serves the entrypoint
      # HTML for the Vue.js SPA.
      #
      # @param message [String, nil] An optional error message to be added to the view.
      #
      # @return [void]
      #
      # This method follows the best practice for serving Single Page Applications:
      # 1. It serves the same entrypoint HTML for all non-API routes.
      # 2. It allows the Vue.js router to handle client-side routing and 404 logic.
      #
      # Rationale:
      # - Enables deep linking and direct access to any SPA route.
      # - Supports client-side routing without server knowledge of Vue.js routes.
      # - Simplifies server configuration and maintenance.
      # - Allows for proper handling of 404s within the Vue.js application.
      def not_found_response(message, **)
        # Simplified: BaseView now extracts everything from req
        view       = Core::Views::VuePoint.new(req)
        view.add_error(message) unless message && message.empty?
        res.status = 404
        res.body   = view.render  # Render the entrypoint HTML
      end

      # JSON response helpers
      #
      # These methods return Hash objects that will be serialized by Otto's JSONHandler
      # when the route has response=json. Do not manually set res.body for JSON responses.

      def json_response(data, status: 200)
        res.status = status
        data
      end

      def json_success(message, status: 200)
        json_response({ success: message }, status: status)
      end

      def json_error(message, field_error: nil, status: 400)
        body                = { error: message }
        body['field-error'] = field_error if field_error
        json_response(body, status: status)
      end

      protected

      # Runtime gate for POST /signin.
      #
      # Custom domains default OFF: sign-in is closed unless the domain owner
      # explicitly opted in via an enabled SigninConfig (same resolution as the
      # branded masthead's Sign In link — link and route stay in lockstep, so a
      # domain that hides the link cannot still accept credentials at /signin).
      # Canonical / subdomain requests follow the global default (ADR-024
      # invariant #2). Either way the global kill switch (AUTH_ENABLED /
      # AUTH_SIGNIN) always wins: a per-domain config can only narrow. SSO login
      # is unaffected — it runs through the omniauth routes, gated separately by
      # SsoConfig. Keep in lockstep with ConfigSerializer#resolve_signin.
      #
      # The branch is chosen by SigninConfig.resolve_signin_enabled_for_request,
      # NOT by custom_domain_request?, so operator defaults require a positive
      # :canonical/:subdomain classification
      # (ADR-024#operator-defaults-require-positive-classification). domain_id
      # is omitted:
      # this is the password/email POST gate, which never inherits the display
      # SSO carve-out.
      def signin_enabled?
        global = Onetime::CustomDomain::SigninConfig.global_signin_enabled(auth_settings)
        Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_request(
          global,
          domain_signin_config,
          domain_strategy: req.env['onetime.domain_strategy'],
        )
      end

      # Runtime gate for `restrict_to` on the SIMPLE-MODE auth routes
      # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
      # / #reject-as-not-found-not-forbidden, #4139).
      #
      # In simple mode POST /auth/login is served HERE, by Core, not by Rodauth
      # (apps/web/core/routes.txt) — so the before_rodauth gate in
      # apps/web/auth/config/hooks/restrict_to.rb never runs for it. Without
      # this method enforcement would be mode-dependent: present in full mode,
      # absent in simple.
      #
      # Resolution is NOT re-derived here (ADR-034#resolution-is-model-owned): this gathers the two
      # inputs and asks SigninConfig.resolve_restrict_to, same as the display
      # gate (ConfigSerializer) and the full-mode route gate.
      #
      # The global input is normally nil in simple mode — AuthConfig#restrict_to
      # returns nil unless full_enabled? — so what this actually enforces is a
      # per-domain restriction on a custom domain that has opted into sign-in.
      # It is written against the resolver rather than that special case so the
      # global half starts working the moment AuthConfig grants it meaning.
      #
      # UNREADABLE POLICY IS NOT "ALLOWED" (#4139). The custom-domain identity,
      # its SigninConfig and the SSO availability probe are datastore reads, so
      # this gate can fail to learn what the host permits. It answers that the
      # same way the full-mode gate does — SigninConfig.resolve_lookup_failure,
      # which fails closed on a custom host (Onetime::SigninPolicyUnavailable →
      # 503 via otto_hooks) and keeps enforcing the still-known global
      # elsewhere. Before this the error propagated as an unhandled 500:
      # fail-closed by crash, which is the right direction with the wrong shape
      # and no shared rule behind it.
      #
      # @param method_name [String, Symbol] one of SigninConfig::RESTRICT_TO_VALUES
      # @raise [Onetime::SigninPolicyUnavailable] on an unreadable custom-host policy
      # @return [Boolean] false when this host restricts the method away
      def restrict_to_allows?(method_name)
        global        = Onetime.auth_config.restrict_to
        signin_config = domain_signin_config

        # A3's runtime-availability half is applied BY THE RESOLVER, not here.
        # This used to guard `return false if global && !restrict_to_available?`
        # ahead of resolution, which was wrong in one case: a DOMAIN-only
        # restriction went dark whenever the unrelated global method was dead.
        # Passing the flag in lets the resolver narrow only what the global half
        # actually governs. Four consumers each remembering this rule is the
        # drift A2 exists to kill — hence restriction_available_for_request?,
        # which is the one place that rule lives (#4139). It also narrows an
        # INHERITED global restriction through the custom host's own
        # capabilities, so this gate cannot accept a method the full-mode gate
        # and the /signin page both treat as dark.
        Onetime::CustomDomain::SigninConfig
          .resolve_restrict_to(
            global,
            signin_config,
            available: Onetime::CustomDomain::SigninConfig.restriction_available_for_request?(
              global,
              signin_config,
              domain_id: custom_domain_id,
              custom_host: custom_domain_request?,
            ),
          )
          .allows?(method_name)
      rescue Redis::BaseError => ex
        # Not covered by the read guards below: the availability half probes
        # SSO config for an inherited restriction. Same rule, same shape —
        # this raises on any host that could have a per-domain policy, and
        # falls through to the global-only resolution on an operator host.
        signin_policy_read_failed!(ex)
        Onetime::CustomDomain::SigninConfig
          .resolve_lookup_failure(domain_strategy: req.env['onetime.domain_strategy'])
          .allows?(method_name)
      end

      # Runtime gate for POST /signup. Same custom-domain-default-OFF / opt-in
      # polarity as signin_enabled?: a custom domain never accepts account
      # creation unless an enabled SignupConfig opts in, while canonical /
      # subdomain requests follow the global default. The global kill switch
      # (AUTH_ENABLED / AUTH_SIGNUP) always wins. Branch chosen positively by
      # the request resolver, same rule as signin_enabled?.
      # ADR-024#operator-defaults-require-positive-classification
      #
      # UNREADABLE POLICY IS NOT "FOLLOW THE GLOBAL" (#4157). domain_signup_config
      # is two datastore reads (CustomDomain identity, then SignupConfig), so
      # this gate can fail to learn whether the tenant opted in. Both reads are
      # guarded inside Onetime::Logic::SignupConfigResolution, which fails
      # closed via SignupConfig.resolve_lookup_failure — Onetime::SignupPolicyUnavailable
      # → 503 on any host not positively an operator host, nil (the only answer
      # such a host could have had) on canonical/subdomain. Before that, a blip
      # produced an unhandled 500 here at best and, on the :invalid
      # misclassification the same blip causes, the operator's global sign-up
      # default at worst. Mirrors signin_policy_read_failed! exactly.
      #
      # @raise [Onetime::SignupPolicyUnavailable] on an unreadable custom-host policy
      def signup_enabled?
        global = Onetime::CustomDomain::SignupConfig.global_signup_enabled(auth_settings)
        Onetime::CustomDomain::SignupConfig.resolve_signup_enabled_for_request(
          global,
          domain_signup_config,
          domain_strategy: req.env['onetime.domain_strategy'],
        )
      end

      private

      # True when the current request is served on a customer's custom domain
      # (as classified by Onetime::Middleware::DomainStrategy). Canonical and
      # subdomain requests are the operator's own surfaces and follow the global
      # auth defaults; custom domains must opt in. Mirrors
      # ConfigSerializer#tenant_domain?.
      #
      # NO LONGER DECIDES AUTH POLARITY
      # (ADR-024#identity-predicates-are-not-auth-gates). It used to pick the
      # branch for signin_enabled? and signup_enabled?, and its false branch is
      # wider than "not a custom domain": :invalid and nil land there too, and
      # :invalid is also what DomainStrategy answers when its
      # `known_custom_domain?` datastore read RAISES — so a blip handed a real
      # customer domain the operator's global auth default. Those two gates now
      # ask SigninConfig.operator_host? through the request resolvers, which
      # require POSITIVE evidence of an operator host.
      #
      # This predicate stays a `== :custom` identity test and is NOT flipped:
      # its remaining consumers govern branding, tenant treatment and the
      # restrict_to custom-host narrowing, none of which a genuinely unplaceable
      # host should receive. See Onetime::Middleware::DomainStrategy's class doc
      # for the full consumer table.
      def custom_domain_request?
        req.env['onetime.domain_strategy'] == :custom
      end

      def auth_settings
        OT.conf.dig('site', 'authentication')
      end

      def signup_config_display_domain
        req.env['onetime.display_domain']
      end

      # Classification hook for Onetime::Logic::SignupConfigResolution's
      # read-failure path (#4157), so an unreadable tenant sign-up policy fails
      # closed on exactly the hosts the sign-in side fails closed on — the
      # mixin's default is nil, which would 503 the canonical sign-up page
      # during a blip that costs it nothing.
      def signup_config_domain_strategy
        req.env['onetime.domain_strategy']
      end

      def signup_config_auth_setting(key)
        auth_settings[key]
      end

      # CustomDomain identifier for the request host, or nil.
      #
      # Read separately from the SigninConfig rather than off it, because the
      # restrict_to gate needs it precisely when there is NO config: an
      # inherited global restriction is narrowed by the host's own capabilities
      # either way, and `config&.domain_id` is nil in exactly that case (#4139).
      # Memoized — two gates ask per request.
      #
      # Uses from_display_domain, NOT load_by_display_domain (#4157): the
      # latter rescues Redis::BaseError (and a blanket StandardError) internally
      # and returns nil, which made the rescue below dead code and let a
      # datastore blip on a tenant host read as "no SigninConfig" → operator
      # global default. That is the widen ADR-024 closes. This is also the
      # lookup the sign-up half already uses, so both policy reads now resolve
      # tenant identity through one non-swallowing path.
      def custom_domain_id
        return @custom_domain_id if defined?(@custom_domain_id)

        display_domain    = req.env['onetime.display_domain']
        @custom_domain_id = display_domain &&
                            Onetime::CustomDomain.from_display_domain(display_domain)&.identifier
      rescue Redis::BaseError => ex
        signin_policy_read_failed!(ex)
      end

      def domain_signin_config
        return unless custom_domain_id

        Onetime::CustomDomain::SigninConfig.find_by_domain_id(custom_domain_id)
      rescue Redis::BaseError => ex
        signin_policy_read_failed!(ex)
      end

      # The two datastore reads that back the per-domain sign-in policy failed
      # (#4139). Guarded at the READ, not at each gate, because signin_enabled?
      # runs before restrict_to_allows? and asks for the same config — a rescue
      # in the gate alone leaves the earlier read crashing as an unhandled 500,
      # which is fail-closed with the wrong shape (see
      # Onetime::SigninPolicyUnavailable).
      #
      # Returns nil only for the operator's OWN hosts, which have no per-domain
      # config to consult in the first place — the read could only ever have
      # produced nil there, and their global policy is in-memory and still
      # fully known. Every other host fails closed, including one classified
      # :invalid: that is what DomainStrategy answers for a host it could not
      # place, which is exactly what a failing domain-index read produces for a
      # real custom domain. SigninConfig.operator_host? owns the test so this
      # gate and the full-mode one carve out the same hosts.
      #
      # @raise [Onetime::SigninPolicyUnavailable] on any non-operator host
      # @return [nil] on an operator host
      def signin_policy_read_failed!(exception)
        http_logger.error 'Sign-in policy lookup failed',
          {
            host: req.env['onetime.display_domain'],
            exception: exception,
          }
        strategy = req.env['onetime.domain_strategy']
        raise Onetime::SigninPolicyUnavailable unless Onetime::CustomDomain::SigninConfig.operator_host?(strategy)

        nil
      end

      # Returns the StrategyResult created by Otto's RouteAuthWrapper
      #
      # This provides authenticated state and metadata from the auth strategy
      # that executed for the current route (noauth, sessionauth, basicauth, etc.)
      #
      # RouteAuthWrapper (post-routing authentication) executes the strategy and sets
      # req.env['otto.strategy_result'] before the controller handler runs.
      #
      # @return [Otto::Security::Authentication::StrategyResult]
      def strategy_result
        req.env['otto.strategy_result']
      end

      def load_current_customer
        # Use Rack::Request extension method (delegates to strategy_result.user)
        user = req.user
        return user if user.is_a?(Onetime::Customer)

        # Anonymous - return nil
        nil
      rescue StandardError => ex
        http_logger.error 'Failed to load customer',
          {
            exception: ex,
          }
        nil # Error recovery - treat as anonymous
      end

      # session_auth_enforced? is inherited from SessionHelpers (included
      # at the top of this module). It uses safe `dig` access and defaults
      # to disabled when config is absent — account features are rendered
      # unavailable unless authentication is explicitly configured.
      # See lib/onetime/helpers/session_helpers.rb.

      # Checks if the request accepts JSON responses
      #
      # @return [Boolean] True if the Accept header includes application/json
      def json_requested?
        req.env['HTTP_ACCEPT']&.include?('application/json')
      end

      # Executes logic with standardized error handling for both JSON and HTML responses
      #
      # @param logic [Object] Logic object to execute
      # @param success_message [String] Success message for JSON responses
      # @param success_redirect [String] Path to redirect on success (HTML)
      # @param error_redirect [String, nil] Path to redirect on error (HTML), nil to re-raise
      # @yield Optional block for additional processing after logic.process
      # @return [Hash, nil] JSON response Hash for routes with response=json, nil otherwise
      def execute_with_error_handling(logic, success_message:, success_redirect: '/', error_redirect: nil, error_status: 400)
        logic.raise_concerns
        logic.process
        yield if block_given?

        if json_requested?
          json_success(success_message)
        else
          res.redirect success_redirect
          nil
        end
      rescue OT::FormError => ex
        handle_form_error(ex, error_redirect, status: error_status)
      end

      # Handles form errors with appropriate JSON or HTML response
      #
      # @param ex [OT::FormError] The form error exception
      # @param redirect_path [String, nil] Path to redirect for HTML, nil to re-raise
      # @param field [String, nil] Field name for error, nil to infer from message
      # @return [Hash, nil] JSON error Hash for routes with response=json, nil otherwise
      def handle_form_error(ex, redirect_path = nil, field: nil, status: 400)
        # We pass the message here and not the exception itelf b/c SemanticLogger
        # automatically outputs backtrace when it receives one.
        http_logger.error 'Form error occurred',
          {
            message: ex.message,
            field: field || ex.field,
            error_type: ex.error_type,
            redirect_path: redirect_path,
          }
        if json_requested?
          # FormError must provide field and error_type
          field    ||= ex.field
          error_type = ex.error_type || ex.message.downcase

          json_error(ex.message, field_error: [field, error_type], status: status)
        elsif redirect_path
          session['error_message'] = ex.message
          res.redirect redirect_path
          nil
        else
          raise
        end
      end

      # Sentry error tracking
      #
      # Available levels are :fatal, :error, :warning, :log, :info, and :debug.
      # The Sentry default, if not specified, is :error.
      def capture_error(error, level = :error, &)
        http_logger.debug '[sentry] controller capture_error → decision',
          {
            exception_class: error.class.name,
            level: level,
            d9s_enabled: OT.d9s_enabled,
            sentry_defined: defined?(Sentry) ? true : false,
            sentry_initialized: (defined?(Sentry) && Sentry.initialized?) || false,
          }
        unless OT.d9s_enabled
          http_logger.debug '[sentry] controller capture_error skipped — d9s_enabled=false'
          return
        end

        begin
          if defined?(req) && req.respond_to?(:env)
            headers = Onetime::ErrorHandler.http_headers_from(req.env)
            http_logger.debug 'Capturing error to Sentry with request headers',
              {
                headers: headers,
              }
          end

          event_id = Sentry.capture_exception(error, level: level, &)
          http_logger.debug '[sentry] controller capture_error returned',
            {
              event_id: event_id,
              exception_class: error.class.name,
            }
        rescue NoMethodError => ex
          raise unless ex.message.include?('start_with?')

          http_logger.error 'Sentry capture error (NoMethodError)',
            {
              exception: ex,
            }
        rescue StandardError => ex
          http_logger.error 'Sentry capture error',
            {
              exception: ex,
            }
        end
      end

      def capture_message(message, level = :log, &)
        return unless OT.d9s_enabled

        Sentry.capture_message(message, level: level, &)
      rescue StandardError => ex
        http_logger.error 'Sentry capture_message error',
          {
            exception: ex,
            message: message,
          }
      end
    end
  end
end
