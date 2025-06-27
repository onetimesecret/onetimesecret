# migrate/1512_01_customer_cleanup.rb
#
# Customer Cleanup - Remove anonymous, known test users - Pipeline
#
# Purpose: Removes Customer records based on the following criteria:
# - custid: is empty, anon, or matches "tryouts*onetimesecret.com" -> remove
# - email: is empty or matches "tryouts*onetimesecret.com" -> remove
# - created: missing or before 2010 -> remove
#
# Usage:
#   bin/ots migrate 1512_customer_cleanup.rb # Preview changes
#   bin/ots migrate --run 1512_customer_cleanup.rb
#

require 'onetime/migration'

module Onetime
  class Migration < PipelineMigration
    def prepare
      @model_class = V2::Customer
      @batch_size  = 1000
    end

    # Override to handle deletions instead of field updates
    def process_batch(objects)
      objects.each do |obj, key|
        next unless should_process?(obj)

        info "Deleting record #{key}"
        for_realsies_this_time? do
          redis_client.del key
        end

        track_stat(:records_updated)
      end
    end

    private

    def should_process?(obj)
      should_remove = false

      # Check custid: empty, anon, or tryouts pattern
      if !should_remove && invalid_custid?(obj.custid)
        should_remove = true
        track_removal_reason(obj, :custid)
      end

      # Check email: empty or tryouts pattern
      if !should_remove && invalid_email?(obj.email)
        should_remove = true
        track_removal_reason(obj, :email)
      end

      # Check created date: missing or too old
      if !should_remove && invalid_created_date?(obj.created)
        should_remove = true
        track_removal_reason(obj, :created)
      end

      should_remove
    end

    def build_update_fields(*)
      # Not used for deletion migration. Instead this migration
      # defines its own process_batch.
      {}
    end

    def invalid_custid?(custid)
      custid.to_s.empty? ||
        custid.to_s.downcase == 'anon' ||
        custid.to_s.match?(/tryouts.*onetimesecret\.com/i)
    end

    def invalid_email?(email)
      email.to_s.empty? ||
        email.to_s.match?(/tryouts.*onetimesecret\.com/i)
    end

    def invalid_created_date?(created)
      created.nil? || created.to_i < Time.new(2010, 1, 1).to_i
    end

    def track_removal_reason(obj, field)
      track_stat("removal_#{field}")
      debug("Removing objid=#{obj.objid} #{field}=#{obj.send(field)}")
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
