# lib/onetime/middleware/impersonation_context.rb
#
# frozen_string_literal: true

require 'json'
require 'rack/request'
require 'otto/utils'

require_relative '../session/impersonation'

module Onetime
  module Middleware
    # Impersonation Context + read-only guard.
    #
    # Two jobs, in this order, once per request:
    #
    #   1. CONTEXT. Read the session marker once (expiring it if it is past
    #      `expires_at`, which audits `ended_by: 'expired'`) and publish it as
    #      a Fiber-local so the bootstrap serializer renders the banner from
    #      the SAME marker that decided the identity actually served. Cleared
    #      in `ensure`, like Middleware::EntitlementPreviewContext.
    #
    #   2. CAPABILITY RESTRICTION AT POINT OF USE. An impersonated session is
    #      READ-ONLY. This is a POSITIVE LIST — the request must be affirmed,
    #      not merely fail to match a denylist:
    #
    #        - the stop endpoint is always allowed (it must be reachable from
    #          inside the very state it ends);
    #        - {BLOCKED_PREFIXES} are denied regardless of method;
    #        - otherwise only {SAFE_METHODS} pass;
    #        - and a safe method carrying REVEAL INTENT is still denied (see
    #          below).
    #
    # ## Why the blocked prefixes are blocked
    #
    # `/auth/*` and `/api/auth/*`: Rodauth's `account_id` in the session is
    # still the COLONEL's — the overlay is an app-layer identity, not an auth
    # DB one. "Change password" there would change the OPERATOR's password
    # while the UI says they are someone else. This is the sharpest edge in
    # the whole feature.
    #
    # `/colonel*` and `/api/colonel/*`: no admin powers while presenting as a
    # non-admin. The effective-customer role check would 403 these anyway
    # (Onetime::SessionImpersonation.resolve makes the TARGET the strategy's
    # user), so this is defense-in-depth — but it is also the difference
    # between "403 for a reason we can point at" and "403 by accident".
    #
    # ## Why a GET can still be a mutation here
    #
    # `GET /api/v{2,3}/secret/:id` (and the `/guest/` twins) CONSUME the secret
    # when the request carries `continue=true`: V2::Logic::Secrets::ShowSecret
    # gates burn-after-reading on that PARAM, not on the HTTP method. So these
    # paths are denied OUTRIGHT — by path, before the safe-method rule — rather
    # than by sniffing for the param.
    #
    # Param-sniffing alone is not a control here, and that is worth spelling
    # out because the first cut of this guard tried it. `continue` does not
    # have to be in the query string: Rack::Parser (mounted ABOVE this
    # middleware) parses ANY request whose Content-Type matches, method
    # included, and publishes the result as `rack.request.form_hash` — which
    # `Rack::Request#POST` then returns even for a GET. So
    # `GET /api/v3/secret/<id>` with `Content-Type: application/json` and body
    # `{"continue":true}` reaches the handler with `params['continue'] == true`
    # while its query string is empty. A query-string-only check waves that
    # through and the secret is gone.
    #
    # The `continue` check survives as belt-and-braces for any FUTURE
    # reveal-intent route the path list has not caught up with, and it now
    # reads the union of query and body params so it cannot be dodged the same
    # way twice.
    #
    # `/secret/:id/status` is deliberately NOT in the deny set: it was made a
    # pure read in #3633 and the receipt timeline records the access.
    #
    # ## Why GETs that mint EXTERNAL artifacts are denied
    #
    # Read-only is about effects on the world, not about the datastore. A
    # handful of GETs create things outside this app on behalf of whoever is
    # authenticated — a Stripe Checkout Session or Customer Portal session
    # bound to the TARGET's Stripe customer, a DNS-provider widget token — and
    # `GET /billing/portal` additionally CREATES a default Organization for the
    # target as a side effect of being visited. `GET /billing/api/org/:extid/
    # subscription` consumes the target's pending plan intent (#4306), which is
    # a one-shot the operator would silently burn. All denied.
    #
    # Must be mounted after the session middleware (reads env['rack.session']).
    class ImpersonationContext
      # Machine-readable code the frontend keys off. Stable API.
      ERROR_CODE = 'impersonation_read_only'

      # HUMAN-readable, and it goes in the `error` field — not the code. The
      # SPA's error classifier (src/schemas/errors/classifier.ts
      # #extractUserMessage) reads `details.error` verbatim as the toast text,
      # so putting the token there would surface "impersonation_read_only" to
      # the operator. The token travels in `error_code` instead.
      ERROR_MESSAGE = 'This session is impersonating a customer and is read-only. ' \
                      'Stop impersonating to make changes.'

      # OPTIONS is deliberately NOT safe. Otto dispatches OPTIONS rows to real
      # handlers — `OPTIONS /secret/generate` runs GenerateSecret, which
      # CREATES a secret — so treating the verb as inert would hand the guard's
      # biggest hole straight back. Nothing legitimate is lost: a CORS preflight
      # is sent without cookies, so it carries no session and never reaches an
      # impersonated one.
      SAFE_METHODS = %w[GET HEAD].freeze

      # Denied regardless of method, as an exact path OR a descendant. Matched
      # on the NORMALIZED full path — never substring, never regex.
      BLOCKED_PREFIXES = %w[
        /api/auth
        /auth
        /api/colonel
        /colonel
        /billing/portal
        /billing/welcome
        /account/billing_portal
        /api/domains/dns-widget/token
      ].freeze

      # Denied only BELOW these paths. The path itself is a harmless SPA page
      # (`/billing/plans` is Page#index) while its children are the checkout
      # entry points (`/billing/plans/:product/:interval`, `/plans/:tier`).
      BLOCKED_SUBTREES = %w[/billing/plans /plans].freeze

      # Denied regardless of method, where a prefix would be too blunt.
      BLOCKED_PATTERNS = [
        # Consuming secret reads: exactly ONE segment after `secret/`, so
        # `/secret/:id/status` (a pure read since #3633) stays reachable.
        %r{\A/api/v[23](?:/guest)?/secret/[^/]+\z},
        # Consumes the target's one-shot pending plan intent (#4306). The
        # sibling reads (`/api/org/:extid`, `.../invoices`) stay allowed.
        %r{\A/billing/api/org/[^/]+/subscription\z},
      ].freeze

      # The one endpoint that must work from inside an impersonation.
      # Customer-facing on purpose: it carries no `role=` requirement and sits
      # outside /api/colonel, so AdminNetworkIsolation and the (now
      # target-shaped) role check cannot strand the operator.
      #
      # This value is duplicated in src/services/impersonation.service.ts
      # (IMPERSONATION_STOP_PATH) and declared in apps/api/account/routes.txt.
      # All three must agree exactly — a rename here without the other two
      # makes the stop button unpressable from inside the state it ends.
      STOP_PATH = '/api/account/impersonation/stop'

      # Param that turns a secret GET into a burn-after-reading consumption.
      REVEAL_INTENT_PARAM = 'continue'

      def initialize(app)
        @app = app
      end

      def call(env)
        # Defensive: state leaked by a previous request on this fiber must not
        # bleed into this one.
        Onetime::SessionImpersonation.clear_context

        session = env['rack.session']
        marker  = Onetime::SessionImpersonation.active(session)

        if marker
          Onetime::SessionImpersonation.set_context(
            marker,
            impersonator_extid: session['external_id'],
          )

          # One target load for the whole request: every identity call site
          # downstream reads this memo (see TARGET_ENV_KEY).
          Onetime::SessionImpersonation.preload_target(env, marker)

          # Normalized ONCE per request: it is the input to both the
          # verdict and the denial's content negotiation, and re-deriving it
          # would double the work and double the failure log line.
          path = request_path(env)

          return denial_response(env, path) unless permitted?(env, path)
        end

        @app.call(env)
      ensure
        Onetime::SessionImpersonation.clear_context
      end

      private

      # The positive list. Anything this does not affirm is denied — including
      # a request whose path could not be normalized (path is nil).
      def permitted?(env, path)
        return false if path.nil?
        return true if path == STOP_PATH
        return false if blocked_path?(path)
        return false unless SAFE_METHODS.include?(env['REQUEST_METHOD'])

        !reveal_intent?(env)
      end

      # The universal stack runs INSIDE Rack::URLMap, so PATH_INFO is
      # mount-relative (`SCRIPT_NAME='/api/v2'` + `PATH_INFO='/status'`).
      # Rejoining and normalizing is what lets one flat list of external paths
      # match every app — and normalization is security-load-bearing, since the
      # router dispatches on the normalized form and would otherwise serve
      # `/%63olonel` past a raw-string check.
      # @return [String, nil] the normalized full path, or nil when it could
      #   not be normalized. nil is a DENY signal, not a default path: an
      #   earlier version returned '/' here, which is not on any deny list and
      #   therefore let an unparseable path through as an ordinary page read.
      def request_path(env)
        Otto::Utils.normalize_path("#{env['SCRIPT_NAME']}#{env['PATH_INFO']}")
      rescue StandardError => ex
        OT.le "[impersonation] path normalization failed, denying: #{ex.class}: #{ex.message}"
        nil
      end

      def blocked_path?(path)
        return true if BLOCKED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
        return true if BLOCKED_SUBTREES.any? { |prefix| path.start_with?("#{prefix}/") }

        BLOCKED_PATTERNS.any? { |pattern| pattern.match?(path) }
      end

      # Belt-and-braces behind the path deny list, for a reveal-intent route
      # that list has not caught up with.
      #
      # Reads the UNION of query and body params, mirroring what the handler
      # itself sees (`Rack::Request#params`) rather than just the query string
      # — see the class doc for the JSON-body-on-GET bypass that makes the
      # difference. #POST is safe to call: Rack::Parser has already parsed and
      # rewound the body and memoized `rack.request.form_hash`, so this
      # consumes no stream a downstream reader still needs.
      def reveal_intent?(env)
        request = Rack::Request.new(env)
        params  = request.GET.merge(request.POST)

        params[REVEAL_INTENT_PARAM].to_s == 'true'
      rescue StandardError
        # Params too broken to parse are too broken to prove innocent.
        true
      end

      def denial_response(env, path)
        if html_request?(env, path)
          [403, { 'content-type' => 'text/html; charset=utf-8' }, [html_body]]
        else
          [403, { 'content-type' => 'application/json' }, [json_body]]
        end
      end

      # A page navigation (browser Accept) that is not an API path gets HTML;
      # everything else gets the JSON contract.
      def html_request?(env, path)
        # nil path => denied for a reason we cannot describe; answer JSON, the
        # machine-readable form, rather than raising inside the denial itself.
        return false if path.nil? || path.start_with?('/api/')

        env['HTTP_ACCEPT'].to_s.include?('text/html')
      end

      def json_body
        JSON.generate(error: ERROR_MESSAGE, error_code: ERROR_CODE)
      end

      def html_body
        <<~HTML
          <!DOCTYPE html>
          <html lang="en"><head><meta charset="utf-8">
          <title>Read-only session</title></head>
          <body><h1>Read-only session</h1>
          <p>#{ERROR_MESSAGE}</p>
          </body></html>
        HTML
      end
    end
  end
end
