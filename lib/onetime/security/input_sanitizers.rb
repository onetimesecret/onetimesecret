# lib/onetime/security/input_sanitizers.rb
#
# frozen_string_literal: true

require 'sanitize'

module Onetime
  module Security
    # Centralized input sanitization methods for API logic classes.
    #
    # Layer-agnostic security module with no Rack dependencies.
    # Can be called from request handlers, background jobs, tests, or CLI tooling.
    #
    # Provides type-appropriate sanitization:
    # - Identifiers: strict allowlist (alphanumeric, underscore, hyphen)
    # - Plain text: strip HTML tags, normalize whitespace
    # - Email: lowercase, strip whitespace (validation handles format)
    #
    # Usage:
    #   Include in logic classes that process user input:
    #     include Onetime::Security::InputSanitizers
    #
    #   Then call appropriate sanitizer in process_params:
    #     @extid = sanitize_identifier(params['extid'])
    #     @display_name = sanitize_plain_text(params['display_name'], max_length: 100)
    #     @contact_email = sanitize_email(params['contact_email'])
    #
    module InputSanitizers
      # Regex patterns for input sanitization
      # Defined as constants to avoid recompilation and improve reviewability

      # Matches any character NOT in the identifier allowlist [a-zA-Z0-9_-]
      IDENTIFIER_STRIP_PATTERN = /[^a-zA-Z0-9_-]/

      # Matches one or more whitespace characters for normalization
      WHITESPACE_NORMALIZE_PATTERN = /\s+/

      # Matches newline characters (CR, LF) for header injection prevention
      NEWLINE_STRIP_PATTERN = /[\r\n]/

      # Matches any character NOT valid in IPv4/IPv6/CIDR notation
      # Allows: 0-9, a-f, A-F (hex), dots, colons, forward slash
      IP_ADDRESS_STRIP_PATTERN = %r{[^0-9a-fA-F.:/]}

      # Sanitize identifiers (extid, objid, custid, etc.)
      #
      # Uses strict allowlist to permit only safe characters.
      # Does NOT use HTML sanitization - identifiers should never contain HTML.
      #
      # @param value [String, nil] The identifier value to sanitize
      # @return [String] Sanitized identifier with only allowed characters
      def sanitize_identifier(value)
        value.to_s.gsub(IDENTIFIER_STRIP_PATTERN, '')
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
        result = Sanitize.fragment(value.to_s).strip.gsub(WHITESPACE_NORMALIZE_PATTERN, ' ')
        max_length ? result.slice(0, max_length) : result
      end

      # Sanitize email addresses
      #
      # Strips HTML tags (defense-in-depth), lowercases, trims whitespace,
      # and removes newlines to prevent email header injection attacks.
      # Validation (format checking) is handled separately by valid_email?
      #
      # @param value [String, nil] The email value to sanitize
      # @return [String] Sanitized email, lowercase and stripped
      def sanitize_email(value)
        Sanitize.fragment(value.to_s).gsub(NEWLINE_STRIP_PATTERN, '').strip.downcase
      end

      # Sanitize IP addresses (IPv4 and IPv6) with optional CIDR notation
      #
      # Uses allowlist to permit only valid IP address characters.
      # Does NOT validate the IP format - that should be done separately.
      # Allows: digits, dots (IPv4), colons (IPv6), hex letters (IPv6), slash (CIDR)
      #
      # @param value [String, nil] The IP address value to sanitize
      # @return [String] Sanitized IP address with only allowed characters
      def sanitize_ip_address(value)
        value.to_s.gsub(IP_ADDRESS_STRIP_PATTERN, '')
      end
    end
  end
end
