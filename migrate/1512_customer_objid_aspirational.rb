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
      # Skip records with empty custid
      if obj.custid.to_s.empty?
        track_stat(:skipped_empty_custid)
        return
      end

      # Check if updates are needed
      needs_objid = obj.objid.to_s.empty?
      needs_extid = obj.extid.to_s.empty?
      needs_user_type = obj.user_type.to_s.empty?

      return unless needs_objid || needs_extid || needs_user_type

      # Log what we're updating
      updates = []
      updates << "objid" if needs_objid
      updates << "extid" if needs_extid
      updates << "user_type" if needs_user_type

      info("Updating record #{obj.custid}: #{updates.join(', ')}")

      # Track that this record will be updated
      would_update_record

      # Apply updates if in actual run mode
      for_realsies_this_time? do
        if needs_objid
          obj.objid = SecureRandom.uuid_v7_from(obj.created)
          track_stat(:objid_set)
        end

        if needs_extid
          obj.extid = OT::Utils.secure_shorten_id(Digest::SHA256.hexdigest(obj.objid))
          track_stat(:extid_set)
        end

        if needs_user_type
          obj.user_type = 'authenticated'
          track_stat(:user_type_set)
        end

        obj.save
      end
    end

    def migration_needed?
      # Always return true to allow re-running for error recovery
      # The migration is idempotent - it won't overwrite existing values
      true
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
