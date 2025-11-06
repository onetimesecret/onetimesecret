# apps/api/account/logic/base.rb

# Account API Logic Base Class
#
# Extends V2 logic with modern API patterns for Account API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Account API uses same modern conventions as v3 API for consistency.

require_relative '../../v2/logic/base'

module AccountAPI
  module Logic
    class Base < V2::Logic::Base
      # Account API-specific serialization helper
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

      # Override safe_dump to use JSON types in Account API
      #
      # This allows Account logic classes to inherit from v2 but get JSON serialization
      # without modifying v2 behavior.
      alias safe_dump json_dump

      # Transform v2 response data to Account API format
      #
      # Account API changes (same as v3):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Account API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Account API
        account_data = v2_data.dup

        # Remove success field (Account API uses HTTP status codes)
        account_data.delete(:success)
        account_data.delete('success')

        # Rename custid to user_id (modern naming)
        if account_data.key?(:custid)
          account_data[:user_id] = account_data.delete(:custid)
        elsif account_data.key?('custid')
          account_data['user_id'] = account_data.delete('custid')
        end

        account_data
      end
    end
  end
end
