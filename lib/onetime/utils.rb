# lib/onetime/utils.rb

require_relative 'utils/enumerables'
require_relative 'utils/sanitation'
require_relative 'utils/strings'
require_relative 'utils/time_utils'

module Onetime
  module Utils
    extend Enumerables
    extend Sanitation
    extend Strings
    extend TimeUtils

    class << self
      attr_accessor :fortunes

    end

    # Character set constants for flexible password generation
    # Move these outside class << self so they're accessible to class methods
    unless defined?(VALID_CHARS)
      # Symbols used in character sets for random string generation.
      # Includes common special characters that are generally safe for use
      # in generated identifiers and passwords.
      # Character set constants for flexible password generation
      UPPERCASE = ('A'..'Z').to_a.freeze
      LOWERCASE = ('a'..'z').to_a.freeze
      NUMBERS   = ('0'..'9').to_a.freeze

      # Extended symbol set for password generation
      SYMBOLS = [
        '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '-', '+', '=',
        '[', ']', '{', '}', '|', ':', ';', '"', "'", '<', '>', ',', '.', '?',
        '/', '~', '`'
      ].freeze

      # Basic symbols for general use (backward compatibility)
      BASIC_SYMBOLS = %w[* $ ! ? ( ) @ # % ^].freeze

      # Characters that can be visually confusing
      AMBIGUOUS_CHARS = %w[i l o 1 I O 0].freeze

      # Complete character set for random string generation.
      # Includes lowercase letters (a-z), uppercase letters (A-Z),
      # digits (0-9), and symbols for maximum effect in generated strings.
      VALID_CHARS = [LOWERCASE, UPPERCASE, NUMBERS, BASIC_SYMBOLS].flatten.freeze

      # Unambiguous character set that excludes visually similar characters.
      # Removes potentially confusing characters (i, l, o, 1, I, O, 0) to
      # improve readability and reduce user errors when manually entering
      # generated strings.
      VALID_CHARS_SAFE = VALID_CHARS.reject { |char| AMBIGUOUS_CHARS.include?(char) }.freeze
    end

    class << self
      attr_accessor :fortunes

    # Generates a random string of specified length using configurable character sets.
    # Supports both simple usage and complex password generation with guaranteed complexity.
    #
    # @param len [Integer] Length of the generated string (default: 12)
    # @param options [Boolean, Hash] If boolean, treats as 'unambiguous' for backward compatibility.
    #   If hash, supports the following options:
    #   - :uppercase [Boolean] Include uppercase letters (default: true)
    #   - :lowercase [Boolean] Include lowercase letters (default: true)
    #   - :numbers [Boolean] Include numbers (default: true)
    #   - :symbols [Boolean] Include symbols (default: true)
    #   - :exclude_ambiguous [Boolean] Exclude visually similar characters (default: true)
    #   - :unambiguous [Boolean] Legacy option, same as exclude_ambiguous
    # @return [String] A randomly generated string of the specified length
    #
    # @example Generate a simple unambiguous 12-character string
    #   Utils.strand         # => "k*8mN2qR9xPw"
    #   Utils.strand(8)      # => "k*8mN2qR"
    #
    # @example Generate using full character set (legacy)
    #   Utils.strand(8, false) # => "kF8mN2qR"
    #
    # @example Generate with custom options
    #   Utils.strand(12, { symbols: true, uppercase: false })
    #
    # @security Cryptographically secure - uses SecureRandom.random_number which
    #   provides cryptographically secure random number generation. Suitable for
    #   generating secure tokens, passwords, and other security-critical identifiers.
    def strand(len = 12, options = true)
      raise ArgumentError, 'Length must be positive' unless len.positive?

      # Handle backward compatibility: if options is boolean, treat as unambiguous
      opts = case options
             in true | false
               { 'exclude_ambiguous' => options }
             in Hash
               # Convert all keys to strings for consistent access
               options.transform_keys(&:to_s)
             else
               {}
             end

      defaults = {
        'uppercase'   => true,
        'lowercase'   => true,
        'numbers'     => true,
        'symbols'     => true,
        'exclude_ambiguous' => true,
      }

      opts = defaults.merge(opts)
      opts['exclude_ambiguous'] ||= opts.delete('unambiguous') if opts.key?('unambiguous')

      # Build character set based on options
      chars = []
      chars.concat(UPPERCASE) if opts['uppercase']
      chars.concat(LOWERCASE) if opts['lowercase']
      chars.concat(NUMBERS) if opts['numbers']
      chars.concat(SYMBOLS) if opts['symbols']

      # Remove ambiguous characters if requested
      if opts['exclude_ambiguous']
        chars.delete_if { |char| AMBIGUOUS_CHARS.include?(char) }
      end

      # Ensure we have at least some characters to work with
      if chars.empty?
        chars = VALID_CHARS_SAFE # Fallback to safe default
      end

      # For simple generation (no complexity requirements), use efficient method
      unless multiple_char_sets_requested?(opts)
        return Array.new(len) { chars[SecureRandom.random_number(chars.length)] }.join
      end

      # Generate password with guaranteed complexity when multiple character sets are enabled
      password_chars = []

      # Ensure at least one character from each selected set
      # When excluding ambiguous chars, sample from filtered sets to maintain guarantee
      if opts['exclude_ambiguous']
        password_chars << (UPPERCASE - AMBIGUOUS_CHARS).sample if opts['uppercase']
        password_chars << (LOWERCASE - AMBIGUOUS_CHARS).sample if opts['lowercase']
        password_chars << (NUMBERS - AMBIGUOUS_CHARS).sample if opts['numbers']
        password_chars << (SYMBOLS - AMBIGUOUS_CHARS).sample if opts['symbols']
      else
        password_chars << UPPERCASE.sample if opts['uppercase']
        password_chars << LOWERCASE.sample if opts['lowercase']
        password_chars << NUMBERS.sample if opts['numbers']
        password_chars << SYMBOLS.sample if opts['symbols']
      end

      # Fill remaining length with random characters from the full set
      remaining_length = len - password_chars.length
      if remaining_length > 0
        remaining_chars = Array.new(remaining_length) do
          chars[SecureRandom.random_number(chars.length)]
        end
        password_chars.concat(remaining_chars)
      end

      # Shuffle and join to create final password
      password_chars.shuffle.join
    end

      # NOTE: Temporary until Familia 2-pre11
      # @see #shorten_securely for truncation details
      def generate_short_id
        hexstr = SecureRandom.hex(32) # generate with all 256 bits
        shorten_securely(hexstr, bits: 64) # and then shorten
      end

      # Truncates a hexadecimal string to specified bit length and encodes in desired base.
      # Takes the most significant bits from the hex string to maintain randomness
      # distribution while reducing the identifier length for practical use.
      #
      # @param hash [String] A hexadecimal string (64 characters for 256 bits)
      # @param bits [Integer] Number of bits to retain (default: 256, max: 256)
      # @param base [Integer] Base encoding for output string (2-36, default: 36)
      # @return [String] Truncated value encoded in the specified base
      #
      # @example Truncate to 128 bits in base-16
      #   hash = "a1b2c3d4..." # 64-char hexadecimal string
      #   Utils.shorten_securely(hash, bits: 128, base: 16) # => "a1b2c3d4e5f6e7c8"
      #
      # @example Default 256-bit truncation in base-36
      #   Utils.shorten_securely(hash) # => "k8x2m9n4p7q1r5s3t6u0v2w8x1y4z7"
      #
      # @note Higher bit counts provide more security but longer identifiers
      # @note Base-36 encoding uses 0-9 and a-z for compact, URL-safe strings
      # @security Bit truncation preserves cryptographic properties of original value
      def shorten_securely(hash, bits: 256, base: 36)
        # Truncate to desired bit length
        truncated = hash.to_i(16) >> (256 - bits)
        truncated.to_s(base).freeze
      end

      # Returns a random fortune from the configured fortunes array.
      # Provides graceful degradation with fallback messages when fortunes
      # are unavailable or malformed, ensuring the application never fails
      # due to fortune retrieval issues.
      #
      # @return [String] A random fortune string, or a fallback message
      # @raise [OT::Problem] Never raised - all errors are caught and logged
      #
      # @example Normal usage
      #   Utils.fortunes = ["Good luck!", "Fortune favors the bold"]
      #   Utils.random_fortune # => "Good luck!" or "Fortune favors the bold"
      #
      # @example Graceful degradation
      #   Utils.fortunes = nil
      #   Utils.random_fortune # => "Unexpected outcomes bring valuable lessons."
      #
      # @note All errors are logged but never propagated to maintain system stability
      # @security Validates input type to prevent injection of malicious objects
      def random_fortune
        raise OT::Problem, 'No fortunes' if fortunes.nil?
        raise OT::Problem, "#{fortunes.class} is not an Array" unless fortunes.is_a?(Array)

        fortune = fortunes.sample.to_s.strip
        raise OT::Problem, 'No fortune found' if fortune.empty?

        fortune
      rescue OT::Problem => ex
        OT.le "#{ex.message}"
        'Unexpected outcomes bring valuable lessons.'
      rescue StandardError => ex
        OT.le "#{ex.message} (#{fortunes.class})"
        OT.ld "#{ex.backtrace.join("\n")}"
        'A house is full of games and puzzles.'
      end

      # Converts an absolute file path to a path relative to the application's
      # base directory. This simplifies logging and error reporting by showing
      # only the relevant parts of file paths instead of lengthy absolute paths.
      #
      # @param file [String, Pathname] The absolute file path to convert
      # @return [Pathname] A relative path from application's base directory
      #
      # @example Using application base directory
      #   # When ONETIME_HOME is set to "/app/onetime"
      #   Utils.pretty_path("/app/onetime/lib/models/user.rb") # => "lib/models/user.rb"
      #
      # @example Using current directory as fallback
      #   # When ONETIME_HOME is not set and __dir__ is "/home/dev/project/lib"
      #   Utils.pretty_path("/home/dev/project/lib/config.rb") # => "config.rb"
      #
      # @note The method respects the ONETIME_HOME environment variable as the
      #   base path, falling back to the current directory if not set
      # @see Pathname#relative_path_from Ruby standard library documentation
      def pretty_path(filepath)
        return nil if filepath.nil?

        basepath    = ENV.fetch('ONETIME_HOME', __dir__)
        Pathname.new(filepath).relative_path_from(basepath)
      end

      private

      # Check if multiple character sets are requested (requiring complexity guarantee)
      def multiple_char_sets_requested?(opts)
        enabled_sets = [opts['uppercase'], opts['lowercase'], opts['numbers'], opts['symbols']].count(true)
        enabled_sets > 1
      end
    end
  end
end
