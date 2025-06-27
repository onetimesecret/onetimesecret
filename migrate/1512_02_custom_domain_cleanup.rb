# migrate/1512_customer_cleanup.rb
#
# Customer Cleanup - Remove anonymous, known test users
#
# Purpose: Removes Custom records based on the following criteria
# - custid: is empty, anon, or matches "Tryouts*onetimesecret.com" -> remove
# - email: is empty or matches "Tryouts*onetimesecret.com" -> remove
# - role: missing -> 'customer'
#
# Usage:
#   bin/ots migrate 1512_customer_cleanup.rb # Preview changes
#   bin/ots migrate --run 1512_customer_cleanup.rb
#
#   ruby -I./lib migrate/1512_customer_cleanup.rb --dry-run  # Preview changes
#   ruby -I./lib migrate/1512_customer_cleanup.rb --run
#

require 'onetime/migration'

module Onetime
  class Migration < ModelMigration
    def prepare
      @model_class  = V2::Customer
      @batch_size   = 1000
      @scan_pattern = "#{@model_class.prefix}:*:custom_domain"
      # @interactive = true
      # There's a bug in Familia, where the Familia::SortedSet uses the
      # Familia.redis instance instead of the one passed in on instantiation.
      Familia.redis(6)
    end

    def load_from_key(key)
      # Replaces everything after the last colon with :object
      @related_key = key.sub(/:[^:]*$/, ':object')
      Familia::SortedSet.new(key, redis: redis_client) # see note in prepare method
    end

    def process_record(obj)
      # Only process records where should_remove is true
      should_remove = false

      # Check custid: empty, anon, or matches tryouts pattern
      if obj.rediskey.to_s.match?(/tryouts.*onetimesecret\.com/i)
        should_remove = true
        track_stat(:should_remove_test_custid)
      end

      return unless should_remove

      track_stat(:records_updated)

      ret = redis_client.exists?(@related_key)
      info("Double checking that there is no related object: #{@related_key} (#{ret})")

      for_realsies_this_time? do
        ret = obj.delete!
        info("Deleting #{obj.class} (ret: #{ret}): #{obj.rediskey} from #{obj.redis.connection}")
      end

      dry_run_only? do
        info("Dry run: #{obj.rediskey} from #{obj.redis.connection}")
      end
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
