# lib/onetime/refinements/indifferent_hash_access.rb

# IndifferentHashAccess
#
# This refinement provides symbol/string indifferent access for Hash objects,
# allowing flexible key lookup using either strings or symbols interchangeably.
# Based on Familia's FlexibleHashAccess with additional methods for comprehensive
# indifferent access support.
#
# The refinement extends Hash with flexible access for [], fetch, and dig methods,
# automatically converting between symbol and string keys during lookup operations.
# This is particularly useful for configuration hashes where keys may be normalized
# to strings but code expects symbol access.
#
# @example Using the refinement
#   using IndifferentHashAccess
#
#   config = { 'site' => { 'secret' => 'abc123' } }
#   config[:site][:secret]        # => 'abc123'
#   config.fetch(:site)           # => { 'secret' => 'abc123' }
#   config.dig(:site, :secret)    # => 'abc123'
#
# @note Only affects reading operations - writing maintains original key types
# @note In future versions, this logic may be moved upstream to Familia's FlexibleHashAccess
#
module IndifferentHashAccess
  refine Hash do
    def [](key)
      return super unless key.is_a?(String) || key.is_a?(Symbol)

      super(key.to_s) || super(key.to_sym)
    end

    def fetch(key, ...)
      # Check if the original key exists first
      return super if key?(key)

      # Only try conversion for String/Symbol keys
      return super unless key.is_a?(String) || key.is_a?(Symbol)

      # Try converted key
      converted_key = case key
                      when Symbol
                        key.to_s if key?(key.to_s)
                      when String
                        key.to_sym if key?(key.to_sym)
                      end

      if converted_key
        super(converted_key, ...)
      else
        super  # Let original method handle default/block
      end
    end

    def dig(key, *rest)
      value = self[key]  # Uses the flexible [] method
      if rest.empty?
        value
      elsif value.respond_to?(:dig)
        value.dig(*rest)
      end
    end
  end
end
