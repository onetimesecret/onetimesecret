# spec/support/auth_route_failure_codes.rb
#
# frozen_string_literal: true

# The declared authentication requirement and failure codes of every auth and
# account route (#4469, acceptance criterion 2), and the parsers that read the
# live route inventories the declaration is checked against.
#
# Three inventories, three sources of truth:
#
#   1. Otto route tables (`apps/**/routes.txt`). The `auth=` option on each
#      row IS the declared requirement; Otto::RouteDefinition parses it here
#      exactly as the router does. The codes follow from the strategies in
#      the chain (STRATEGY_CODES), except where a handler answers a
#      credential refusal itself (HANDLER_CODES) or a row carries no `auth=`
#      and is anonymous by Otto's default (ANONYMOUS_OTTO_ROUTES, each with
#      its reason).
#   2. Rodauth routes. Rodauth freezes `route_hash` in post_configure, so the
#      full-mode integration spec reads the LIVE mounted set
#      (spec/integration/full/auth_route_failure_code_coverage_spec.rb) and
#      the unit spec reads the route universe the two existing gates
#      maintain (Auth::SigninGate, Auth::RestrictTo), which their own specs
#      check against the same route_hash. Both fail on a route absent from
#      RODAUTH_ROUTES (ADR-038#classify-exhaustively-or-fail).
#   3. The Roda routes apps/web/auth/routes/*.rb serve themselves. Roda has no
#      route table, so the inventory is the string literals those files
#      dispatch on (`r.on 'account'`, `r.get 'mfa-status'`), read from the
#      files. A new literal fails the unit spec until CUSTOM_AUTH_ROUTES
#      names it.
#
# The codes are what the route ITSELF answers on an authentication failure.
# On /auth the router refuses a rejected, revoked or MFA-pending session
# before dispatch (Auth::Router; docs/authentication/customer-session-failure-matrix.md)
# with the session codes, whatever the route; that layer is not repeated per
# route here.
#
# This file is shared support (loaded by every lane) and must stay boot-free:
# it reads files and the code vocabulary, nothing else. The gate modules are
# required by the specs that need them.

require 'onetime/session/failure_code'

module AuthRouteFailureCodes
  ROOT = Onetime::HOME

  SESSION_CODES    = Onetime::SessionFailureCode::SESSION_REASON_SCOPES.keys.freeze
  CREDENTIAL_CODES = Onetime::SessionFailureCode::CREDENTIAL_REASON_SCOPES.keys.freeze

  # ---------------------------------------------------------------------------
  # 1. Otto surfaces
  # ---------------------------------------------------------------------------

  # What a route's 401 can carry, by the strategy that refused it. A chained
  # route (`sessionauth,basicauth`) can carry the union: the last stash wins,
  # and a terminal Basic auth refusal replaces the session strategy's.
  STRATEGY_CODES = {
    # BaseSessionAuthStrategy#failure_for: the evaluator reason.
    'sessionauth' => SESSION_CODES,
    # BasicAuthStrategy, on a terminal credentialed failure.
    'basicauth' => %i[api_key_invalid suspended_credentials].freeze,
    # Never refuses. A rejected Authorization header on a `basicauth,noauth`
    # chain is the Basic strategy's terminal failure, coded above.
    'noauth' => [].freeze,
  }.freeze

  # Rows with no `auth=` option. Otto serves them as anonymous routes; each
  # one is declared here with the reason it carries no strategy, keyed by
  # route table (relative to the repo root), with :all or a list of
  # "VERB path" rows.
  ANONYMOUS_OTTO_ROUTES = {
    # API v1 authenticates in its own controller (V1::Controllers::Base#authorized)
    # and, for backwards compatibility, answers a rejected credential with 404
    # and `X-OTS-Intended-Status: 401` (base.rb, `disabled_response`). Not a
    # 401, so uncoded; the deprecated surface is left as it is.
    'apps/api/v1/routes.txt' => :all,
    # Public metadata, and the CORS preflights for the anonymous secret routes.
    'apps/api/v2/routes.txt' => [
      'GET /status', 'GET /supported-locales', 'OPTIONS /secret/generate', 'OPTIONS /secret/conceal',
    ].freeze,
    'apps/api/v3/routes.txt' => [
      'GET /status', 'GET /supported-locales', 'OPTIONS /secret/generate', 'OPTIONS /secret/conceal',
    ].freeze,
    # Authenticated by the Stripe signature in the handler; never a 401.
    'apps/web/billing/routes.txt' => ['POST /webhook'].freeze,
    # Internal ACME challenge answer, reached only by the TLS terminator.
    'apps/internal/acme/routes.txt' => ['GET /ask'].freeze,
    # SPA shell pages for full-page loads of the auth app's own flows
    # (Core::Controllers::Page#index); the JSON API behind them is /auth.
    'apps/web/core/routes.txt' => [
      'GET /verify-account', 'GET /email-login', 'GET /mfa-verify', 'GET /link-sso/*', 'GET /sso-link-confirm/*',
    ].freeze,
  }.freeze

  # Routes whose handler answers a credential refusal of its own, on top of
  # (or instead of) the strategies'. Keyed by [route table, verb, path].
  HANDLER_CODES = {
    # Simple-mode sign-in: Core::Controllers::Authentication#perform_authentication
    # (`failure_codes:`). `invalid` is the single non-enumerating rejection;
    # `suspended` is only raised past a verified password.
    ['apps/web/core/routes.txt', 'POST', '/auth/login'] => %i[invalid_credentials suspended_credentials].freeze,
  }.freeze

  OttoRoute = Struct.new(:table, :verb, :path, :definition, :auth, :line, keyword_init: true) do
    def anonymous_by_default?
      auth.empty?
    end

    def row
      "#{verb} #{path}"
    end

    def label
      "#{table}:#{line} #{row}"
    end
  end

  class << self
    # Every route row in every Otto route table under apps/, parsed with
    # Otto's own RouteDefinition so `auth=` is read exactly as at boot.
    #
    # @return [Array<OttoRoute>]
    def otto_routes
      Dir.glob(File.join(ROOT, 'apps', '**', 'routes.txt')).sort.flat_map do |file|
        table = file.delete_prefix("#{ROOT}/")
        File.readlines(file, encoding: 'UTF-8').each_with_index.filter_map do |line, index|
          next unless line =~ /\A(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s/

          verb, path, definition = line.strip.split(/\s+/, 3)
          route_definition       = Otto::RouteDefinition.new(verb, path, definition.to_s)

          OttoRoute.new(
            table: table,
            verb: verb,
            path: path,
            definition: definition,
            auth: route_definition.auth_requirements,
            line: index + 1,
          )
        end
      end
    end

    # Whether an `auth=`-less row is declared anonymous.
    def declared_anonymous?(route)
      declared = ANONYMOUS_OTTO_ROUTES[route.table]
      declared == :all || Array(declared).include?(route.row)
    end

    # The codes a route's 401 can carry, or nil when a strategy in its chain
    # is unknown to STRATEGY_CODES.
    #
    # @return [Array<Symbol>, nil]
    def codes_for(route)
      return nil unless route.auth.all? { |strategy| STRATEGY_CODES.key?(strategy) }

      strategy_codes = route.auth.flat_map { |strategy| STRATEGY_CODES.fetch(strategy) }
      handler_codes  = HANDLER_CODES.fetch([route.table, route.verb, route.path], [])
      (strategy_codes + handler_codes).uniq
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Rodauth routes
  # ---------------------------------------------------------------------------

  # Requirement values:
  #   :anonymous       served without a login (a credential or recovery
  #                    ceremony). The route refuses only a credential it
  #                    was handed, if `credential:` is true.
  #   :login_required  Rodauth's require_login / require_account. Refused
  #                    with the router's anonymous stash (session codes);
  #                    with `credential:` true it also confirms a password.
  #   :mfa_pending     the second-factor ceremony: a session that has
  #                    presented its first factor. Refused with the session
  #                    codes; the factor it checks is a credential.
  #
  # `also:` lists the credential codes a route answers beyond
  # `invalid_credentials`. Route names, never paths
  # (ADR-038#classify-by-symbol-not-url).
  RODAUTH_ROUTES = {
    # --- sign-in and recovery, anonymous ---------------------------------
    # The lockout (403, `account_locked`) and the unverified-account refusal
    # (403, `account_unverified`) are answered on this route.
    login: { requirement: :anonymous, credential: true, also: %i[account_locked account_unverified] },
    webauthn_login: { requirement: :anonymous, credential: true },
    webauthn_autofill_js: { requirement: :anonymous, credential: false },
    # A login that matches no account is a rejected credential (401,
    # `no_matching_login`); a rejected link key is not (uncoded).
    email_auth_request: { requirement: :anonymous, credential: true },
    email_auth: { requirement: :anonymous, credential: false },
    create_account: { requirement: :anonymous, credential: false },
    verify_account: { requirement: :anonymous, credential: false },
    verify_account_resend: { requirement: :anonymous, credential: true },
    # The enumeration override (config/overrides/reset_password_enumeration.rb)
    # answers every request-phase outcome alike, so nothing is refused.
    reset_password_request: { requirement: :anonymous, credential: false },
    reset_password: { requirement: :anonymous, credential: false },
    unlock_account_request: { requirement: :anonymous, credential: true },
    unlock_account: { requirement: :anonymous, credential: true },
    # Answered by the router for a refused session, otherwise never refused.
    logout: { requirement: :anonymous, credential: false },
    verify_login_change: { requirement: :anonymous, credential: false },

    # --- account routes, login required ----------------------------------
    remember: { requirement: :login_required, credential: false },
    close_account: { requirement: :login_required, credential: true },
    change_password: { requirement: :login_required, credential: true },
    change_login: { requirement: :login_required, credential: true },
    confirm_password: { requirement: :login_required, credential: true },
    otp_setup: { requirement: :login_required, credential: true },
    otp_disable: { requirement: :login_required, credential: true },
    # Its unlock attempts answer with their own counters, not a 401.
    otp_unlock: { requirement: :login_required, credential: false },
    recovery_codes: { requirement: :login_required, credential: true },
    two_factor_auth: { requirement: :login_required, credential: false },
    two_factor_manage: { requirement: :login_required, credential: false },
    two_factor_disable: { requirement: :login_required, credential: true },
    webauthn_setup: { requirement: :login_required, credential: true },
    webauthn_setup_js: { requirement: :login_required, credential: false },
    webauthn_remove: { requirement: :login_required, credential: true },

    # --- second-factor ceremony ------------------------------------------
    otp_auth: { requirement: :mfa_pending, credential: true },
    recovery_auth: { requirement: :mfa_pending, credential: true },
    webauthn_auth: { requirement: :mfa_pending, credential: true },
    webauthn_auth_js: { requirement: :mfa_pending, credential: false },
  }.freeze

  # OmniAuth's routes are added per provider and per install; the request
  # phase is served by middleware and the callback is anonymous. A rejected
  # SSO assertion is answered by redirect (omniauth_failure_redirect), never
  # a 401, so no code.
  OMNIAUTH_ROUTE_PREFIX = 'omniauth_'

  class << self
    # @param declaration [Hash] a RODAUTH_ROUTES or CUSTOM_AUTH_ROUTES value
    # @return [Array<Symbol>] the codes the route answers with
    def codes_for_declaration(declaration)
      codes = case declaration.fetch(:requirement)
              when :anonymous then []
              when :login_required, :mfa_pending then SESSION_CODES
              else raise ArgumentError, "unknown requirement #{declaration[:requirement].inspect}"
              end
      codes += [:invalid_credentials] if declaration.fetch(:credential)
      codes += declaration.fetch(:also, [])
      codes.uniq
    end

    def omniauth_route?(name)
      name.to_s.start_with?(OMNIAUTH_ROUTE_PREFIX)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Custom Roda routes under apps/web/auth/routes/
  # ---------------------------------------------------------------------------

  CUSTOM_AUTH_ROUTES = {
    # routes/health.rb: monitored path, gated by HealthAccessControl.
    'health' => { requirement: :anonymous, credential: false },
    # routes/account.rb
    'account' => { requirement: :login_required, credential: false },
    'account.json' => { requirement: :login_required, credential: false },
    'mfa-status' => { requirement: :login_required, credential: false },
    # routes/active_sessions.rb
    'active-sessions' => { requirement: :login_required, credential: false },
    'remove-all-active-sessions' => { requirement: :login_required, credential: false },
    # routes/identities.rb
    'identities' => { requirement: :login_required, credential: false },
    # routes/webauthn_credentials.rb
    'webauthn-credentials' => { requirement: :login_required, credential: false },
    # routes/reauth.rb: the offer is per-account state; the completion
    # verifies a password, second factor or passkey (REJECTED_CREDENTIAL_CODES).
    'reauth-offer' => { requirement: :login_required, credential: false },
    'reauth' => { requirement: :login_required, credential: true },
    # routes/link_sso.rb: the SSO sign-in interstitial verifies the existing
    # password. Its `link_expired` 401s are about the token and are uncoded.
    'link-sso' => { requirement: :anonymous, credential: true },
    # routes/sso_link_confirm.rb: token possession alone; `link_expired`
    # 401s are uncoded.
    'sso-link-confirm' => { requirement: :anonymous, credential: false },
  }.freeze

  # Single- or double-quoted, so a future `r.on "x"` is not invisible here.
  CUSTOM_ROUTE_LITERAL = /\br\.(?:on|is|get|post|put|delete)\s*\(?\s*(['"])([^'"]+)\1/

  class << self
    # The string literals the custom /auth route modules dispatch on.
    #
    # @return [Hash{String=>String}] literal => "file:line" of its first use
    def custom_auth_route_literals
      Dir.glob(File.join(ROOT, 'apps', 'web', 'auth', 'routes', '*.rb')).sort.each_with_object({}) do |file, found|
        File.readlines(file, encoding: 'UTF-8').each_with_index do |line, index|
          next if line.lstrip.start_with?('#')

          line.scan(CUSTOM_ROUTE_LITERAL).each do |(_quote, literal)|
            found[literal] ||= "#{file.delete_prefix("#{ROOT}/")}:#{index + 1}"
          end
        end
      end
    end
  end
end
