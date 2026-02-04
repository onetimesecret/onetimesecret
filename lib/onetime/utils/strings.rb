# lib/onetime/utils/strings.rb
#
# frozen_string_literal: true

require 'mail'
require 'public_suffix'

module Onetime
  module Utils
    module Strings
      unless defined?(VALID_CHARS)
        # Symbols used in character sets for random string generation.
        # Includes common special characters that are generally safe for use
        # in generated identifiers and passwords.
        SYMBOLS         = %w[* $ ! ? ( ) @ # % ^].freeze
        AMBIGUOUS_CHARS = %w[i l o 1 I O 0].freeze

        # Complete character set for random string generation.
        # Includes lowercase letters (a-z), uppercase letters (A-Z),
        # digits (0-9), and symbols for maximum effect in generated strings.
        VALID_CHARS = [
          ('a'..'z').to_a,
          ('A'..'Z').to_a,
          ('0'..'9').to_a,
          *SYMBOLS,
        ].flatten.freeze

        # Unambiguous character set that excludes visually similar characters.
        # Removes potentially confusing characters (i, l, o, 1, I, O, 0) to
        # improve readability and reduce user errors when manually entering
        # generated strings.
        VALID_CHARS_SAFE = VALID_CHARS.reject { |char| AMBIGUOUS_CHARS.include?(char) }.freeze
        TRUTHY_VALUES    = %w[1 true yes on y t].freeze
      end

      # Generates a random string of specified length using predefined
      # character sets. Offers both unambiguous and standard character sets for
      # different use cases.
      #
      # @param len [Integer] Length of the generated string (default: 12)
      # @param unambiguous [Boolean] Whether to use the unambiguous character set
      #   (default: true)
      # @return [String] A randomly generated string of the specified length
      #
      # @example Generate a unambiguous 12-character string
      #   Utils.strand         # => "kF8mN2qR9xPw"
      #   Utils.strand(8)      # => "kF8mN2qR"
      #
      # @example Generate using full character set
      #   Utils.strand(8, false) # => "il0O1o$!"
      #
      # @see VALID_CHARS for details on the complete character set
      # @see VALID_CHARS_SAFE for details on the unambiguous character set
      # @security Cryptographically secure - uses SecureRandom.random_number which
      #   provides cryptographically secure random number generation. Suitable for
      #   generating secure tokens, passwords, and other security-critical identifiers.
      def strand(len = 12, unambiguous = true)
        raise ArgumentError, 'Length must be positive' unless len.positive?

        chars        = unambiguous ? VALID_CHARS_SAFE : VALID_CHARS
        charset_size = chars.length

        Array.new(len) { chars[SecureRandom.random_number(charset_size)] }.join
      end

      # Configuration constants for email masking
      EMAIL_MASK_MIN_LOCAL = 2    # chars to keep at start of local part
      EMAIL_MASK_CHAR      = '*'  # masking character
      EMAIL_MASK_LENGTH    = 3    # number of mask characters

      # RFC 5321/5322-compliant email pattern for matching
      # Supports: local-part@domain where local-part allows dots, plus, etc.
      # This pattern is intentionally permissive to catch edge cases while
      # Mail::Address handles validation during parsing.
      EMAIL_PATTERN = /
        \b
        [A-Z0-9._%+'-]+   # local part: alphanumeric, dots, plus, etc.
        @
        [A-Z0-9.-]+       # domain: alphanumeric, dots, hyphens
        \.
        [A-Z]{2,}         # TLD: at least 2 letters
        \b
      /ix

      # Obscures email addresses by replacing most characters with asterisks
      # while preserving a minimal prefix for partial readability. Uses the
      # mail gem's Address parser for robust email handling.
      #
      # @param text [String] Text containing email addresses to obscure
      # @return [String] Text with email addresses masked
      #
      # @example Basic usage
      #   obscure_email("Contact tom@myspace.com please")
      #   # => "Contact to***@m***.com please"
      #
      # @example Short local part
      #   obscure_email("a@example.org")
      #   # => "a@e***.org"
      #
      # @example Subdomain handling
      #   obscure_email("user@mail.example.co.uk")
      #   # => "us***@m***.co.uk"
      #
      # @note Uses Mail::Address for parsing, avoiding hand-rolled parsing
      #   edge cases while keeping the code short and auditable.
      def obscure_email(text)
        return text if text.nil? || text.empty?

        text.gsub(EMAIL_PATTERN) do |raw|
          mask_email_address(raw)
        end
      end

      # Checks if a value represents a truthy boolean value
      # @param value [Object] Value to check
      # @return [Boolean] true if value one of the TRUTHY_VALUES (case-insensitive)
      def yes?(value)
        !value.to_s.empty? && TRUTHY_VALUES.include?(value.to_s.downcase)
      end

      private

      # Masks a single email address string
      # @param raw [String] Raw email address to mask
      # @return [String] Masked email address, or original if parsing fails
      def mask_email_address(raw)
        addr = Mail::Address.new(raw)
        return raw unless addr.local && addr.domain

        local  = mask_string_head(addr.local, EMAIL_MASK_MIN_LOCAL)
        domain = mask_domain(addr.domain)
        "#{local}@#{domain}"
      rescue Mail::Field::ParseError
        raw
      end

      # Splits domain and masks the host portion, preserving TLD
      # Uses PublicSuffix for reliable TLD detection (handles .co.uk, .com.au, etc.)
      # @param domain [String] Full domain (e.g., "mail.example.co.uk")
      # @return [String] Masked domain (e.g., "m***.co.uk")
      def mask_domain(domain)
        parsed = PublicSuffix.parse(domain, ignore_private: true)

        # Build host from subdomain (trd) and second-level domain (sld)
        host = parsed.trd ? "#{parsed.trd}.#{parsed.sld}" : parsed.sld
        tld  = parsed.tld

        return tld if host.nil? || host.empty?

        masked_host = mask_string_head(host, 1)
        "#{masked_host}.#{tld}"
      rescue PublicSuffix::DomainNotAllowed, PublicSuffix::DomainInvalid
        # Fallback for invalid/unlisted domains: mask first part, keep rest
        parts = domain.split('.')
        return domain if parts.size < 2

        "#{mask_string_head(parts.first, 1)}.#{parts[1..].join('.')}"
      end

      # Masks a string keeping only the first N characters visible
      # @param str [String] String to mask
      # @param keep_head [Integer] Number of leading characters to preserve
      # @return [String] Masked string
      def mask_string_head(str, keep_head)
        return str if str.nil? || str.length <= keep_head

        visible = str[0, keep_head]
        "#{visible}#{EMAIL_MASK_CHAR * EMAIL_MASK_LENGTH}"
      end
    end
  end
end
