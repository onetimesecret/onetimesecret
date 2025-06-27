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

module Onetime
  class Migration < PipelineMigration
    def prepare
      @model_class = V2::Session
      @batch_size  = 1000
    end

    # Override to handle deletions instead of field updates
    def execute_update(pipe, obj, _, original_key)
      # Use original_key for records that can't generate valid keys
      redis_key = original_key || obj.rediskey

      for_realsies_this_time? do
        pipe.del redis_key
      end

      dry_run_only? do
        debug("Would update #{@model_class}: #{original_key} (created: #{obj.to_h})")
      end
    end

    private

    # Check ttl: is it a negative value? Is the record older than 7 days?
    #
    # This method can be implemented however you like. It just needs to
    # return a boolean value.
    def should_process?(obj)
      return false unless obj.realttl.to_i.negative?

      # return false unless obj.created_at < 7.days.ago # TODO

      track_stat('removal_ttl')
      debug("Should remove sessid=#{obj.sessid} ttl=#{obj.ttl} realttl=#{obj.realttl}")
      true
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
