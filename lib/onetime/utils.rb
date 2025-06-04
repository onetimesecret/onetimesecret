
require 'httparty'
require 'yaml'

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

    def strand(len = 12, safe = true)
      chars = safe ? VALID_CHARS_SAFE : VALID_CHARS
      (1..len).collect { chars[rand(chars.size - 1)] }.join
    end

    def deep_indifferent_hash(params)
      if params.is_a?(Hash)
        params = indifferent_hash.merge(params)
        params.each do |key, value|
          next unless value.is_a?(Hash) || value.is_a?(Array)

          params[key] = deep_indifferent_hash(value)
        end
      elsif params.is_a?(Array)
        params.collect! do |value|
          if value.is_a?(Hash) || value.is_a?(Array)
            deep_indifferent_hash(value)
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

    # Standard deep_merge implementation with symbol/string key normalization
    #
    # @param original [Hash] Base hash with default values
    # @param other [Hash] Hash with values that override defaults
    # @return [Hash] A new hash containing the merged result with string keys
    def deep_merge(original, other)
      return normalize_keys(deep_clone(other)) if original.nil?
      return normalize_keys(deep_clone(original)) if other.nil?

      original_normalized = normalize_keys(deep_clone(original))
      other_normalized = normalize_keys(deep_clone(other))

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

    # Recursively freezes an object and all its nested components
    # to ensure complete immutability. This is a critical security
    # measure that prevents any modification of configuration values
    # after they've been loaded and validated, protecting against both
    # accidental mutations and potential security exploits.
    #
    # @param obj [Object] The object to freeze
    # @return [Object] The frozen object
    # @security This ensures configuration values cannot be tampered with at runtime
    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
      when Array
        obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end

    # Creates a complete deep copy of a configuration hash using Marshal
    # dump and load. This ensures all nested objects are properly duplicated,
    # preventing unintended sharing of references that could lead to data
    # corruption if modified.
    #
    # @param config_hash [Hash] The configuration hash to be cloned
    # @return [Hash] A deep copy of the original configuration hash
    # @raise [OT::Problem] When Marshal serialization fails due to unserializable objects
    # @security Prevents configuration mutations from affecting multiple components
    #
    # @limitations
    #   This method has significant limitations due to its reliance on Marshal:
    #   - Cannot clone objects with singleton methods, procs, lambdas, or IO objects
    #   - Will fail when encountering objects that implement custom _dump methods without _load
    #   - Loses any non-serializable attributes from complex objects
    #   - May not preserve class/module references across different Ruby processes
    #   - Thread-safety issues may arise with concurrent serialization operations
    #   - Performance can degrade with deeply nested or large object structures
    #
    #   Consider using a recursive approach for specialized object cloning when
    #   dealing with configuration containing custom objects, procs, or other
    #   non-serializable elements. For critical security contexts, validate that
    #   all configuration elements are serializable before using this method.
    #
    def deep_clone(config_hash)
      # Previously used Marshal here. But in Ruby 3.1 it died cryptically with
      # a singleton error. It seems like it's related to gibbler but since we
      # know we only expect a regular hash here without any methods, procs
      # etc, we use YAML instead to accomplish the same thing (JSON is
      # another option but it turns all the symbol keys into strings).
      YAML.load(YAML.dump(config_hash)) # TODO: Use oj for performance and string gains
    rescue TypeError => ex
      raise OT::Problem, "[deep_clone] #{ex.message}"
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
        when 'String', 'Gibbler::Digest', 'Symbol', 'Integer', 'Float'
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
