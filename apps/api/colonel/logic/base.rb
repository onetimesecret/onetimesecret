# apps/api/colonel/logic/base.rb
#
# frozen_string_literal: true

# Colonel API Logic Base Class
#
# Extends V2 logic with modern API patterns for Colonel API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Colonel API uses same modern conventions as v3 API for consistency.

require_relative '../../v2/logic/base'
require_relative '../../../../lib/onetime/application/authorization_policies'

module ColonelAPI
  module Logic
    class Base < V2::Logic::Base
      include Onetime::Application::AuthorizationPolicies

      using Familia::Refinements::TimeLiterals

      # Colonel API-specific serialization helper
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

      # Override safe_dump to use JSON types in Colonel API
      #
      # This allows Colonel logic classes to inherit from v2 but get JSON serialization
      # without modifying v2 behavior.
      alias safe_dump json_dump

      # Transform v2 response data to Colonel API format
      #
      # Colonel API changes (same as v3):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Colonel API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Colonel API
        colonel_data = v2_data.dup

        # Remove success field (Colonel API uses HTTP status codes)
        colonel_data.delete(:success)
        colonel_data.delete('success')

        # Rename custid to user_id (modern naming)
        if colonel_data.key?(:custid)
          colonel_data[:user_id] = colonel_data.delete(:custid)
        elsif colonel_data.key?('custid')
          colonel_data['user_id'] = colonel_data.delete('custid')
        end

        colonel_data
      end
    end
  end
end
