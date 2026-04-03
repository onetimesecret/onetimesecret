# apps/api/incoming/logic/base.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'
require 'onetime/logic/organization_context'
require 'onetime/logic/guest_route_gating'

module Incoming
  module Logic
    # Base class for Incoming API logic classes.
    #
    # Extends Onetime::Logic::Base with:
    # - URI helpers for building paths and URLs
    # - Guest route gating for anonymous access control
    # - Domain context support for multi-tenant deployments
    #
    # All Incoming routes are anonymous (noauth), so this base class
    # is designed to work without authenticated user context while
    # still supporting domain-aware configuration.
    class Base < Onetime::Logic::Base
      include V2::Logic::UriHelpers
      include Onetime::Logic::GuestRouteGating

      # Include organization context for classes that use Incoming::Logic::Base
      def self.included(base)
        base.include Onetime::Logic::OrganizationContext
      end

      # Transform response data to Incoming API format
      #
      # Incoming API follows V3 conventions:
      # - Remove "success" field (use HTTP status codes)
      # - Native JSON types (numbers, booleans, null)
      #
      # @return [Hash] Incoming API-formatted response data
      def success_data
        # Get the base response data
        base_data = super

        # Transform for Incoming API (V3 conventions)
        api_data = base_data.dup

        # Remove success field (use HTTP status codes)
        api_data.delete(:success)
        api_data.delete('success')

        api_data
      end
    end
  end
end
