# migrate/1512_customer_cleanup_pipeline.rb
#
# Customer Object ID and User Type Migration - Pipeline
#
# Purpose: Populates objid and user_type fields for all existing Customer records.
# - objid: Set to a UUIDv7 based on the customer's created timestamp
# - extid: Set to a shortened hash of the objid
# - user_type: Set to 'authenticated' (default user type)
#
# Usage:
#   bin/ots migrate 1512_customer_objid_aspirational.rb # Preview changes
#   bin/ots migrate --run 1512_customer_objid_aspirational.rb
#
#   ruby -I./lib migrate/1512_customer_objid_aspirational.rb --dry-run  # Preview changes
#   ruby -I./lib migrate/1512_customer_objid_aspirational.rb --run
#

require 'onetime/migration'
require 'onetime/refinements/uuidv7_refinements'

module Onetime
  class Migration < PipelineMigration
    using Onetime::UUIDv7Refinements

    def prepare
      @model_class = V2::Customer
      @batch_size  = 100  # Smaller batches for pipeline
    end

    def use_batch_processing?
      true
    end

    def process_batch(objects)
      @redis_client.pipelined do |pipe|
        objects.each do |obj|
          next unless should_update?(obj)

          fields = build_update_fields(obj)

          for_realsies_this_time? do
            pipe.hmset(obj.rediskey, fields.flatten)
          end

          dry_run_only? do
            p fields
          end

          track_stat(:records_updated)
        end
      end
    end

    private

    def should_update?(obj)
      return track_stat(:skipped_empty_custid) if obj.custid.to_s.empty?
      return track_stat(:skipped_anonymous) if obj.anonymous?
      return track_stat(:skipped_empty_email) if obj.email.to_s.empty?
      return track_stat(:skipped_user_deleted_self) if obj.user_deleted_self?
      return track_stat(:skipped_tryouts_test_record) if obj.email.to_s.start_with?('tryouts+')
      return track_stat(:skipped_empty_created) if obj.created.to_s.empty?

      true
    end

    def build_update_fields(obj)
      {
        objid: obj.objid || SecureRandom.uuid_v7_from(obj.created),
        extid: obj.extid || OT::Utils.secure_shorten_id(Digest::SHA256.hexdigest(obj.objid)),
        # Force them all to be user_type=authenticated. If not set, it can be saved
        # as anonymous which then triggers the guard above as well as an error when
        # trying to call obj.save.
        user_type: 'authenticated',
      }
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end
