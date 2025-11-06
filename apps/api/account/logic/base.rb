# apps/api/account/logic/base.rb

# Account API Logic Base Class
#
# Extends V2 logic with JSON-type aware serialization for Account API.
# Returns native JSON types (numbers, booleans, null) instead of
# string-serialized values.

require_relative '../../v2/logic/base'

module AccountAPI
  module Logic
    module Base
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
    end
  end
end
