#!/usr/bin/env ruby
# migrate/1512_customer_objid_aspirational.rb
#
# Customer Object ID and User Type Migration
#
# Purpose: Populates objid and user_type fields for all existing Customer records.
# - objid: Set to a UUIDv7 based on the customer's created timestamp
# - extid: Set to a shortened hash of the objid
# - user_type: Set to 'authenticated' (default user type)
#
# Usage:
#   ruby -I./lib migrate/1512_customer_objid_aspirational.rb --dry-run  # Preview changes
#   ruby -I./lib migrate/1512_customer_objid_aspirational.rb --run      # Execute migration
#
#   bin/ots migrate 1512_customer_objid_aspirational.rb


require 'onetime/model_migration'
require 'onetime/refinements/uuidv7_refinements'

module Onetime
  class Migration < ModelMigration
    using Onetime::UUIDv7Refinements

    def prepare
      @model_class = V2::Customer
      @batch_size = 1000
    end

    def process_record(obj)
      return track_stat(:skipped_empty_custid) if obj.custid.to_s.empty?

      would_update_record

      for_realsies_this_time? do
        obj.objid = obj.objid || SecureRandom.uuid_v7_from(obj.created)
        obj.extid = obj.extid || OT::Utils.secure_shorten_id(Digest::SHA256.hexdigest(obj.objid))
        obj.user_type = obj.user_type || 'authenticated'

        obj.save
        track_stat(:customers_updated)
      end
    end

  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
