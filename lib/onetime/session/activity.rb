# lib/onetime/session/activity.rb
#
# frozen_string_literal: true

module Onetime
  # Whether the current request counts as session activity (#4455).
  #
  # A request is **activity** unless its route says otherwise. A route that
  # only verifies the session on a timer, with no user action behind it,
  # declares `activity=passive` in its routes file:
  #
  #     GET /bootstrap/me  Core::Controllers::Page#bootstrap_me auth=noauth activity=passive
  #
  # A passive request is verified exactly like any other: revocation, both
  # active-session deadlines, suspension and the credential watermark all
  # apply, and an expired active-session row is still removed. What it must
  # not do is move an inactivity clock, or a tab left open would keep its own
  # session alive forever by polling. Three writers read this predicate, one
  # per clock:
  #
  # - {Onetime::ActiveSessionGate}: the active-session row's `last_use`
  #   (Rodauth's inactivity deadline, full mode).
  # - {Onetime::Operations::Sessions::TrackMetadata}: `last_activity_at` (the
  #   admin-surface idle bound).
  # - {Onetime::Session#write_session}: the Rack session blob's TTL (the only
  #   inactivity clock in simple mode).
  #
  # ## Requests the client declares passive
  #
  # A route cannot say which of its requests a person asked for. The
  # dashboard's receipt list is fetched by navigation and re-fetched by a
  # five-minute timer through the same `GET`, and with only the route
  # declaration a tab left on the dashboard never reached the inactivity
  # deadline (RISK-2026-09-19-04). The client knows the difference, so it may
  # say so:
  #
  #     X-Session-Activity: passive
  #
  # The header can only ever take activity away. It is read for nothing but
  # the exact value `passive`, so no value makes a passive route count; it is
  # honoured on `GET` and `HEAD` only, so a request that changes state always
  # counts, whatever it declares; and it reaches nothing but this predicate,
  # so authentication, the evaluator and both deadlines run exactly as they
  # do without it. What a caller can do with it is let its own session end
  # sooner. Nothing is gained by forging it and nothing needs to trust it.
  #
  # Otto parses `key=value` route tokens into Symbol keys and publishes them
  # at `env['otto.route_options']` when the route matches, before the auth
  # strategy runs. A request no Otto route matched (the Roda auth app, a
  # static file, a 404) has no options and is therefore activity: the default
  # is today's behaviour, and passive is something a route opts into.
  #
  # The predicate is read at each decision, never cached. If one Rack env is
  # dispatched to a second route, the second route's declaration governs from
  # that point on.
  #
  # ## Refused requests
  #
  # "A refused request is not activity" is the older half of the same rule
  # (#4331): a request the session gates turned away must not advance the
  # deadline it was turned away under, or the refusal would only ever cost
  # one 401. {.refused?} reads the two places a refusal is recorded, and
  # {.counts?} is the single question the two session-store writers ask.
  # The gate does not ask it: it produces the refusal, and already refuses
  # before it touches.
  module SessionActivity
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

      verdict = env[Onetime::CustomerSessionEvaluator::ENV_KEY]
      return false unless verdict.respond_to?(:rejected?) && verdict.respond_to?(:unavailable?)

      verdict.rejected? || verdict.unavailable?
    end

    # Whether this request may move an inactivity clock.
    def counts?(env)
      !passive?(env) && !refused?(env)
    end
  end
end
