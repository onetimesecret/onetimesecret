# apps/web/manifold/views/helpers/sanitizer.rb

# SanitizerHelpers provides methods for sanitizing data before rendering in views.
#
# This module handles JSON serialization, HTML escaping, and caching to prevent
# common security issues like XSS attacks and ensure proper data rendering.
#
module Manifold
  module Views
    module SanitizerHelpers
      # Normalizes values to prevent injection attacks and ensure consistent formatting.
      #
      # @param value [String, Array, Hash] The value to normalize
      # @return [String, Array, Hash] The normalized value
      def normalize_value(value)
        Onetime::Utils.normalize_value(value)
      end

      # Serializes view data to a script tag for frontend consumption.
      #
      # @return [String] HTML script tag containing serialized data
      def serialized_to_script
        data       = serialized_data
        nonce      = view_vars[:nonce]
        element_id = view_vars[:script_element_id]
        to_json_script(data, id: element_id, nonce: nonce)
      end

      # Converts data to a script tag with sanitized JSON content.
      #
      # @param data [Hash, Array] Data to convert to JSON
      # @param id [String, nil] Optional ID attribute for the script tag
      # @param nonce [String, nil] Optional Content Security Policy nonce
      # @return [String] HTML script tag with sanitized JSON
      def to_json_script(data, id: nil, nonce: nil)
        sanitized_json = to_sanitized_json(data)
        attributes     = ['type="application/json"']
        attributes << %(id="#{Rack::Utils.escape_html(id)}") if id
        attributes << %(nonce="#{nonce}") if nonce

        "<script #{attributes.join(' ')}>#{sanitized_json}</script>"
      end

      # Converts data to sanitized JSON to prevent XSS attacks.
      #
      # @param data [Hash, Array] Data to convert to JSON
      # @return [String] Sanitized JSON string
      def to_sanitized_json(data)
        data.to_json
          .gsub(%r{</script}i, '<\/script')
          .gsub(/[\u0000-\u001F]/, '')
          .gsub(/[^\x20-\x7E]/) { |c| "\\u#{c.ord.to_s(16).rjust(4, '0')}" }
      end

      # Caches the result of a method call for a specified duration.
      #
      # This method is used to cache the result of expensive operations, such as
      # asset generation, in Redis. It provides a simple way to implement caching
      # for view helpers or other frequently called methods.
      #
      # @param methname [String] The name of the method being cached.
      # @yield The block of code to execute if the cache is empty.
      # @return [String] The cached content or the result of the block execution.
      #
      # @example
      #   cached_method('generate_asset') do
      #     # Expensive operation to generate an asset
      #     Asset.generate_complex_asset
      #   end
      #
      # @note The cache key is prefixed with "template:global:" and stored in Redis db 0.
      # @note The default Time To Live (TTL) for the cache is 1 hour.
      #
      def cached_method(methname)
        dbkey     = "template:global:#{methname}"
        cache_object = Familia::String.new dbkey, default_expiration: 1.hour, logical_database: 0
        OT.ld "[cached_method] #{methname} #{cache_object.exists? ? 'hit' : 'miss'} #{dbkey}"
        cached       = cache_object.get
        return cached if cached

        # Existing logic to generate assets...
        content = yield

        # Cache the generated content
        cache_object.set(content)

        content
      end
    end
  end
end
