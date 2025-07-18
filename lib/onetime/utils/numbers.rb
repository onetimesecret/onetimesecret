# lib/onetime/utils/numbers.rb

module Onetime
  module Utils
    module Numbers
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
    end
  end
end
