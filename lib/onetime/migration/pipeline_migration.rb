# lib/onetime/migration/pipeline_migration.rb

require_relative 'model_migration'

module Onetime
  # Pipeline-based migration for batch Redis operations
  #
  # Inherits all ModelMigration functionality but processes records in batches
  # using Redis pipelining for improved performance on large datasets.
  #
  # Usage:
  #   class MyPipelineMigration < PipelineMigration
  #     def prepare
  #       @model_class = V2::Customer
  #       @batch_size = 100  # Smaller batches recommended for pipelines
  #     end
  #
  #     def should_process?(obj)
  #       # Return false to skip, true to process
  #       # Use track_stat() for skip counters
  #     end
  #
  #     def build_update_fields(obj)
  #       # Return hash of fields to update
  #       { field_name: new_value }
  #     end
  #   end
  class PipelineMigration < ModelMigration

    # Main batch processor - executes Redis operations in pipeline
    def process_batch(objects)
      @redis_client.pipelined do |pipe|
        objects.each do |obj, _| # obj and key
          next unless should_process?(obj)

          fields = build_update_fields(obj)
          next unless fields&.any?

          execute_update(pipe, obj, fields)

          track_stat(:records_updated)
        end
      end
    end

    # Override scanning to collect batches instead of individual processing
    private

    def scan_and_process_records
      cursor        = '0'
      batch_objects = []

      loop do
        cursor, keys    = @redis_client.scan(cursor, match: @scan_pattern, count: @batch_size)
        @total_scanned += keys.size

        # Progress reporting
        if @total_scanned <= 500 || @total_scanned % 100 == 0
          progress(@total_scanned, @total_records, "Scanning #{model_class.name.split('::').last} records")
        end

        # Collect objects for batch processing
        keys.each do |key|
          obj                      = load_from_key(key)
          @records_needing_update += 1
          batch_objects << [obj, key]

          # Process when batch is full
          if batch_objects.size >= @batch_size
            process_batch_safely(batch_objects)
            batch_objects.clear
          end
        end

        break if cursor == '0'
      end

      # Process remaining objects
      process_batch_safely(batch_objects) if batch_objects.any?
    end

    def execute_update(pipe, obj, fields)
      for_realsies_this_time? do
        pipe.hmset(obj.rediskey, fields.flatten)
      end
      dry_run_only? do
        debug("Would update #{obj.class.name.split('::').last} #{obj.send(obj.class.identifier)}: #{fields}")
      end
    end

    def process_batch_safely(objects)
      return if objects.empty?

      info("Processing batch of #{objects.size} objects...")
      process_batch(objects)
    rescue StandardError => ex
      @error_count += objects.size
      error("Error processing batch of #{objects.size}: #{ex.message}")
      debug("Stack trace: #{ex.backtrace.first(10).join('; ')}")
      objects.each { track_stat(:errors) }
    end

    protected

    # Determine if object should be processed
    # @param obj [Familia::Horreum] The model instance
    # @return [Boolean] true to process, false to skip
    def should_process?(obj)
      raise NotImplementedError, "#{self.class} must implement #should_process?"
    end

    # Build fields hash for Redis update
    # @param obj [Familia::Horreum] The model instance
    # @return [Hash] field_name => value pairs for Redis HMSET
    def build_update_fields(obj)
      raise NotImplementedError, "#{self.class} must implement #build_update_fields"
    end
  end
end

# Example usage:
#
# class CustomerObjidMigration < PipelineMigration
#   def prepare
#     @model_class = V2::Customer
#     @batch_size = 100
#   end
#
#   private
#
#   def should_process?(obj)
#     return track_stat(:skipped_empty_custid) && false if obj.custid.to_s.empty?
#     return track_stat(:skipped_anonymous) && false if obj.anonymous?
#     return track_stat(:skipped_empty_email) && false if obj.email.to_s.empty?
#     true
#   end
#
#   def build_update_fields(obj)
#     {
#       objid: obj.objid || SecureRandom.uuid_v7_from(obj.created),
#       user_type: 'authenticated'
#     }
#   end
# end
