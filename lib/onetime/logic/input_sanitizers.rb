# lib/onetime/logic/input_sanitizers.rb
#
# frozen_string_literal: true

require 'sanitize'

module Onetime
  module Logic
    # Centralized input sanitization methods for API logic classes.
    #
    # Provides type-appropriate sanitization:
    # - Identifiers: strict allowlist (alphanumeric, underscore, hyphen)
    # - Plain text: strip HTML tags, normalize whitespace
    # - Email: lowercase, strip whitespace (validation handles format)
    #
    # Usage:
    #   Include in logic classes that process user input:
    #     include Onetime::Logic::InputSanitizers
    #
    #   Then call appropriate sanitizer in process_params:
    #     @extid = sanitize_identifier(params['extid'])
    #     @display_name = sanitize_plain_text(params['display_name'], max_length: 100)
    #     @contact_email = sanitize_email(params['contact_email'])
    #
    module InputSanitizers
      # Sanitize identifiers (extid, objid, custid, etc.)
      #
      # Uses strict allowlist to permit only safe characters.
      # Does NOT use HTML sanitization - identifiers should never contain HTML.
      #
      # @param value [String, nil] The identifier value to sanitize
      # @return [String] Sanitized identifier with only allowed characters
      def sanitize_identifier(value)
        value.to_s.gsub(/[^a-zA-Z0-9_-]/, '')
      end

      # Sanitize plain text input (display names, titles, descriptions)
      #
      # Strips all HTML tags and normalizes whitespace.
      # Use for text that should never contain HTML markup.
      #
      # @param value [String, nil] The text value to sanitize
      # @param max_length [Integer, nil] Optional maximum length
      # @return [String] Sanitized text with HTML stripped and whitespace normalized
      def sanitize_plain_text(value, max_length: nil)
        result = Sanitize.fragment(value.to_s).strip.gsub(/\s+/, ' ')
        max_length ? result.slice(0, max_length) : result
      end

      # Sanitize email addresses
      #
      # Strips HTML tags (defense-in-depth), lowercases, and trims whitespace.
      # Validation (format checking) is handled separately by valid_email?
      #
      # @param value [String, nil] The email value to sanitize
      # @return [String] Sanitized email, lowercase and stripped
      def sanitize_email(value)
        Sanitize.fragment(value.to_s).strip.downcase
      end
    end
  end
end
