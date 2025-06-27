# lib/onetime/migration/model_migration.rb

require_relative 'model_migration'

module Onetime
  class PipelineMigration < ModelMigration
    # In ModelMigration class
    def process_batch(objects)
      # Default: process individually (backward compatibility)
      objects.each { |obj| process_record(obj) }
    end

    # Override this to return true for pipeline-enabled migrations
    def use_batch_processing?
      false
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

          if use_batch_processing?
            batch_objects << obj

            # Process batch when full
            if batch_objects.size >= @batch_size
              process_batch_safely(batch_objects)
              batch_objects.clear
            end
          else
            process_single_record(key)
          end
        end

        break if cursor == '0'
      end

      # Process remaining objects in batch
      process_batch_safely(batch_objects) if use_batch_processing? && batch_objects.any?
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
