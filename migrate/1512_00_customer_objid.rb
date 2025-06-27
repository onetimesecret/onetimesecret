# migrate/1512_customer_cleanup_pipeline.rb

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

      # ... other validations
      true
    end

    def build_update_fields(obj)
      {
        objid: obj.objid || SecureRandom.uuid_v7_from(obj.created),
        extid: obj.extid || OT::Utils.secure_shorten_id(Digest::SHA256.hexdigest(obj.objid)),
        user_type: 'authenticated',
      }
    end
  end
end
