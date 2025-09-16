
require 'httparty'

module Onetime
  module Utils
    extend self
    unless defined?(VALID_CHARS)
      # Symbols used in character sets for random string generation.
      # Includes common special characters that are generally safe for use
      # in generated identifiers and passwords.
      # Character set constants for flexible password generation
      UPPERCASE = ('A'..'Z').to_a.freeze
      LOWERCASE = ('a'..'z').to_a.freeze
      NUMBERS = ('0'..'9').to_a.freeze

      # Extended symbol set for password generation
      SYMBOLS = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '-', '+', '=', '[', ']', '{', '}', '|', ' :', ';', '"', "'", '<', '>', ',', '.', '?', '/', '~', '`'].freeze

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

    # Generates a random string of specified length using configurable character sets.
    # Supports both simple usage and complex password generation with guaranteed complexity.
    #
    # @param len [Integer] Length of the generated string (default: 12)
    # @param options [Boolean, Hash] If boolean, treats as 'unambiguous' for backward compatibility.
    #   If hash, supports the following options:
    #   - :uppercase [Boolean] Include uppercase letters (default: true)
    #   - :lowercase [Boolean] Include lowercase letters (default: true)
    #   - :numbers [Boolean] Include numbers (default: true)
    #   - :symbols [Boolean] Include symbols (default: false)
    #   - :exclude_ambiguous [Boolean] Exclude visually similar characters (default: true)
    #   - :unambiguous [Boolean] Legacy option, same as exclude_ambiguous
    # @return [String] A randomly generated string of the specified length
    #
    # @example Generate a simple unambiguous 12-character string
    #   Utils.strand         # => "kF8mN2qR9xPw"
    #   Utils.strand(8)      # => "kF8mN2qR"
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
               { exclude_ambiguous: options }
             in Hash
               options
             else
               {}
             end

      defaults = {
        uppercase:   true,
        lowercase:   true,
        numbers:     true,
        symbols:     false,
        exclude_ambiguous: true,
      }

      opts = defaults.merge(opts)
      opts[:exclude_ambiguous] ||= opts.delete(:unambiguous) if opts.key?(:unambiguous)

      # Build character set based on options
      chars = []
      chars.concat(UPPERCASE) if opts[:uppercase]
      chars.concat(LOWERCASE) if opts[:lowercase]
      chars.concat(NUMBERS) if opts[:numbers]
      chars.concat(SYMBOLS) if opts[:symbols]

      # Remove ambiguous characters if requested
      if opts[:exclude_ambiguous]
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
      password_chars << UPPERCASE.sample if opts[:uppercase]
      password_chars << LOWERCASE.sample if opts[:lowercase]
      password_chars << NUMBERS.sample if opts[:numbers]
      password_chars << SYMBOLS.sample if opts[:symbols]

      # Remove ambiguous characters from guaranteed chars if needed
      if opts[:exclude_ambiguous]
        password_chars.delete_if { |char| AMBIGUOUS_CHARS.include?(char) }
      end

      # Fill remaining length with random characters from the full set
      remaining_length = len - password_chars.length
      if remaining_length > 0
        remaining_chars = Array.new(remaining_length) { chars[SecureRandom.random_number(chars.length)] }
        password_chars.concat(remaining_chars)
      end

      # Shuffle and join to create final password
      password_chars.shuffle.join
    end

    private

    # Check if multiple character sets are requested (requiring complexity guarantee)
    def multiple_char_sets_requested?(opts)
      enabled_sets = [opts[:uppercase], opts[:lowercase], opts[:numbers], opts[:symbols]].count(true)
      enabled_sets > 1
    end

    public



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

    def deep_merge(default, overlay)
      merger = proc { |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &merger) : v2 }
      default.merge(overlay, &merger)
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
