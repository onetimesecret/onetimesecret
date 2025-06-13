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
      return super unless key.is_a?(String) || key.is_a?(Symbol)

      super(key.to_s) || super(key.to_sym)
    end

    def fetch(key, ...)
      # Check if the original key exists first
      return super if has_key?(key)

      # Only try conversion for String/Symbol keys
      return super unless key.is_a?(String) || key.is_a?(Symbol)

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

# ThenWithDiff
#
# This refinement extends Kernel#then with diff tracking capabilities, logging
# changes between transformation steps for debugging and monitoring purposes.
# Built on top of the hashdiff gem to provide detailed change detection.
#
# The refinement adds then_with_diff to all objects, which works like Kernel#then
# but tracks state changes between calls and logs diffs when changes are detected.
# Particularly useful for configuration transformations where understanding the
# evolution of data structures is important.
#
# @example Using the refinement
#   using ThenWithDiff
#
#   config = { env: 'dev' }
#     .then_with_diff('set database') { |c| c.merge(db: 'postgres') }
#     .then_with_diff('add cache') { |c| c.merge(cache: 'redis') }
#   # Logs: [diff] set database: [["+", "db", "postgres"]]
#   # Logs: [diff] add cache: [["+", "cache", "redis"]]
#
# @note Uses deep cloning by default to prevent reference issues
# @note Diff options configured for strict type checking and symbol/string indifference
#
# @see https://github.com/liufengyun/hashdiff
#
module ThenWithDiff
  @options = {
    strict: true, # integer !== float
    indifferent: true, # string === symbol
    preserve_key_order: true, # uses order of first hash
    use_lcs: true, # slower, more accurate
    # An order difference alone between two arrays can create too many
    # diffs to be useful. Consider sorting them prior to diffing.
  }.freeze

  # NOTE: We recently added a valkey-backed settings model V2::SystemSettings
  # which may seen at odds with this approach or potentially overlap. They
  # use valkey for different purposes though: the settings model represents
  # a timeline of settings objects including the current state; here we are
  # using valkey like thread-safe shared memory and tracking the diffs at
  # each steps that it is modified.
  #
  # The URL for this key: redis://host/2/system:then_with_diff:history
  #
  # Other differences:
  # * SystemSettings:
  #   * modified manually in the colonel UI.
  #   * keeps track of every version of the settings object
  # * Core configuration:
  #   * modified via ./etc/config.yaml before the application boots up.
  #   * only keeps a rolling 14 days of diffs
  #   * not meant to be modified while the application is running.
  #
  # KNOWN LIMITATION: Since the key name is hardcoded any hash-like class that
  # uses this refinement will have have its diffs stored in amongst the boot
  # configuration for OT::Configurator. It's the only usecase right now but
  # we'll want want to setup this history sorted set at boot-time to so
  # we can access it in other parts of the codebase.
  @history = Familia::SortedSet.new 'then_with_diff',
    db: 2,
    ttl: 14.days,
    prefix: 'system',
    suffix: 'history'

  class << self
    attr_reader :options, :history
  end

  refine Object do
    def then_with_diff(step_name, deep_clone: true, &)
      OT.ld "[then_with_diff] Inside #{step_name} (clone: #{deep_clone})"
      result = yield(self)

      # Get previous state from last record
      last_record_json = ThenWithDiff.history.last
      last_record      = last_record_json ? JSON.parse(last_record_json) : {}
      previous_state   = last_record['content'] || {}

      diff = Hashdiff.diff(previous_state, result, ThenWithDiff.options)
      OT.ld "[then_with_diff] #{step_name}: #{diff.size} changes" unless diff.empty?

      # Store as simple hash, serialized to JSON
      record = {
        mode: OT.mode,
        instance: OT.instance,
        step_name: step_name,
        diff: diff,
        content: OT::Utils.deep_clone(result).freeze,
        created: OT.now.to_i,
      }

      ThenWithDiff.history << record.to_json

      # Cleanup old records (older than 14 days)
      cutoff_time = OT.now.to_i - 14.days
      ThenWithDiff.history.remrangebyscore(0, cutoff_time)

      deep_clone ? OT::Utils.deep_clone(result) : result
    end
  end
end
