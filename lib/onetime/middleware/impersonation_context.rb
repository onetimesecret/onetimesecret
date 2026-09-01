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
    # `GET /api/v2/secret/:id` and `GET /api/v3/secret/:id` CONSUME the secret
    # when called with `continue=true` (V2::Logic::Secrets::ShowSecret gates
    # the reveal on that param, not on the HTTP method). Burn-after-reading is
    # irreversible and would destroy a customer's secret during a support
    # session. Safe-method-ness is therefore not sufficient on its own: a
    # reveal-intent query param is treated as the mutation it is. Only the
    # QUERY STRING is inspected (Rack::Request#GET), so this never touches the
    # request body.
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

      SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

      # Denied regardless of method. Matched as exact path or path prefix on
      # the NORMALIZED full path — never substring, never regex.
      BLOCKED_PREFIXES = %w[/api/auth /auth /api/colonel /colonel].freeze

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

          return denial_response(env) unless permitted?(env)
        end

        @app.call(env)
      ensure
        Onetime::SessionImpersonation.clear_context
      end

      private

      # The positive list. Anything this does not affirm is denied.
      def permitted?(env)
        path = request_path(env)
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
      def request_path(env)
        Otto::Utils.normalize_path("#{env['SCRIPT_NAME']}#{env['PATH_INFO']}")
      rescue StandardError
        # An unparseable path is judged as blocked: deny is the safe direction
        # for a read-only overlay.
        '/'
      end

      def blocked_path?(path)
        BLOCKED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
      end

      # Query-string only — Rack::Request#GET never reads the body, so this
      # cannot consume a stream a downstream parser still needs. Mirrors the
      # logic's own `params['continue'].to_s == 'true'` test.
      def reveal_intent?(env)
        Rack::Request.new(env).GET[REVEAL_INTENT_PARAM].to_s == 'true'
      rescue StandardError
        # A query string too broken to parse is also too broken to prove
        # innocent.
        true
      end

      def denial_response(env)
        if html_request?(env)
          [403, { 'content-type' => 'text/html; charset=utf-8' }, [html_body]]
        else
          [403, { 'content-type' => 'application/json' }, [json_body]]
        end
      end

      # A page navigation (browser Accept) that is not an API path gets HTML;
      # everything else gets the JSON contract.
      def html_request?(env)
        return false if request_path(env).start_with?('/api/')

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
