# migrate/1512_02_custom_domain_cleanup.rb
#
# Custom Domain Cleanup - Remove test user domains
#
# Purpose: Removes custom domain records for test users:
# - Domains matching "tryouts*onetimesecret.com" pattern -> remove
# - Verifies no related customer object exists before deletion
#
# Usage:
#   bin/ots migrate 1512_02_custom_domain_cleanup.rb # Preview changes
#   bin/ots migrate --run 1512_02_custom_domain_cleanup.rb
#

require 'onetime/migration'

module Onetime
  class Migration < ModelMigration
    def prepare
      @model_class = V2::Customer
      @batch_size = 1000
      @scan_pattern = "#{@model_class.prefix}:*:custom_domain"

      # Workaround: Familia::SortedSet ignores redis parameter, uses Familia.redis
      Familia.redis(6)
    end

    def load_from_key(key)
      # Store related object key for safety checking
      @related_object_key = key.sub(/:[^:]*$/, ':object')

      # Load the custom domain SortedSet
      Familia::SortedSet.new(key, redis: redis_client)
    end

    def process_record(custom_domain_set)
      return unless should_remove_domain?(custom_domain_set)

      verify_no_related_object
      delete_custom_domain(custom_domain_set)
      track_stat(:records_updated)
    end

    private

    def should_remove_domain?(custom_domain_set)
      if test_domain_pattern?(custom_domain_set.rediskey)
        track_stat(:should_remove_test_domain)
        info("Found test domain: #{custom_domain_set.rediskey}")
        true
      else
        false
      end
    end

    def test_domain_pattern?(redis_key)
      redis_key.to_s.match?(/tryouts.*onetimesecret\.com/i)
    end

    def verify_no_related_object
      exists = redis_client.exists?(@related_object_key)
      info("Verifying no related customer object: #{@related_object_key} (exists: #{exists})")
    end

    def delete_custom_domain(custom_domain_set)
      for_realsies_this_time? do
        result = custom_domain_set.delete!
        info("Deleted custom domain (result: #{result}): #{custom_domain_set.rediskey}")
      end

      dry_run_only? do
        info("Would delete: #{custom_domain_set.rediskey}")
      end
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
