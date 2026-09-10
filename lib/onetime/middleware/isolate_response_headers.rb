# lib/onetime/middleware/isolate_response_headers.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # Hands every middleware above it a response headers hash that belongs to
    # THIS request.
    #
    # Rack middleware writes response headers in place: rack-session's
    # `commit_session` calls `Rack::Response::Raw#set_cookie`, which is an
    # `add_header` on the hash the app returned — and
    # Rack::Utils.set_cookie_header! APPENDS when the value is already an
    # Array. CsrfResponseHeader, DomainStrategy and RetryAfterHeader assign
    # into the same hash. That is fine as long as the hash is fresh per
    # request, and every controller-built response is. Otto's router
    # fallbacks are not: `router.not_found` and `router.server_error` are
    # static Rack triples built once in each application's `build_router`,
    # and Otto returns them BY REFERENCE (otto/core/router.rb `@not_found`,
    # otto/core/error_handler.rb `@server_error`). One process-lifetime hash
    # therefore accumulated every session cookie ever committed on a 404/500
    # in that app and replayed all of them, to any client, on every later
    # miss. Session ids are bearer tokens with no client binding.
    #
    # Mounted innermost in Onetime::Application::Base#build_rack_app,
    # directly around the router, so the copy is made before any header
    # writer runs and regardless of which app (or which Otto version) is
    # behind it. A shallow copy of the hash plus a copy of each Array value:
    # the hash copy stops single-valued writes from landing on the shared
    # object, and the Array copies stop an append from reaching a shared
    # multi-valued header (Rack 3 represents repeated headers as Arrays).
    # Non-Array values (Strings) are never mutated by the rack header API.
    #
    # Deliberately keeps the headers object's class: Rack 3 apps may return
    # Rack::Headers (case-insensitive keys) and `dup` preserves that, where
    # `transform_values` would hand back a plain Hash.
    #
    # Regression guard:
    #   spec/integration/all/router_fallback_response_headers_spec.rb
    class IsolateResponseHeaders
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        [status, self.class.isolate(headers), body]
      end

      # @param headers [Hash, Rack::Headers, nil]
      # @return [Hash, Rack::Headers, nil] a per-request copy; nil stays nil so
      #   a malformed response fails downstream the same way it did before.
      def self.isolate(headers)
        return headers unless headers.respond_to?(:dup) && headers.respond_to?(:each_pair)

        copy = headers.dup
        # Reassigning an EXISTING key during iteration is permitted; only
        # adding keys is not, so `keys` is snapshotted first to keep the
        # invariant obvious rather than relying on that subtlety.
        copy.keys.each do |key|
          value     = copy[key]
          copy[key] = value.dup if value.is_a?(Array)
        end
        copy
      end
    end
  end
end
