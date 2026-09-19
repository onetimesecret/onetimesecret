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
  # Otto parses `key=value` route tokens into Symbol keys and publishes them
  # at `env['otto.route_options']` when the route matches, before the auth
  # strategy runs. A request no Otto route matched (the Roda auth app, a
  # static file, a 404) has no options and is therefore activity: the default
  # is today's behaviour, and passive is something a route opts into.
  #
  # The predicate is read at each decision, never cached. If one Rack env is
  # dispatched to a second route, the second route's declaration governs from
  # that point on.
  module SessionActivity
    extend self

    ROUTE_OPTIONS_ENV_KEY = 'otto.route_options'
    OPTION                = :activity
    PASSIVE               = 'passive'

    # @param env [Hash, nil] the Rack env
    # @return [Boolean] true only when the matched route declares
    #   `activity=passive`
    def passive?(env)
      return false unless env.is_a?(Hash)

      options = env[ROUTE_OPTIONS_ENV_KEY]
      return false unless options.is_a?(Hash)

      options[OPTION] == PASSIVE
    end
  end
end
