# lib/onetime/utils.rb

require_relative 'utils/sanitize'
require_relative 'utils/time_utils'

module Onetime
  module Utils

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

    class << self
      attr_accessor :fortunes

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
        raise ArgumentError, "Length must be positive" unless len.positive?

        chars = unambiguous ? VALID_CHARS_SAFE : VALID_CHARS
        charset_size = chars.length

        Array.new(len) { chars[SecureRandom.random_number(charset_size)] }.join
      end

      # Generates a cryptographically secure identifier using SecureRandom.
      # Creates a random hexadecimal string and converts it to base-36 encoding
      # for a compact, URL-safe identifier.
      #
      # @return [String] A secure identifier in base-36 encoding
      #
      # @example Generate a 256-bit ID in base-36
      #   Utils.generate_id # => "25nkfebno45yy36z47ffxef2a7vpg4qk06ylgxzwgpnz4q3os4"
      #
      # @security Uses SecureRandom for cryptographic entropy
      # @see #convert_base_string for base conversion details
      def generate_id
        hexstr = SecureRandom.hex(32)
        convert_base_string(hexstr)
      end

      # Generates a cryptographically secure short identifier by creating
      # a 256-bit random value and then truncating it to 64 bits for a
      # shorter but still secure identifier.
      #
      # @return [String] A secure short identifier in base-36 encoding
      #
      # @example Generate a 64-bit short ID
      #   Utils.generate_short_id # => "k8x2m9n4p7q1"
      #
      # @security Uses SecureRandom for entropy with secure bit truncation
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
        convert_base_string(truncated.to_s, base: base)
      end

      # Converts a string representation of a number from one base to another.
      # This utility method is flexible, allowing conversions between any bases
      # supported by Ruby's `to_i` and `to_s` methods (i.e., 2 to 36).
      #
      # @param value_str [String] The string representation of the number to convert.
      # @param from_base [Integer] The base of the input `value_str` (default: 16).
      # @param base [Integer] The target base for the output string (default: 36).
      # @return [String] The string representation of the number in the `base`.
      # @raise [ArgumentError] If `from_base` or `base` are outside the valid range (2-36).
      def convert_base_string(value_str, from_base: 16, base: 36)
        unless from_base.between?(2, 36) && base.between?(2, 36)
          raise ArgumentError, 'Bases must be between 2 and 36'
        end

        value_str.to_i(from_base).to_s(base)
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
      def pretty_path(file)
        return nil if file.nil?

        basepath    = ENV.fetch('ONETIME_HOME', __dir__)
        Pathname.new(file).relative_path_from(basepath)
      end

      # Standard deep_merge implementation with symbol/string key normalization
      #
      # TODO: The deep_merge method performs recursive merging without depth
      # limits or cycle detection. For large or deeply nested configurations,
      # this could lead to performance issues or stack overflow. Consider
      # adding safeguards. #1497
      #
      # @param original [Hash] Base hash with default values
      # @param other [Hash] Hash with values that override defaults
      # @return [Hash] A new hash containing the merged result with string keys
      def deep_merge(original, other)
        return normalize_keys(deep_clone(other)) if original.nil?
        return normalize_keys(deep_clone(original)) if other.nil?

        original_normalized = normalize_keys(deep_clone(original))
        other_normalized    = normalize_keys(deep_clone(other))

        merger = proc do |_key, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            v1.merge(v2, &merger)
          elsif v2.nil?
            v1
          else
            v2
          end
        end
        original_normalized.merge(other_normalized, &merger)
      end

      # Recursively freezes an object and all its nested components
      # to ensure complete immutability. This is a critical security
      # measure that prevents any modification of configuration values
      # after they've been loaded and validated, protecting against both
      # accidental mutations and potential security exploits.
      #
      # NOTE: This operates on the object itself, ensuring that all
      # nested components are also frozen. If you need to freeze an object
      # without modifying its original state, use `deep_clone` first
      # to avoid deep trouble.
      #
      # @param obj [Object] The object to freeze
      # @param clone [Boolean] Whether to clone the object before freezing
      # @return [Object] The frozen object
      # @security This ensures config values cannot be tampered with at runtime
      def deep_freeze(obj, clone = false)
        obj = deep_clone(obj) if clone # immediately forgets about the initial object
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
        when Array
          obj.each { |v| deep_freeze(v) }
        end
        obj.freeze
      end

      # Creates a complete deep copy of a configuration hash using YAML
      # serialization. This ensures all nested objects are properly duplicated,
      # preventing unintended sharing of references that could lead to data
      # corruption if modified.
      #
      # @param config_hash [Hash] The configuration hash to be cloned
      # @return [Hash] A deep copy of the original configuration hash
      # @raise [OT::Problem] When YAML serialization fails due to unserializable
      #   objects
      # @security Prevents configuration mutations from affecting multiple
      #   components
      #
      # @security_note YAML Deserialization Restrictions
      #   Ruby's YAML parser (Psych) restricts object loading to prevent
      #   deserialization attacks. Only basic types are allowed by default:
      #   String, Integer, Float, Array, Hash, Symbol, Date, Time. Custom
      #   objects will raise Psych::DisallowedClass errors. Malicious alias
      #   references will raise Psych::BadAlias errors. These restrictions are
      #   intentional and provide security benefits by preventing malicious
      #   object deserialization and YAML bomb attacks in configuration data.
      #
      # @limitations
      #   - Only works with basic Ruby data types (String, Integer, Hash,
      #     Array, Symbol)
      #   - Custom objects, Struct instances, and complex classes are blocked
      #     for security
      #   - Objects with singleton methods or custom serialization will fail
      #   - Performance can degrade with deeply nested or large object
      #     structures
      #
      #   For configuration use cases, these limitations are beneficial as they
      #   ensure data integrity and prevent security vulnerabilities. Use
      #   recursive approaches for custom object cloning outside of
      #   configuration contexts.
      #
      def deep_clone(config_hash)
        # Since we know we only expect a regular hash here without any methods,
        # procs etc, we use YAML instead to accomplish the same thing (JSON is
        # another option but it turns all the symbol keys into strings).
        YAML.load(YAML.dump(config_hash)) # TODO: Use oj for perf and string gains
      rescue TypeError, Psych::DisallowedClass, Psych::BadAlias => ex
        raise OT::Problem, "[deep_clone] #{ex.message}"
      end

      # Dump structure with types instead of values. Used for safe logging of
      # configuration data to help debugging.
      # @param obj [Object] Any Ruby object
      # @return [Hash,Array,String] Structure with class names instead of values
      def type_structure(obj)
        case obj
        when Hash
          obj.transform_values { |v| type_structure(v) }
            .transform_values { |v| v.is_a?(Hash) ? v : v.to_s }
        when Array
          if obj.empty?
            'Array<empty>'
          else
            sample = type_structure(obj.first)
            "Array<#{sample.class.name}>"
          end
        when NilClass
          'nil'
        else
          obj.class.name
        end
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

      private

      # Recursively normalizes hash keys to strings to ensure consistent key types
      # and prevent symbol/string key conflicts during merging operations.
      #
      # @param obj [Object] The object to normalize (Hash, Array, or other)
      # @return [Object] The object with normalized string keys
      def normalize_keys(obj)
        case obj
        when Hash
          normalized = {}
          obj.each do |key, value|
            normalized[key.to_s] = normalize_keys(value)
          end
          normalized
        when Array
          obj.map { |item| normalize_keys(item) }
        else
          obj
        end
      end

    end
  end
end
