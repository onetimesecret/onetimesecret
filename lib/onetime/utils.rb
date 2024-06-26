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
      @fortunes.random.to_s.strip
    rescue StandardError
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
  end

end
