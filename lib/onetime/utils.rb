
require 'httparty'

module Onetime
  module Utils
    extend self

    unless defined?(VALID_CHARS)
      VALID_CHARS = [('a'..'z').to_a, ('A'..'Z').to_a, ('0'..'9').to_a, %w[* $ ! ? ( )]].flatten
      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |v| %w[i l o 1 0].member?(v) }
      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    attr_accessor :fortunes

    def random_fortune
      raise OT::Problem, "No fortunes" if fortunes.nil?
      raise OT::Problem, "#{fortunes.class} is not an Array" unless fortunes.is_a?(Array)
      fortune = fortunes.sample.to_s.strip
      raise OT::Problem, "No fortune found" if fortune.empty?
      fortune
    rescue OT::Problem => e
      OT.le "#{e.message}"
      'Unexpected outcomes bring valuable lessons.'
    rescue StandardError => e
      OT.le "#{e.message} (#{fortunes.class})"
      OT.ld "#{e.backtrace.join("\n")}"
      'A house is full of games and puzzles.'
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

    # Generates a random string of specified length using predefined
    # character sets. Offers both safe and standard character sets for
    # different use cases, with the safe set excluding visually similar
    # characters to improve readability.
    #
    # @param len [Integer] Length of the generated string (default: 12)
    # @param safe [Boolean] Whether to use the safe character set
    #   (default: true)
    # @return [String] A randomly generated string of the specified length
    #
    # @example Generate a safe 12-character string
    #   Utils.strand         # => "kF8mN2qR9xPw"
    #   Utils.strand(8)      # => "kF8mN2qR"
    #
    # @example Generate using full character set
    #   Utils.strand(8, false) # => "il0O1o$!"
    #
    # @note Safe mode excludes potentially confusing characters: i, l, o, 1, 0
    # @note Character sets include: a-z, A-Z, 0-9, and symbols: * $ ! ? ( )
    # @security NOT cryptographically secure - uses Array#sample which relies
    #   on Ruby's standard PRNG. While suitable for password generation where
    #   users will replace with their own secrets, this should NOT be used for
    #   cryptographic keys, tokens, or other security-critical identifiers.
    #   Use SecureRandom methods for cryptographically secure generation.
    def strand(len = 12, safe = true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size - 1)] }.join
    end

    def indifferent_params(params)
      if params.is_a?(Hash)
        params = indifferent_hash.merge(params)
        params.each do |key, value|
          next unless value.is_a?(Hash) || value.is_a?(Array)

          params[key] = indifferent_params(value)
        end
      elsif params.is_a?(Array)
        params.collect! do |value|
          if value.is_a?(Hash) || value.is_a?(Array)
            indifferent_params(value)
          else
            value
          end
        end
      end
    end

    # Creates a Hash with indifferent access.
    def indifferent_hash
      Hash.new { |hash, key| hash[key.to_s] if key.is_a?(Symbol) }
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
      el = text.split('@')
      text.gsub regex, '\\3*****\\4@\\6*****\\7'
    end

    module Sanitation
      extend self

      # Converts a Ruby value into a JavaScript-friendly string or JSON.
      # This ensures special characters are properly escaped or converted to JSON.
      def normalize_value(value)
        case value.class.to_s
        when 'String', 'Symbol', 'Integer', 'Float'
          if is_https?(value)
            value
          else
            Rack::Utils.escape_html(value)
          end
        when 'Array', 'Hash'
          value
        when 'Boolean', 'FalseClass', 'TrueClass'
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

      def is_https?(str)
        uri = URI.parse(str)
        uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end

  module TimeUtils
    extend self

    def extract_time_from_uuid_v7(uuid)
      # Remove hyphens and take first 12 hex characters
      timestamp_hex = uuid.delete('-')[0, 12]
      # Convert to milliseconds since Unix epoch
      timestamp_ms  = timestamp_hex.to_i(16)
      # Convert to Time object
      Time.at(timestamp_ms / 1000.0)
    end

    def time_to_uuid_v7_timestamp(time)
      # Convert to milliseconds since Unix epoch
      timestamp_ms = (time.to_f * 1000).to_i
      # Convert to 12-character hex string
      hex          = timestamp_ms.to_s(16).rjust(12, '0')
      # Format with hyphen after 8 characters
      "#{hex[0, 8]}-#{hex[8, 4]}"
    end

    def epochdate(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      dformat time_parsed.utc
    end

    def epochtime(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      tformat time_parsed.utc
    end

    def epochformat(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      dtformat time_parsed.utc
    end

    def epochformat2(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      dtformat2 time_parsed.utc
    end

    def epochdom(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      time_parsed.utc.strftime('%b %d, %Y')
    end

    def epochtod(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      time_parsed.utc.strftime('%I:%M%p').gsub(/^0/, '').downcase
    end

    def epochcsvformat(time_in_s)
      time_parsed = Time.at time_in_s.to_i
      time_parsed.utc.strftime('%Y/%m/%d %H:%M:%S')
    end

    def dtformat(time_in_s)
      time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
      time_in_s.strftime('%Y-%m-%d@%H:%M:%S UTC')
    end

    def dtformat2(time_in_s)
      time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
      time_in_s.strftime('%Y-%m-%d@%H:%M UTC')
    end

    def dformat(time_in_s)
      time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
      time_in_s.strftime('%Y-%m-%d')
    end

    def tformat(time_in_s)
      time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
      time_in_s.strftime('%H:%M:%S')
    end

    def natural_duration(duration_in_s)
      if duration_in_s <= 1.minute
        format('%d seconds', duration_in_s)
      elsif duration_in_s <= 1.hour
        format('%d minutes', duration_in_s.in_minutes)
      elsif duration_in_s <= 1.day
        format('%d hours', duration_in_s.in_hours)
      else
        format('%d days', duration_in_s.in_days)
      end

      def epochtime(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        tformat time_parsed.utc
      end

      def epochformat(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        dtformat time_parsed.utc
      end

      def epochformat2(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        dtformat2 time_parsed.utc
      end

      def epochdom(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        time_parsed.utc.strftime('%b %d, %Y')
      end

      def epochtod(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        time_parsed.utc.strftime('%I:%M%p').gsub(/^0/, '').downcase
      end

      def epochcsvformat(time_in_s)
        time_parsed = Time.at time_in_s.to_i
        time_parsed.utc.strftime('%Y/%m/%d %H:%M:%S')
      end

      def dtformat(time_in_s)
        time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
        time_in_s.strftime('%Y-%m-%d@%H:%M:%S UTC')
      end

      def dtformat2(time_in_s)
        time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
        time_in_s.strftime('%Y-%m-%d@%H:%M UTC')
      end

      def dformat(time_in_s)
        time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
        time_in_s.strftime('%Y-%m-%d')
      end

      def tformat(time_in_s)
        time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
        time_in_s.strftime('%H:%M:%S')
      end

      def natural_duration(duration_in_s)
        if duration_in_s <= 1.minute
          '%d seconds' % duration_in_s
        elsif duration_in_s <= 1.hour
          '%d minutes' % duration_in_s.in_minutes
        elsif duration_in_s <= 1.day
          '%d hours' % duration_in_s.in_hours
        else
          '%d days' % duration_in_s.in_days
        end
      end

      # rubocop:disable Metrics/PerceivedComplexity, Metrics/AbcSize
      def natural_time(time_in_s)
        return if time_in_s.nil?

        val = Time.now.utc.to_i - time_in_s.to_i
        # puts val
        if val < 10
          result = 'a moment ago'
        elsif val < 40
          result = "about #{(val * 1.5).to_i.to_s.slice(0, 1)}0 seconds ago"
        elsif val < 60
          result = 'about a minute ago'
        elsif val < 60 * 1.3
          result = '1 minute ago'
        elsif val < 60 * 2
          result = '2 minutes ago'
        elsif val < 60 * 50
          result = "#{(val / 60).to_i} minutes ago"
        elsif val < 3600 * 1.4
          result = 'about 1 hour ago'
        elsif val < 3600 * (24 / 1.02)
          result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
        elsif val < 3600 * 24 * 1.6
          result = Time.at(time_in_s.to_i).strftime('yesterday').downcase
        elsif val < 3600 * 24 * 7
          result = Time.at(time_in_s.to_i).strftime('on %A').downcase
        else
          weeks = (val / 3600.0 / 24.0 / 7).to_i
          result = Time.at(time_in_s.to_i).strftime("#{weeks} #{'week'.plural(weeks)} ago").downcase
        end
        result
      end

  end
end
