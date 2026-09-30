# lib/onetime/session/failure_code.rb
#
# frozen_string_literal: true

require_relative 'customer_session_evaluator'

module Onetime
  # Stable, machine-readable codes for authentication refusals (#4462, #4469).
  #
  # The wire `code` is the refusal reason verbatim: there is one vocabulary and
  # no translation table that can drift from it. `code_scope` names the class
  # of failure so a client can act on a code it has never seen:
  #
  #   customer_session          The customer session was examined and is not
  #                             (or is no longer) an authenticated one. The
  #                             client reconciles against the server.
  #   verification_unavailable  The session could not be verified (datastore
  #                             outage). Not a verdict about the session; the
  #                             client must not treat it as a sign-out.
  #   admin_session             The admin-only idle/absolute timeout. The
  #                             customer session itself is untouched.
  #   credential                A credential the request presented was
  #                             examined and rejected: a login (password,
  #                             passkey, second factor), a re-authentication,
  #                             or an API key. Not a statement about the
  #                             customer session, which may be perfectly
  #                             valid; the form or client that sent the
  #                             credential owns the message (#4469).
  #
  # The session reasons are owned by Onetime::CustomerSessionEvaluator::REASONS
  # and are what the session strategies and the /auth router stash. The
  # credential reasons are listed in CREDENTIAL_REASON_SCOPES below and are
  # stashed by whatever code rejects the credential: the Basic auth strategies
  # (an API key), the Rodauth seam (Auth::CredentialFailureCode), the /auth
  # re-authentication and SSO-linking routes, and the simple-mode sign-in
  # controller. They are deliberately no more granular than the message each
  # of those paths already returns, so a code never distinguishes an unknown
  # account from a wrong password or an unverified account.
  #
  # A 401 without a `code` still makes no statement about the customer
  # session. A 403 carries the pair only when it is a credential refusal
  # (Rodauth answers a locked-out or unverified account with 403); a session
  # reason is never rendered onto a 403.
  #
  # Both fields are additive: redirects and the existing `error`, `message`,
  # `error_type`, `timestamp`, `success` fields are unchanged. So is every
  # status but one: a JSON refusal in the `verification_unavailable` scope
  # leaves the middleware as a 503 with `Retry-After`, because it is an
  # outage and not a verdict (Onetime::Middleware::SessionFailureCode, "The
  # 503"). Every annotated 401 also carries a `WWW-Authenticate` challenge.
  module SessionFailureCode
    # Rack env key written by the code that refuses a request, read by
    # Onetime::Middleware::SessionFailureCode. Holds the reason Symbol.
    ENV_KEY = 'onetime.session_failure_reason'

    # Rack env key naming the HTTP authentication scheme whose credential
    # was rejected, when there is one. Written only by the Basic auth
    # strategies (Helpers#credentialed_failure), beside the reason, so the
    # middleware's `WWW-Authenticate` challenge follows the provenance of the
    # refusal and never the headers a request happened to carry: a form
    # login that rejected its password is challenged with the application's
    # `Session` scheme even if the request also carried an `Authorization`
    # header no strategy examined.
    SCHEME_ENV_KEY = 'onetime.session_failure_scheme'
    SCHEME_BASIC   = 'Basic'

    SCOPE_CUSTOMER_SESSION         = 'customer_session'
    SCOPE_VERIFICATION_UNAVAILABLE = 'verification_unavailable'
    SCOPE_ADMIN_SESSION            = 'admin_session'
    SCOPE_CREDENTIAL               = 'credential'

    SCOPES = [
      SCOPE_CUSTOMER_SESSION,
      SCOPE_VERIFICATION_UNAVAILABLE,
      SCOPE_ADMIN_SESSION,
      SCOPE_CREDENTIAL,
    ].freeze

    # Every non-success evaluator reason and its scope. Written out rather
    # than derived from REASONS on purpose: a new evaluator reason has to be
    # given a scope here by a person (failure_code_spec.rb fails until it is),
    # because defaulting an outage reason to `customer_session` would tell
    # clients to sign the user out.
    SESSION_REASON_SCOPES = {
      session_missing: SCOPE_CUSTOMER_SESSION,
      awaiting_mfa: SCOPE_CUSTOMER_SESSION,
      not_authenticated: SCOPE_CUSTOMER_SESSION,
      identity_missing: SCOPE_CUSTOMER_SESSION,
      surface_mismatch: SCOPE_CUSTOMER_SESSION,
      customer_not_found: SCOPE_CUSTOMER_SESSION,
      account_suspended: SCOPE_CUSTOMER_SESSION,
      stale_credentials: SCOPE_CUSTOMER_SESSION,
      admin_session_expired: SCOPE_ADMIN_SESSION,
      active_session_revoked: SCOPE_CUSTOMER_SESSION,
      active_session_unavailable: SCOPE_VERIFICATION_UNAVAILABLE,
      customer_unavailable: SCOPE_VERIFICATION_UNAVAILABLE,
    }.freeze

    # The credential vocabulary (#4469). One reason per kind of credential
    # the surfaces reject, at the granularity of the message they already
    # send:
    #
    #   invalid_credentials    A login credential was rejected: the login or
    #                          password on POST /auth/login (one code for
    #                          both), a passkey assertion, a second factor, a
    #                          password confirmation on an account route, a
    #                          re-authentication, the simple-mode sign-in, or
    #                          the password on the SSO-linking interstitial.
    #   api_key_invalid        An `Authorization` header was presented and
    #                          rejected by a Basic auth strategy: wrong
    #                          scheme, malformed, unknown account, or wrong
    #                          key. One code, as the strategy takes constant
    #                          time across them.
    #   suspended_credentials  The credential was valid but its account is
    #                          suspended. Only ever observable to a holder of
    #                          the valid credential (an API key, or the
    #                          simple-mode password).
    #   account_locked         Rodauth's lockout: too many failed logins, and
    #                          the account cannot be logged in to until it is
    #                          unlocked. Answered with 403 and its own
    #                          message on the same login path, so the code
    #                          discloses nothing the message did not.
    #   account_unverified     A login to an account that has not completed
    #                          verification. Answered with 403 and its own
    #                          (deliberately generic) message.
    CREDENTIAL_REASON_SCOPES = {
      invalid_credentials: SCOPE_CREDENTIAL,
      api_key_invalid: SCOPE_CREDENTIAL,
      suspended_credentials: SCOPE_CREDENTIAL,
      account_locked: SCOPE_CREDENTIAL,
      account_unverified: SCOPE_CREDENTIAL,
    }.freeze

    REASON_SCOPES = SESSION_REASON_SCOPES.merge(CREDENTIAL_REASON_SCOPES).freeze

    # String keys and values: these hashes are merged straight into JSON
    # response bodies.
    CODES = REASON_SCOPES.to_h do |reason, scope|
      [reason, { 'code' => reason.to_s, 'code_scope' => scope }.freeze]
    end.freeze

    # Reasons that describe a visitor who never claimed a session, or a login
    # that is still in progress. They are the steady state of any public site,
    # so .log_refusal records them at debug.
    ROUTINE_REASONS = [:session_missing, :not_authenticated, :awaiting_mfa].freeze

    class << self
      # @param reason [Symbol, String, nil] a refusal reason
      # @return [Hash{String=>String}] `code` and `code_scope`, or an empty
      #   Hash for :authenticated / unknown input, so callers can always merge
      #   the result.
      def for(reason)
        return {} if reason.nil?

        CODES.fetch(reason.to_sym, {})
      end

      # @param reason [Symbol, String, nil]
      # @return [Boolean] whether the reason is in the credential scope
      def credential?(reason)
        return false if reason.nil?

        CREDENTIAL_REASON_SCOPES.key?(reason.to_sym)
      end

      # Record the reason a request is being refused for, for the middleware
      # to render. The last writer wins: on a `sessionauth,basicauth` chain
      # the session strategy's reason is replaced by the Basic auth strategy's
      # when the header it presented is rejected, which is the refusal the
      # client is answered with.
      #
      # @param env [Hash, nil] the Rack env. A nil or non-Hash env is ignored,
      #   so bare unit-level strategy calls need no guard.
      # @param reason [Symbol] a key of REASON_SCOPES
      # @return [void]
      def stash(env, reason)
        return nil unless env.is_a?(Hash)

        env[ENV_KEY] = reason
        # A scheme belongs to the reason it was stashed with. A later writer
        # that replaces the reason without naming a scheme has no Basic
        # credential to challenge for.
        env.delete(SCHEME_ENV_KEY)
        nil
      end

      # Record the HTTP authentication scheme whose credential the stashed
      # reason rejects. Called after .stash by the code that examined that
      # credential; today only the Basic auth strategies.
      #
      # @param env [Hash, nil] the Rack env
      # @param scheme [String] SCHEME_BASIC
      # @return [void]
      def stash_scheme(env, scheme)
        env[SCHEME_ENV_KEY] = scheme if env.is_a?(Hash)
        nil
      end

      # The scheme stashed beside the reason, or nil when no HTTP
      # authentication scheme examined a credential.
      #
      # @param env [Hash, nil] the Rack env
      # @return [String, nil]
      def scheme(env)
        env[SCHEME_ENV_KEY] if env.is_a?(Hash)
      end

      # Withdraw a stashed reason and its scheme. For a route that answers a
      # 401 which is neither the session's nor a credential's (an expired
      # SSO-linking token), so the router's anonymous stash is not rendered
      # onto it.
      #
      # @param env [Hash, nil] the Rack env
      # @return [void]
      def forget(env)
        return nil unless env.is_a?(Hash)

        env.delete(ENV_KEY)
        env.delete(SCHEME_ENV_KEY)
        nil
      end

      # One structured line per session refusal, from both places a refusal
      # is answered: the Otto session strategies and the /auth router (#4461).
      #
      # It carries what joins a client report to the server's decision and
      # nothing that could be replayed: the `code` and `code_scope` the client
      # was sent, the request id it was sent, and the route PATTERN. Never the
      # sid, a cookie, a token, or the request path, whose segments can be
      # secret identifiers.
      #
      # A refused claim is info; an outage is warn, because it refuses
      # sessions that may be perfectly valid. Never raises: logging must not
      # be able to change how a request is answered.
      #
      # Credential refusals are not logged here. Each surface that rejects a
      # credential already records it (Rodauth's `login_failure` event, the
      # simple-mode sign-in's log line, Otto's failed-chain line), and a
      # `Session refused` line for a rejected password would claim the session
      # was refused when it was never examined.
      #
      # @param reason [Symbol, String, nil] the refusal reason acted on
      # @param env [Hash, nil] the Rack env
      # @return [void]
      def log_refusal(reason, env)
        return if credential?(reason)

        pair = self.for(reason)
        return if pair.empty?

        level   = refusal_log_level(reason.to_sym, pair['code_scope'])
        payload = pair.transform_keys(&:to_sym)
        if env.is_a?(Hash)
          payload[:request_id] = env['HTTP_X_REQUEST_ID']
          payload[:route]      = env['otto.route_definition']&.path if env['otto.route_definition'].respond_to?(:path)
        end

        Onetime.auth_logger.public_send(level, 'Session refused', payload.compact)
        nil
      rescue StandardError
        nil
      end

      private

      def refusal_log_level(reason, scope)
        return :debug if ROUTINE_REASONS.include?(reason)
        return :warn if scope == SCOPE_VERIFICATION_UNAVAILABLE

        :info
      end
    end
  end
end
