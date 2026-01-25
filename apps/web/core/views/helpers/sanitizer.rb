# apps/web/core/views/helpers/sanitizer.rb
#
# frozen_string_literal: true

# SanitizerHelpers provides methods for sanitizing data before rendering in views.
#
# This module handles JSON serialization for script tags, preventing XSS attacks
# through proper escaping of script tag boundaries and control characters.
#
module Core
  module Views
    module SanitizerHelpers
      # Serializes view data to a script tag for frontend consumption.
      #
      # @return [String] HTML script tag containing serialized data
      def serialized_to_script
        data       = serialized_data
        nonce      = view_vars['nonce']
        element_id = view_vars['script_element_id']
        to_json_script(data, id: element_id, nonce: nonce)
      end

      # Valid CSP nonce format: base64 characters only (alphanumeric, +, /, =)
      VALID_NONCE_PATTERN = %r{\A[A-Za-z0-9+/=]+\z}

      # Converts data to a script tag with sanitized JSON content.
      #
      # @param data [Hash, Array] Data to convert to JSON
      # @param id [String, nil] Optional ID attribute for the script tag
      # @param nonce [String, nil] Optional Content Security Policy nonce (must be base64 format)
      # @return [String] HTML script tag with sanitized JSON
      def to_json_script(data, id: nil, nonce: nil)
        sanitized_json = to_sanitized_json(data)
        attributes     = ['type="application/json"']
        attributes << %(id="#{Rack::Utils.escape_html(id)}") if id
        attributes << %(nonce="#{nonce}") if nonce&.match?(VALID_NONCE_PATTERN)

        "<script #{attributes.join(' ')}>#{sanitized_json}</script>"
      end

      # Converts data to sanitized JSON to prevent XSS attacks.
      #
      # Escapes script tag boundaries and control characters to prevent
      # injection when embedding JSON in HTML script tags.
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
