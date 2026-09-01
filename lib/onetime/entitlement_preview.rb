# lib/onetime/entitlement_preview.rb
#
# frozen_string_literal: true

module Onetime
  # Request-scoped entitlement preview context (ADR-020).
  #
  # Holds the session's preview keys (test planid plus the Redis key names of
  # the session-scoped grants/revokes sets written by SetEntitlementPreview)
  # in a Fiber-local for the duration of a request. The entitlement and limit
  # chokepoints (WithEntitlements#entitlements, WithPlanEntitlements#entitlements,
  # OrganizationMembership#entitlements, WithMaterializedLimits#limit_for)
  # consult this context, so every consumer above them is preview-aware
  # without a session parameter.
  #
  # Populated once per request by Middleware::EntitlementPreviewContext and
  # cleared in its ensure block — the same fiber-local discipline as
  # connection_pinning.rb. A missing context means no preview is active.
  module EntitlementPreview
    FIBER_KEY = :ots_entitlement_preview

    # Session keys holding the NAMES of the two session-scoped Redis sets.
    SESSION_SET_KEYS = [
      :entitlement_preview_grants_key,
      :entitlement_preview_revokes_key,
    ].freeze

    # Every session key a preview writes. SetEntitlementPreview owns their
    # meaning; this list exists so all teardown paths delete the same three.
    # `entitlement_preview_planid` is legacy-for-transition and still cleared.
    SESSION_MARKER_KEYS = (SESSION_SET_KEYS + [:entitlement_preview_planid]).freeze

    class << self
      # Stash the preview context for the current fiber.
      #
      # Empty strings normalize to nil so a blank session value cannot
      # register as an active preview. When all three values are nil there is
      # nothing to preview: the fiber-local is cleared rather than storing an
      # empty hash that would make `active?` report true.
      #
      # @param planid [String, nil] Preview plan id
      # @param grants_key [String, nil] Redis key of the session grants set
      # @param revokes_key [String, nil] Redis key of the session revokes set
      # @return [Hash, nil] The frozen context, or nil when nothing was stored
      def set(planid:, grants_key:, revokes_key:)
        planid      = normalize(planid)
        grants_key  = normalize(grants_key)
        revokes_key = normalize(revokes_key)

        if planid.nil? && grants_key.nil? && revokes_key.nil?
          clear
          return nil
        end

        Fiber[FIBER_KEY] = {
          planid: planid,
          grants_key: grants_key,
          revokes_key: revokes_key,
        }.freeze
      end

      # @return [Hash, nil] Frozen context hash, or nil when no preview is active
      def context
        Fiber[FIBER_KEY]
      end

      # @return [Boolean] Whether a preview context is present on this fiber
      def active?
        !context.nil?
      end

      # Remove the fiber-local.
      #
      # @return [nil]
      def clear
        Fiber[FIBER_KEY] = nil
      end

      # Tear a preview out of a SESSION as well as out of this request.
      #
      # The single place that knows what a preview leaves behind: the two
      # session-scoped Redis sets (whose full key names the session itself
      # carries — no key-name construction here, so the naming stays owned by
      # SetEntitlementPreview), the three session markers, and the
      # request-scoped context. Callers that end a preview for a reason other
      # than "the operator cleared it" — impersonation start, for one, where a
      # preview would silently distort what the operator sees as the customer
      # — go through here rather than re-deriving the key names.
      #
      # Best-effort on the Redis half: both sets carry their own TTL, so a
      # failed DEL leaks nothing durable, and the session markers (which are
      # what makes a preview ACTIVE) are cleared regardless.
      #
      # @param session [#[], #delete, nil] Rack session
      # @return [nil]
      def clear_session!(session)
        return clear unless session.respond_to?(:[]) && session.respond_to?(:delete)

        delete_session_sets(session)

        SESSION_MARKER_KEYS.each { |key| session.delete(key) }

        clear
      end

      private

      def delete_session_sets(session)
        # Symbol keys throughout, like every incumbent call site: a live
        # Rack::Session::Abstract::SessionHash stringifies keys on access, so
        # the symbol spelling is the one that works on both a real session and
        # the doubles the colonel specs build.
        keys = SESSION_SET_KEYS.map { |key| session[key] }.reject { |name| name.to_s.empty? }
        return if keys.empty?

        Familia.dbclient.del(*keys)
      rescue StandardError => ex
        OT.le "[entitlement_preview] session set cleanup failed: #{ex.class}: #{ex.message}"
      end

      def normalize(value)
        str = value.to_s
        str.empty? ? nil : str
      end
    end
  end
end
