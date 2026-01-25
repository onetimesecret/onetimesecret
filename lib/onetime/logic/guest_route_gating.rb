# lib/onetime/logic/guest_route_gating.rb
#
# frozen_string_literal: true

module Onetime
  module Logic
    # Concern for enforcing guest route configuration in API logic classes.
    #
    # Guest routes allow anonymous (unauthenticated) API access for specific
    # operations. This concern provides a method to check if guest access is
    # enabled globally and for specific operations.
    #
    # Configuration is read from `site.interface.api.guest_routes` in config.yaml:
    #
    #   site:
    #     interface:
    #       api:
    #         guest_routes:
    #           enabled: true      # Global toggle
    #           conceal: true      # Per-operation toggle
    #           generate: true
    #           reveal: true
    #           burn: true
    #
    # Usage in raise_concerns:
    #
    #   def raise_concerns
    #     require_guest_route_enabled!(:conceal)
    #     super
    #   end
    #
    module GuestRouteGating
      # Check if the guest route is enabled for the given operation.
      #
      # Only enforced when the request is from an anonymous user with noauth.
      # Authenticated users are not subject to guest route restrictions.
      #
      # @param operation [Symbol, String] The operation to check (e.g., :conceal, :reveal)
      # @raise [Onetime::GuestRoutesDisabled] If guest routes are disabled
      # @return [true] If check passes (authenticated user or guest route enabled)
      def require_guest_route_enabled!(operation)
        return true unless guest_context?

        config = guest_routes_config

        unless config['enabled']
          raise Onetime::GuestRoutesDisabled.new(
            'Guest API access is disabled',
            code: 'GUEST_ROUTES_DISABLED',
          )
        end

        unless config[operation.to_s]
          raise Onetime::GuestRoutesDisabled.new(
            "Guest #{operation} is disabled",
            code: "GUEST_#{operation.to_s.upcase}_DISABLED",
          )
        end

        true
      end

      private

      # Determine if this is a guest (anonymous + noauth) context.
      #
      # A guest context is when:
      # 1. The customer is anonymous (not logged in)
      # 2. The authentication method is 'noauth' (no credentials provided)
      #
      # @return [Boolean] True if this is a guest context
      def guest_context?
        cust.anonymous? && strategy_result&.auth_method == 'noauth'
      end

      # Get the guest routes configuration from the site config.
      #
      # @return [Hash] The guest_routes configuration, or empty hash if not configured
      def guest_routes_config
        OT.conf.dig('site', 'interface', 'api', 'guest_routes') || {}
      end
    end
  end
end
