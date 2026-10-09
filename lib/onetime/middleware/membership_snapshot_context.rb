# lib/onetime/middleware/membership_snapshot_context.rb
#
# frozen_string_literal: true

require_relative '../membership_snapshot'

module Onetime
  module Middleware
    # Opens the request store for Onetime::MembershipSnapshot and clears it
    # when the request is done, so the organization loader, the bootstrap
    # serializer and the session commit share one read of the customer's
    # memberships. Mounted above Onetime::Session: the session commit on the
    # way out (Sessions::TrackMetadata) resolves the active organization too
    # and must still find the store open.
    #
    # The ensure-clear is sufficient because all response bodies are
    # serialized eagerly, as for EntitlementPreviewContext. A streaming body
    # that resolved organizations during iteration would need the clear
    # moved to Rack::BodyProxy#on_close.
    class MembershipSnapshotContext
      def initialize(app)
        @app = app
      end

      def call(env)
        Onetime::MembershipSnapshot.open
        @app.call(env)
      ensure
        Onetime::MembershipSnapshot.close
      end
    end
  end
end
