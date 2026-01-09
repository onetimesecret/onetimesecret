# lib/onetime/security/output_escaper.rb
#
# frozen_string_literal: true

require 'uri'

module Onetime
  module Security
    # Output escaping for safe rendering in views and JSON responses.
    #
    # Converts Ruby values into JavaScript-friendly strings with proper escaping
    # to prevent XSS attacks and ensure consistent data formatting.
    #
    # Note: This module uses Rack::Utils.escape_html for HTML escaping.
    # While it has a Rack dependency, the escaping logic is view-layer specific
    # and benefits from Rack's well-tested implementation.
    #
    # Usage:
    #   extend Onetime::Security::OutputEscaper
    #
    #   escape_for_output(user_input)  # => HTML-escaped string
    #
    module OutputEscaper
      # Converts a Ruby value into a JavaScript-friendly string or JSON.
      # Ensures special characters are properly escaped or converted to JSON.
      #
      # @param value [String, Symbol, Integer, Float, Array, Hash, Boolean, nil] The value to escape
      # @return [String, Array, Hash, nil] The escaped value safe for output
      def escape_for_output(value)
        case value.class.to_s
        when 'String', 'Symbol', 'Integer', 'Float'
          if https?(value)
            value
          else
            Rack::Utils.escape_html(value)
          end
        # JSON-compatible types are passed through as-is
        when 'Array', 'Hash', 'Boolean', 'FalseClass', 'TrueClass'
          value
        when 'NilClass'
          nil
        else
          # Log error for unsupported types, return empty string so page doesn't break
          OT.le "Unsupported type: #{value.class} (#{value})"
          ''
        end
      end

      # Legacy alias for backward compatibility
      alias normalize_value escape_for_output

      private

      def https?(str)
        uri = URI.parse(str)
        uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
