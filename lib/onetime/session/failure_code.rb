# lib/onetime/session/failure_code.rb
#
# frozen_string_literal: true

require_relative 'customer_session_evaluator'

module Onetime
  # Stable, machine-readable codes for session-authentication refusals (#4462).
  #
  # The wire `code` is the evaluator reason verbatim: there is one vocabulary,
  # owned by Onetime::CustomerSessionEvaluator::REASONS, and no translation
  # table that can drift from it. `code_scope` names the class of failure so a
  # client can act on a code it has never seen:
  #
  #   customer_session          The customer session was examined and is not
  #                             (or is no longer) an authenticated one. The
  #                             client reconciles against the server.
  #   verification_unavailable  The session could not be verified (datastore
  #                             outage). Not a verdict about the session; the
  #                             client must not treat it as a sign-out.
  #   admin_session             The admin-only idle/absolute timeout. The
  #                             customer session itself is untouched.
  #
  # Reserved, not emitted yet: `credential` (login / reauthentication /
  # API-key rejections; #4469). A 401 without a `code` makes no statement
  # about the customer session.
  #
  # Both fields are additive. Statuses, redirects, and the existing `error`,
  # `message`, `error_type`, `timestamp`, `success` fields are unchanged.
  module SessionFailureCode
    # Rack env key written by the session auth strategies when they refuse a
    # request, read by Onetime::Middleware::SessionFailureCode. Holds the
    # evaluator reason Symbol.
    ENV_KEY = 'onetime.session_failure_reason'

    SCOPE_CUSTOMER_SESSION         = 'customer_session'
    SCOPE_VERIFICATION_UNAVAILABLE = 'verification_unavailable'
    SCOPE_ADMIN_SESSION            = 'admin_session'

    SCOPES = [
      SCOPE_CUSTOMER_SESSION,
      SCOPE_VERIFICATION_UNAVAILABLE,
      SCOPE_ADMIN_SESSION,
    ].freeze

    # Every non-success evaluator reason and its scope. Written out rather
    # than derived from REASONS on purpose: a new evaluator reason has to be
    # given a scope here by a person (failure_code_spec.rb fails until it is),
    # because defaulting an outage reason to `customer_session` would tell
    # clients to sign the user out.
    REASON_SCOPES = {
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
      # @param reason [Symbol, String, nil] an evaluator reason
      # @return [Hash{String=>String}] `code` and `code_scope`, or an empty
      #   Hash for :authenticated / unknown input, so callers can always merge
      #   the result.
      def for(reason)
        return {} if reason.nil?

        CODES.fetch(reason.to_sym, {})
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
      # @param reason [Symbol, String, nil] the evaluator reason acted on
      # @param env [Hash, nil] the Rack env
      # @return [void]
      def log_refusal(reason, env)
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
