# migrate/1512_03_session_cleanup.rb
#
# Session Cleanup - Remove test user sessions
#
# Purpose: Removes session records with no expiration
# - Sessions without a TTL were created by a bug. They never expire so
#   they are never cleaned up.
# - Verifies they are older than 7 days as a precaution to ensure
#   they are not active sessions.
#
# Usage:
#   bin/ots migrate 1512_03_session_cleanup.rb # Preview changes
#   bin/ots migrate --run 1512_03_session_cleanup.rb
#

require 'onetime/migration'
require 'familia/refinements/time_utils'

module Onetime
  class Migration < PipelineMigration
    using Familia::Refinements::TimeUtils

    def prepare
      @model_class = V2::Session
      @batch_size  = 1000
    end

    # Override to handle deletions instead of field updates
    #
    # NOTE: Don't call `track_stat(:records_updated)` here (or anywhere in
    # a pipline migration). It's called automatically in process_batch.
    def execute_update(pipe, obj, _, original_key)
      # Use original_key for records that can't generate valid keys
      dbkey = original_key || obj.dbkey

      for_realsies_this_time? do
        pipe.del dbkey
      end

      dry_run_only? do
        debug("Would update #{@model_class}: #{original_key} (created: #{obj.to_h})")
      end

    end

    private

    # Check ttl: is it a negative value?
    # Check created: Is the record older than 7 days?
    #
    # This method can be implemented however you like. It just needs to
    # return a boolean value.
    def should_process?(obj)
      should_process = false
      criteria = [
        obj.current_expiration.to_i.negative?,
        obj.created.to_i.older_than?(7.days),
      ]

      if criteria.all?
        track_stat('removal_ttl_and_older_than_7d')
        debug("Should process sessid=#{obj.sessid} ttl=#{obj.default_expiration} realttl=#{obj.current_expiration}")
        should_process = true
      end

      should_process
    end

    def build_update_fields(*)
      # Not used for deletion migration. Instead this migration
      # defines its own execute_update.
      {}
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
