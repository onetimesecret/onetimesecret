# apps/api/v3/logic/base.rb
#
# frozen_string_literal: true

# V3 Logic Base Module
#
# Extends V2 logic with modern REST API patterns for v3.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
#
# V3 classes include this module to inherit v2 business logic while
# transforming responses to follow v3 API conventions.

# require_relative '../../v2/logic/base'

require 'onetime/logic/base'
require 'onetime/logic/organization_context'
require 'onetime/logic/guest_route_gating'

module V3
  module Logic
    class Base < Onetime::Logic::Base
      include V2::Logic::UriHelpers
      include Onetime::Logic::GuestRouteGating

      # Include organization context for classes that use V3::Logic::Base
      # without inheriting from V2::Logic::Base
      def self.included(base)
        base.include Onetime::Logic::OrganizationContext
      end

      # V3-specific serialization helper
      #
      # Converts Familia model to JSON hash with native types.
      # Unlike v2's safe_dump which converts all primitives to strings,
      # this preserves JSON types from Familia v2's native storage.
      #
      # @param model [Familia::Horreum] Model instance to serialize
      # @return [Hash] JSON-serializable hash with native types
      def json_dump(model)
        return nil if model.nil?

        # Familia v2 models store fields as JSON types already
        # We just need to convert the model to a hash without string coercion
        model.to_h
      end

      # Transform v2 response data to v3 format
      #
      # V3 API changes:
      # - Remove "success" field (use HTTP status codes)
      #
      # @return [Hash] v3-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for v3
        v3_data = v2_data.dup

        # Remove success field (v3 uses HTTP status codes)
        v3_data.delete(:success)
        v3_data.delete('success')

        v3_data
      end
    end
  end
end
