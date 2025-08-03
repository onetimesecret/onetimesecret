# apps/web/core/views/helpers/sanitizer.rb

# SanitizerHelpers provides methods for sanitizing data before rendering in views.
#
# This module handles JSON serialization, HTML escaping, and caching to prevent
# common security issues like XSS attacks and ensure proper data rendering.
#
module Core
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
        data = serialized_data
        nonce = view_vars['nonce']
        element_id = view_vars['script_element_id']
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
        attributes = ['type="application/json"']
        attributes << %{id="#{Rack::Utils.escape_html(id)}"} if id
        attributes << %{nonce="#{nonce}"} if nonce

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
    end

  end
end
