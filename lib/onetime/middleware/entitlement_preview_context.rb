# lib/onetime/middleware/entitlement_preview_context.rb
#
# frozen_string_literal: true

require_relative '../entitlement_preview'

module Onetime
  module Middleware
    # Entitlement Preview Context Middleware (ADR-020)
    #
    # Copies the session's entitlement-preview keys into a Fiber-local once
    # per request so the entitlement/limit chokepoints can consult the
    # preview without a session parameter. Consumers become preview-aware by
    # construction rather than by opt-in.
    #
    # Must be mounted after session middleware (reads env['rack.session']).
    #
    # ### Usage
    #
    # ```ruby
    # use Onetime::Middleware::EntitlementPreviewContext
    # ```
    #
    # The ensure-clear is sufficient because all response bodies are
    # serialized eagerly (JSON strings built in-handler). If a streaming or
    # lazy body ever consumes entitlements during server-side body iteration,
    # the clear must move to Rack::BodyProxy#on_close.
    class EntitlementPreviewContext
      def initialize(app)
        @app = app
      end

      def call(env)
        # Defensive: state leaked by a previous request on this fiber must
        # not bleed into this one.
        Onetime::EntitlementPreview.clear

        session = env['rack.session']
        if session.respond_to?(:[])
          planid      = session[:entitlement_preview_planid]
          grants_key  = session[:entitlement_preview_grants_key]
          revokes_key = session[:entitlement_preview_revokes_key]

          if [planid, grants_key, revokes_key].any? { |val| !val.to_s.empty? }
            Onetime::EntitlementPreview.set(
              planid: planid,
              grants_key: grants_key,
              revokes_key: revokes_key,
            )
          end
        end

        @app.call(env)
      ensure
        Onetime::EntitlementPreview.clear
      end
    end
  end
end
