# lib/onetime/session/activity.rb
#
# frozen_string_literal: true

require_relative 'namespace'

module Onetime
  # Classifies requests for the session inactivity clocks: active-session
  # `last_use`, admin `last_activity_at`, and the Rack session blob TTL.
  #
  # Routes opt out with `activity=passive`. On GET or HEAD,
  # `X-Session-Activity: passive` can only suppress activity, not enable it.
  # Passive requests still undergo all authentication checks.
  # Read the route options at each decision because Rack may redispatch the env.
  # Refused requests do not refresh the session-store clocks.
  module Session::Activity
    extend self

    ROUTE_OPTIONS_ENV_KEY = 'otto.route_options'
    OPTION                = :activity
    PASSIVE               = 'passive'

    # The request header a client sets on a timer-driven request, and the Rack
    # env key it arrives under. The only value read is {PASSIVE}.
    HEADER         = 'X-Session-Activity'
    HEADER_ENV_KEY = 'HTTP_X_SESSION_ACTIVITY'

    # The methods the header is honoured on: an allowlist, so a method this
    # list has never heard of counts as activity.
    DECLARABLE_METHODS = %w[GET HEAD].freeze

    # @param env [Hash, nil] the Rack env
    # @return [Boolean] true when the matched route declares
    #   `activity=passive`, or the client declared this safe request passive
    def passive?(env)
      return false unless env.is_a?(Hash)

      route_passive?(env) || client_declared_passive?(env)
    end

    # @return [Boolean] true only when the matched route declares
    #   `activity=passive`
    def route_passive?(env)
      options = env[ROUTE_OPTIONS_ENV_KEY]
      return false unless options.is_a?(Hash)

      options[OPTION] == PASSIVE
    end

    # @return [Boolean] true only for a GET or HEAD whose
    #   `X-Session-Activity` header is exactly `passive` (case and surrounding
    #   whitespace aside)
    def client_declared_passive?(env)
      return false unless DECLARABLE_METHODS.include?(env['REQUEST_METHOD'])

      declared = env[HEADER_ENV_KEY]
      declared.is_a?(String) && declared.strip.casecmp?(PASSIVE)
    end

    # True when a session gate refused this request: the shared evaluator
    # rejected the customer session or could not verify it, or the
    # admin-surface bounds (#4331) flagged it. The Rack session blob still
    # says `authenticated` in every one of these cases, which is why the
    # writers cannot tell from the session data alone.
    #
    # An anonymous or MFA-pending verdict is not a refusal. A login that
    # completes inside such a request clears the memo and writes an
    # authenticated session, and that write is activity.
    #
    # The constants are resolved here, at call time, because the evaluator
    # requires the gate and the gate requires this file.
    def refused?(env)
      return false unless env.is_a?(Hash)
      return true unless env[Onetime::Application::AuthStrategies::AdminSessionLifetime::EXPIRED_ENV_KEY].nil?

      verdict = env[Onetime::Session::CustomerSessionEvaluator::ENV_KEY]
      return false unless verdict.respond_to?(:rejected?) && verdict.respond_to?(:unavailable?)

      verdict.rejected? || verdict.unavailable?
    end

    # Whether this request may move an inactivity clock.
    def counts?(env)
      !passive?(env) && !refused?(env)
    end
  end
end
