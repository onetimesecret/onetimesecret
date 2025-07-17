# lib/onetime/refinements/then_with_diff.rb

require 'hashdiff'
require 'familia'

module Onetime
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
  #   using Onetime::ThenWithDiff
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

    # NOTE: We recently added a valkey-backed settings model V2::MutableConfig
    # which may seen at odds with this approach or potentially overlap. They
    # use valkey for different purposes though: the settings model represents
    # a timeline of settings objects including the current state; here we are
    # using valkey like thread-safe shared memory and tracking the diffs at
    # each steps that it is modified.
    #
    # The URL for this key: redis://host/2/system:then_with_diff:history
    #
    # Other differences:
    # * MutableConfig:
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
        last_record_json = Onetime::ThenWithDiff.history.last
        last_record      = last_record_json ? JSON.parse(last_record_json) : {}
        previous_state   = last_record['content'] || {}

        diff = Hashdiff.diff(previous_state, result, Onetime::ThenWithDiff.options)
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

        Onetime::ThenWithDiff.history << record.to_json

        # Cleanup old records (older than 14 days)
        cutoff_time = OT.now.to_i - 14.days
        Onetime::ThenWithDiff.history.remrangebyscore(0, cutoff_time)

        deep_clone ? OT::Utils.deep_clone(result) : result
      end
    end
  end
end
