
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

    def self.random_fortune
      raise "No fortunes" if fortunes.nil? || fortunes.empty?
      fortune = fortunes.sample.to_s.strip
      raise "No fortune found" if fortune.empty?
      fortune
    rescue StandardError => e
      OT.le "#{e.message}"
      OT.ld "#{e.backtrace.join("\n")}"
      'A house is full of games and puzzles.'
    end

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
      def jsvar(value)
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

      # Collects data and returns a script tag for embedding.
      def serialize_to_script(data, id: nil, nonce: nil)
        sanitized_json = to_sanitized_json(data)
        attributes = ['type="application/json"']
        attributes << %{id="#{Rack::Utils.escape_html(id)}"} if id
        attributes << %{nonce="#{nonce}"} if nonce

        "<script #{attributes.join(' ')}>#{sanitized_json}</script>"
      end

      # Converts data to JSON and sanitizes it to reduce risk of injection attacks.
      # Escapes certain special characters and script tags.
      def to_sanitized_json(data)
        data.to_json
          .gsub(%r{</script}i, '<\/script')
          .gsub(/[\u0000-\u001F]/, '')
          .gsub(/[^\x20-\x7E]/) { |c| "\\u#{c.ord.to_s(16).rjust(4, '0')}" }
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
