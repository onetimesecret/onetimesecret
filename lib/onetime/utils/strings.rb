# lib/onetime/utils/strings.rb

module Onetime
  module Utils
    module Strings
      unless defined?(VALID_CHARS)
        # Symbols used in character sets for random string generation.
        # Includes common special characters that are generally safe for use
        # in generated identifiers and passwords.
        SYMBOLS = %w[* $ ! ? ( ) @ # % ^]

        # Complete character set for random string generation.
        # Includes lowercase letters (a-z), uppercase letters (A-Z),
        # digits (0-9), and symbols for maximum entropy in generated strings.
        VALID_CHARS = [
          ('a'..'z').to_a,
          ('A'..'Z').to_a,
          ('0'..'9').to_a,
          SYMBOLS,
        ].flatten.freeze

        # Unambiguous character set that excludes visually similar characters.
        # Removes potentially confusing characters (i, l, o, 1, I, O, 0) to
        # improve readability and reduce user errors when manually entering
        # generated strings.
        VALID_CHARS_SAFE = VALID_CHARS.reject { |char| %w[i l o 1 I O 0].include?(char) }.freeze

        SYMBOLS.freeze
        VALID_CHARS.freeze
        VALID_CHARS_SAFE.freeze
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

      def obscure_email(text)
        regex = /(\b(([A-Z0-9]{1,2})[A-Z0-9._%-]*)([A-Z0-9])?(@([A-Z0-9])[A-Z0-9.-]+(\.[A-Z]{2,4}\b)))/i
        text.split('@')
        text.gsub regex, '\\3*****\\4@\\6*****\\7'
      end
      # rubocop:enable Layout/LineLength

      # Checks if a value represents a truthy boolean value
      # @param value [Object] Value to check
      # @return [Boolean] true if value is "true", "yes", or "1" (case-insensitive)
      def yes?(value)
        !value.to_s.empty? && %w[true yes 1].include?(value.to_s.downcase)
      end
    end
  end
end
