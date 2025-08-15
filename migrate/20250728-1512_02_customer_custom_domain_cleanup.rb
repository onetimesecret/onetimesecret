# migrate/1512_02_customer_custom_domain_cleanup.rb
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
      @model_class  = V2::Customer
      @batch_size   = 1000
      @scan_pattern = "#{@model_class.prefix}:*:custom_domain"

      # Workaround: Familia::SortedSet ignores redis parameter, uses Familia.dbclient
      Familia.dbclient(6)
    end

    # This is an optional overload. We're cleaning up customer:*:custom_domain
    # records which are orphans, meaning they don't have customer object records
    # associated to them. They are defined as:
    #     `Customer.sorted_set :custom_domains, suffix: 'custom_domain'
    # Their only model association is  via V2::Customer which is why this is
    # a customer data migration, customized for these orphan records.
    #
    def load_from_key(key)
      # Generate the customer:*:object key that would exist if this
      # record wasn't an orphan. This key is used to verify if the customer
      # object does not exist before deleting the custom domain record (as
      # an extra precaution).
      @related_object_key = key.sub(/:[^:]*$/, ':object')

      # Load the custom domain SortedSet
      Familia::SortedSet.new(key, redis: dbclient)
    end

    # This is the ModelMethod#process_record method to override to perform
    # the actual migration on the loaded record.
    #
    # @param obj [Familia::SortedSet] The instance we created in loaded_from_key
    def process_record(obj, *)
      return unless should_remove_domain?(obj)

      # A custom method in this migration that checks @related_object_key
      verify_no_related_object

      # Another custom method in this migration to keep it easy to read
      delete_custom_domain(obj)

      track_stat(:records_updated)
    end

    private

    def delete_custom_domain(custom_domain_set)
      for_realsies_this_time? do
        result = custom_domain_set.delete!
        info("Deleted custom domain (result: #{result}): #{custom_domain_set.dbkey}")
      end

      dry_run_only? do
        info("Would delete: #{custom_domain_set.dbkey}")
      end
    end

    def should_remove_domain?(custom_domain_set)
      if test_domain_pattern?(custom_domain_set.dbkey)
        track_stat(:should_remove_test_domain)
        info("Found test domain: #{custom_domain_set.dbkey}")
        true
      else
        false
      end
    end

    def verify_no_related_object
      exists = dbclient.exists?(@related_object_key)
      info("Verifying no related customer object: #{@related_object_key} (exists: #{exists})")
    end

    def test_domain_pattern?(dbkey)
      dbkey.to_s.match?(/\Atryouts.*onetimesecret\.com\z/i)
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
