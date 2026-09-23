# apps/web/core/middleware/snapshot_ordering.rb
#
# frozen_string_literal: true

require 'onetime/session/snapshot_ordering'

module Core
  module Middleware
    # Allocates the bootstrap snapshot ordering pair (ADR-046) once per Web
    # Core request that carries an ordered session.
    #
    # ## Placement
    #
    # Innermost in Core::Application, directly around the router: after the
    # session is loaded (universal stack) and BEFORE the router invokes the
    # authentication strategy. The version is a start stamp — a snapshot
    # reflects every write committed before its version was allocated — so it
    # has to precede the strategy's customer, organization and entitlement
    # reads. Behind StaticFiles, so an authenticated tab's asset requests
    # allocate nothing.
    #
    # The middleware cannot know whether the route will serialize a snapshot,
    # so a version may be allocated and never delivered. Versions are compared
    # only as strictly greater; gaps are harmless.
    #
    # ## Failure
    #
    # Never raises and never touches the response. A failed allocation is
    # recorded in env for the two consumers to act on:
    # Core::Controllers::Page#bootstrap_me answers a retryable 503, and HTML
    # hydration renders without the pair. A route that serializes no snapshot
    # is unaffected, and so is the session write.
    class SnapshotOrdering
      ENV_KEY = Onetime::SnapshotOrdering::ENV_KEY

      def initialize(app)
        @app = app
      end

      def call(env)
        allocate(env)
        @app.call(env)
      end

      private

      def allocate(env)
        session = env['rack.session']
        return unless Onetime::SnapshotOrdering.ordered?(session)

        env[ENV_KEY] = Onetime::SnapshotOrdering.allocate(session, ttl: expire_after(env))
      rescue StandardError => ex
        env[ENV_KEY] = { error: ex.class.name }
        log_failure(env, ex)
      end

      # The lifetime the session commit will write the blob to in this same
      # request (ADR-046 step 5), not the blob's remaining TTL.
      def expire_after(env)
        options = env['rack.session.options']
        options.respond_to?(:[]) ? options[:expire_after] : nil
      end

      # Redaction (#4461): the request id and the exception class only. Never
      # the session id, and not the exception message either — a Redis error
      # message can quote the command, whose key embeds the sid.
      def log_failure(env, ex)
        Onetime.session_logger.warn 'Snapshot ordering allocation failed',
          {
            module: 'SnapshotOrdering',
            error: ex.class.name,
            request_id: env['HTTP_X_REQUEST_ID'],
          }
      rescue StandardError
        nil
      end
    end
  end
end
