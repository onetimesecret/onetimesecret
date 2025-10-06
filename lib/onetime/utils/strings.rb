# lib/onetime/utils/strings.rb

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

      # Obscures email addresses by replacing most characters with asterisks
      # while preserving the first few and last characters of both the local
      # and domain parts for partial readability.
      #
      # @param text [String] Text containing email addresses to obscure
      # @return [String] Text with email addresses obscured in the format:
      #   "ab*****c@d*****com" where visible characters are preserved from
      #   the beginning and end of each part
      #
      # @example
      #   obscure_email("Contact tom@myspace.com for help")
      #   # => "Contact to*****e@m******.com for help"
      #
      # @note The method uses a regex to identify email patterns and replaces
      #   the middle portions with asterisks while keeping structural elements
      #   visible for context.
      def obscure_email(text)
        email_pattern = /\b([A-Z0-9]{1,2})([A-Z0-9._%-]*)([A-Z0-9])?@([A-Z0-9])([A-Z0-9.-]+)(\.[A-Z]{2,4}\b)/i

        text.gsub(email_pattern) do |_match|
          local_start  = ::Regexp.last_match(1)
          _            = ::Regexp.last_match(2)
          local_end    = ::Regexp.last_match(3)
          domain_start = ::Regexp.last_match(4)
          _            = ::Regexp.last_match(5)
          domain_end   = ::Regexp.last_match(6)
          "#{local_start}*****#{local_end}@#{domain_start}*****#{domain_end}"
        end
      end

      # Checks if a value represents a truthy boolean value
      # @param value [Object] Value to check
      # @return [Boolean] true if value one of the TRUTHY_VALUES (case-insensitive)
      def yes?(value)
        !value.to_s.empty? && TRUTHY_VALUES.include?(value.to_s.downcase)
      end
    end
  end
end
