# lib/onetime/refinements/hash_refinements.rb

require 'hashdiff'

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
      return super(key) unless key.is_a?(String) || key.is_a?(Symbol)
      super(key.to_s) || super(key.to_sym)
    end

    def fetch(key, ...)
      # Check if the original key exists first
      return super(key, ...) if has_key?(key)

      # Only try conversion for String/Symbol keys
      return super(key, ...) unless key.is_a?(String) || key.is_a?(Symbol)

      # Try converted key
      converted_key = case key
                      when Symbol
                        key.to_s if has_key?(key.to_s)
                      when String
                        key.to_sym if has_key?(key.to_sym)
                      end

      if converted_key
        super(converted_key, ...)
      else
        super(key, ...)  # Let original method handle default/block
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

# ThenRehash
#
# This refinement extends Kernel#then with diff tracking capabilities, logging
# changes between transformation steps for debugging and monitoring purposes.
# Built on top of the hashdiff gem to provide detailed change detection.
#
# The refinement adds then_rehash to all objects, which works like Kernel#then
# but tracks state changes between calls and logs diffs when changes are detected.
# Particularly useful for configuration transformations where understanding the
# evolution of data structures is important.
#
# @example Using the refinement
#   using ThenRehash
#
#   config = { env: 'dev' }
#     .then_rehash('set database') { |c| c.merge(db: 'postgres') }
#     .then_rehash('add cache') { |c| c.merge(cache: 'redis') }
#   # Logs: [diff] set database: [["+", "db", "postgres"]]
#   # Logs: [diff] add cache: [["+", "cache", "redis"]]
#
# @note Uses deep cloning by default to prevent reference issues
# @note Diff options configured for strict type checking and symbol/string indifference
#
# @see https://github.com/liufengyun/hashdiff
#
module ThenRehash
  @options = {
    strict: true, # integer !== float
    indifferent: true, # string === symbol
    preserve_key_order: true, # uses order of first hash
    use_lcs: true, # slower, more accurate
    # An order difference alone between two arrays can create too many
    # diffs to be useful. Consider sorting them prior to diffing.
  }
  class << self
    attr_reader :options
  end

  refine Object do
    def then_rehash(step_name, deep_clone: true, &)
      result = yield(self)

      @previous_config_state ||= {}
      if @previous_config_state # in case it gets set to nil somewhere else
        diff = Hashdiff.diff(@previous_config_state, result, ThenRehash.options)
        OT.ld "[diff] #{step_name}: #{diff}" unless diff.empty?
      end

      @previous_config_state = deep_clone ? OT::Utils.deep_clone(result) : result
    end
  end
end
