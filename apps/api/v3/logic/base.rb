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
# 3. Modern naming - "user_id" instead of "custid"
#
# V3 classes include this module to inherit v2 business logic while
# transforming responses to follow v3 API conventions.

# require_relative '../../v2/logic/base'

module V3
  module Logic
    module Base
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

      # Override safe_dump to use JSON types in v3
      #
      # This allows v3 logic classes to inherit from v2 but get JSON serialization
      # without modifying v2 behavior.
      alias safe_dump json_dump

      # Transform v2 response data to v3 format
      #
      # V3 API changes:
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
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

        # Rename custid to user_id (modern naming)
        if v3_data.key?(:custid)
          v3_data[:user_id] = v3_data.delete(:custid)
        elsif v3_data.key?('custid')
          v3_data['user_id'] = v3_data.delete('custid')
        end

        v3_data
      end
    end
  end
end
