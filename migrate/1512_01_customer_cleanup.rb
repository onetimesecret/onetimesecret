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
  class Migration < PipelineMigration
    def prepare
      @model_class = V2::Customer
      @batch_size  = 1000
      # @scan_pattern = "#{@model_class.prefix}:*:custom_domain"
      # @interactive = true
    end

    def process_record(obj)
      # Skip records that don't meet any removal criteria
      should_remove = false

      # Check custid: empty, anon, or matches tryouts pattern
      if obj.custid.to_s.empty? ||
         obj.custid.to_s.downcase == 'anon' ||
         obj.custid.to_s.match?(/tryouts.*onetimesecret\.com/i)

        should_remove = true
        track_stat_and_log_reason(obj, :should_update, :custid)
      end

      # Check email: empty or matches tryouts pattern
      if obj.email.to_s.empty? ||
         obj.email.to_s.match?(/tryouts.*onetimesecret\.com/i)

        should_remove = true
        track_stat_and_log_reason(obj, :should_update, :email)
      end

      # Check created date: missing or should_update
      if obj.created.nil? ||
         obj.created.to_i < Time.new(2010, 1, 1).to_i

        should_remove = true
        track_stat_and_log_reason(obj, :should_update, :created)
      end

      return unless should_remove

      track_stat(:records_updated)

      for_realsies_this_time? do
        obj.flag_for_permanent_removal!("Migration #{__FILE__} at #{OT.now}")
      end
    end

  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
