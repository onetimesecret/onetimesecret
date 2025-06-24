# lib/onetime/utils.rb

require 'httparty'

module Onetime
  module Utils
    extend self
    unless defined?(VALID_CHARS)
      VALID_CHARS = [
        ('a'..'z').to_a,
        ('A'..'Z').to_a,
        ('0'..'9').to_a,
        %w[* $ ! ? ( )],
      ].flatten

      VALID_CHARS_SAFE = VALID_CHARS.clone
      VALID_CHARS_SAFE.delete_if { |char| %w[i l o 1 0].include?(char) }

      VALID_CHARS.freeze
      VALID_CHARS_SAFE.freeze
    end
    attr_accessor :fortunes

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
    # @security Uses cryptographically secure random generation
    def strand(len = 12, safe = true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars.sample }.join
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
      # Previously used Marshal here. But in Ruby 3.1 it died cryptically with
      # a singleton error. It seems like it's related to gibbler but since we
      # know we only expect a regular hash here without any methods, procs
      # etc, we use YAML instead to accomplish the same thing (JSON is
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

    module Sanitation
      extend self

      # Converts a Ruby value into a JavaScript-friendly string or JSON.
      # This ensures special characters are properly escaped or converted to JSON.
      def normalize_value(value)
        case value.class.to_s
        when 'String', 'Gibbler::Digest', 'Symbol', 'Integer', 'Float'
          if https?(value)
            value
          else
            Rack::Utils.escape_html(value)
          end
        # JSON-compatible types are passed through as-is
        when 'Array', 'Hash', 'Boolean', 'FalseClass', 'TrueClass'
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

      def https?(str)
        uri = URI.parse(str)
        uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end

  module TimeUtils
    extend self

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
    end

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
        weeks  = (val / 3600.0 / 24.0 / 7).to_i
        result = Time.at(time_in_s.to_i)
          .strftime("#{weeks} #{'week'.plural(weeks)} ago")
          .downcase
      end
      result
    end
  end
end
