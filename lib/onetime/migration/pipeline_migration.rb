# lib/onetime/migration/pipeline_migration.rb

require_relative 'model_migration'

module Onetime
  # Pipeline-based migration for batch Redis operations with improved performance
  #
  # Inherits all ModelMigration functionality but processes records in batches
  # using Redis pipelining instead of individual operations. This provides
  # significant performance improvements for large datasets with simple updates.
  #
  # ## When to Use PipelineMigration vs ModelMigration
  #
  # Use **PipelineMigration** when:
  # - Processing thousands+ records with simple field updates
  # - All records get similar field modifications
  # - Performance is more important than per-record error handling
  # - Updates can be expressed as Hash field assignments
  #
  # Use **ModelMigration** when:
  # - Complex logic needed per record
  # - Individual error handling is important
  # - Records need different processing logic
  # - Updates involve method calls beyond simple field assignment
  #
  # ## Subclassing Requirements
  #
  # Subclasses must implement:
  # - {#prepare} - Set @model_class and @batch_size (inherited)
  # - {#should_process?} - Return true/false for each record
  # - {#build_update_fields} - Return Hash of field updates
  #
  # Subclasses may override:
  # - {#execute_update} - Customize the pipeline update operation
  #
  # ## Usage Example
  #
  #   class CustomerObjidMigration < PipelineMigration
  #     def prepare
  #       @model_class = V2::Customer
  #       @batch_size = 100  # Smaller batches for pipelines
  #     end
  #
  #     def should_process?(obj)
  #       return track_stat(:skipped_empty_custid) && false if obj.custid.empty?
  #       true
  #     end
  #
  #     def build_update_fields(obj)
  #       {
  #         objid: obj.objid || SecureRandom.uuid_v7_from(obj.created),
  #         user_type: 'authenticated'
  #       }
  #     end
  #   end
  #
  # ## Performance Notes
  #
  # - Use smaller batch sizes (50-200) compared to ModelMigration
  # - Pipeline operations are atomic per batch, not per record
  # - Error handling is less granular than ModelMigration
  #
  # @abstract Subclass and implement {#should_process?} and {#build_update_fields}
  # @see ModelMigration For individual record processing
  class PipelineMigration < ModelMigration
    # Main batch processor - executes Redis operations in pipeline
    #
    # Processes an array of objects using Redis pipelining for improved
    # performance. Each object is checked via {#should_process?} and
    # updated via {#execute_update} if processing is needed.
    #
    # @param objects [Array<Array>] Array of tuples: [obj, original_redis_key]
    #   The original Redis key is preserved because records with missing/empty
    #   identifier fields cannot reconstitute their Redis key via obj.rediskey.
    #   Only the original key from SCAN guarantees we can operate on the record.
    # @return [void]
    def process_batch(objects)
      @redis_client.pipelined do |pipe|
        objects.each do |obj, original_key|
          next unless should_process?(obj)

          fields = build_update_fields(obj)

          # Previously we skipped here when the migration returned no fields
          # to update. We're not always here to update though. Sometimes we
          # delete or update expirations of do other stuff. If we skip ahead
          # here, we never get to the execute_update method which migrations
          # can override to do whatever they want.
          #
          # Now, we simply return inside the default execute_update. The end
          # result is the same but it gives us the opportunity to perform
          # additional operations on the record.

          execute_update(pipe, obj, fields, original_key)

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

    # Determine if object should be processed in this batch
    #
    # **Required for subclasses** - implement filtering logic to determine
    # which records should be included in the pipeline update. Use
    # {#track_stat} to count skipped records.
    #
    # @abstract Subclasses must implement this method
    # @param obj [Familia::Horreum] The model instance to evaluate
    # @return [Boolean] true to process, false to skip
    # @raise [NotImplementedError] if not implemented
    def should_process?(obj)
      raise NotImplementedError, "#{self.class} must implement #should_process?"
    end

    # Build fields hash for Redis HMSET operation
    #
    # **Required for subclasses** - return a hash of field names to values
    # that will be applied via Redis HMSET in the pipeline. Return an empty
    # hash or nil to skip the default HMSET operation.
    #
    # @abstract Subclasses must implement this method
    # @param obj [Familia::Horreum] The model instance to update
    # @return [Hash] field_name => value pairs for Redis HMSET
    # @raise [NotImplementedError] if not implemented
    def build_update_fields(obj)
      raise NotImplementedError, "#{self.class} must implement #build_update_fields"
    end

    # Execute pipeline update operation
    #
    # Override this method to customize pipeline operations beyond simple
    # HMSET field updates. The default implementation handles HMSET with
    # dry-run support.
    #
    # **Important**: Use the provided `pipe` parameter, not the regular
    # Redis connection, to ensure operations are pipelined.
    #
    # NOTE: The `track_stat(:records_updated)` method should not be called here
    # (or anywhere else in a pipeline migration actually) as it is called by the
    # pipeline migration framework itself.
    #
    # @param pipe [Redis::Pipeline] Redis pipeline instance
    # @param obj [Familia::Horreum] object being updated
    # @param fields [Hash] field updates from {#build_update_fields}
    # @param original_key [String] original Redis key from SCAN
    # @return [void]
    def execute_update(pipe, obj, fields, original_key = nil)
      klass_name = obj.class.name.split('::').last

      unless fields&.any?
        return debug("Would skip #{klass_name} b/c empty fields (#{original_key})")
      end

      # Use original_key for records that can't generate valid keys
      redis_key = original_key || obj.rediskey

      for_realsies_this_time? do
        # USE THE PIPELINE AND NOT THE regular redis connection.
        pipe.hmset(redis_key, fields.flatten)
      end

      dry_run_only? do
        debug("Would update #{klass_name}: #{fields}")
      end
    end
  end
end
