# lib/onetime/security/input_sanitizers.rb
#
# frozen_string_literal: true

require 'cgi'
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
      # We store plain text and render plain text, but sanitize in the
      # middle using HTML-centric tools. Sanitize.fragment returns HTML
      # (`R&D` → `R&amp;D`, `x < 5` → `x &lt; 5`, U+00A0 → `&nbsp;`), so the
      # final step decodes the entities it introduces to get back to plain
      # text for storage.
      #
      # Strips all HTML tags and decodes HTML entities so the stored value
      # is raw text. Frontend frameworks (Vue, React) handle output encoding
      # on render, so storing pre-encoded entities causes double-encoding
      # (e.g. `R&D` → `R&amp;D` in storage → `R&amp;amp;D` on screen).
      #
      # @param value [String, nil] The text value to sanitize
      # @param max_length [Integer, nil] Optional maximum length
      # @return [String] Sanitized plain text with HTML stripped, entities decoded,
      #   and whitespace normalized
      def sanitize_plain_text(value, max_length: nil)
        # Decode-then-sanitize in a loop until output stabilizes. A single
        # pass misses multiply-encoded payloads (e.g. &amp;lt;script&amp;gt;)
        # where step-1 decode reveals entity-encoded tags that Sanitize
        # preserves, and a final blanket decode would re-introduce them.
        result            = value.to_s
        max_decode_passes = 10
        converged         = false
        max_decode_passes.times do
          decoded   = CGI.unescapeHTML(result)
          sanitized = Sanitize.fragment(decoded)
          if sanitized == result
            converged = true
            break
          end

          result = sanitized
        end

        # Fail closed. A payload still changing after ten decode passes is
        # nested encoding (`&amp;amp;...lt;script`), and decoding it below
        # would hand back live markup. No legitimate text needs that depth.
        return '' unless converged

        # At the fixed point, decoding `result` gives text that Sanitize only
        # re-encoded (it stripped nothing), so a full decode is safe and is
        # what makes the stored value plain text again. Decode through
        # Nokogiri, not CGI.unescapeHTML: Sanitize's serializer emits
        # `&nbsp;` for U+00A0 and CGI leaves named entities alone, which
        # used to store `a&nbsp;b` and `x &lt; 5` as literal entity text.
        result = Nokogiri::HTML5.fragment(result).text
        result = result.strip.gsub(WHITESPACE_NORMALIZE_PATTERN, ' ')
        max_length ? result.slice(0, max_length) : result
      end

      # Sanitize strings that we area treating as email addresses.
      #
      # NOTE: This is not a validator. It treats the input as a string that
      # is presumed to be an email address.
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
