# lib/onetime/migration/model_migration.rb

require_relative 'model_migration'

module Onetime
  class PipelineMigration < ModelMigration
    # In ModelMigration class
    def process_batch(objects)
      # Default: process individually (backward compatibility)
      objects.each { |obj| process_record(obj) }
    end

    # In PipelineMigration
    def process_batch(objects)
      @redis_client.pipelined do |pipe|
        objects.each do |obj|
          next unless should_process?(obj)

          fields = build_update_fields(obj)
          next unless fields&.any?

          execute_update(pipe, obj, fields)
          track_stat(:records_updated)
        end
      end
    end

    private

    def scan_and_process_records
      cursor        = '0'
      batch_objects = []

      loop do
        cursor, keys    = @redis_client.scan(cursor, match: @scan_pattern, count: @batch_size)
        @total_scanned += keys.size

        if @total_scanned <= 500 || @total_scanned % 100 == 0
          progress(@total_scanned, @total_records, "Scanning #{model_class.name.split('::').last} records")
        end

        keys.each do |key|
          obj                      = model_class.find_by_key(key)
          @records_needing_update += 1

          batch_objects << obj

          # Process batch when full
          if batch_objects.size >= @batch_size
            process_batch_safely(batch_objects)
            batch_objects.clear
          end
        end

        break if cursor == '0'
      end

      # Process remaining objects in batch
      process_batch_safely(batch_objects) if batch_objects.any?
    end

    def execute_update(pipe, obj, fields)
      for_realsies_this_time? do
        pipe.hmset(obj.rediskey, fields.flatten)
      end

      dry_run_only? do
        debug("Would update #{obj.class.name.split('::').last} #{obj.custid}: #{fields}")
      end
    end

    # These methods must be implemented by subclasses
    def should_process?(obj)
      raise NotImplementedError, "#{self.class} must implement #should_process?"
    end

    def build_update_fields(obj)
      raise NotImplementedError, "#{self.class} must implement #build_update_fields"
    end

    def process_batch_safely(objects)
      process_batch(objects)
    rescue StandardError => ex
      @error_count += objects.size
      error("Error processing batch of #{objects.size}: #{ex.message}")
      objects.each { |obj| track_stat(:errors) }
    end
  end
end
