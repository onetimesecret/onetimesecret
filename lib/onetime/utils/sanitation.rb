# lib/onetime/utils/sanitation.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    module Sanitation
      # Converts a Ruby value into a JavaScript-friendly string or JSON.
      # This ensures special characters are properly escaped or converted to JSON.
      def normalize_value(value)
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
          # Just totally give up if we don't know what to do with it, log
          # an error, and return an empty string so the page doesn't break.
          OT.le "Unsupported type: #{value.class} (#{value})"
          ''
        end
      end

      def https?(str)
        uri = URI.parse(str)
        uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
