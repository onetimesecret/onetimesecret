# lib/onetime/redis_key_migrator.rb

require 'redis'
require 'uri'
require 'logger'

module Onetime
  class RedisKeyMigrator
    attr_reader :source_uri, :target_uri, :options, :statistics, :logger

    DEFAULT_OPTIONS = {
      batch_size: 100,
      scan_count: 1000,
      timeout: 5000,
      redis_timeout: 30,  # Redis client connection timeout in seconds
      copy_mode: true,
      retry_attempts: 3,
      progress_interval: 100,
      max_keys_in_memory: 100_000,  # Switch to streaming mode above this threshold
      streaming_mode: false  # Force streaming mode regardless of key count
    }.freeze

    def initialize(source_uri, target_uri, options = {})
      @source_uri = source_uri.is_a?(String) ? URI.parse(source_uri) : source_uri
      @target_uri = target_uri.is_a?(String) ? URI.parse(target_uri) : target_uri
      @options = DEFAULT_OPTIONS.merge(options)
      @statistics = initialize_statistics
      @logger = options[:logger] || Logger.new($stdout, level: Logger::WARN)

      # Auto-adjust Redis timeout based on batch size if not explicitly set
      unless options.key?(:redis_timeout)
        @options[:redis_timeout] = calculate_redis_timeout(@options[:batch_size])
      end

      # Initialize adaptive progress tracking
      @last_progress_time = Time.now
      @adaptive_progress_interval = @options[:progress_interval]
    end

    def migrate_keys(pattern = '*', &progress_block)
      validate_migration_params

      strategy = determine_migration_strategy
      @logger.debug "Using migration strategy: #{strategy}"

      # Validate strategy consistency
      unless strategy == @statistics[:strategy_used]
        raise "Strategy mismatch: returned #{strategy}, but statistics show #{@statistics[:strategy_used]}"
      end

      # Check if we should use streaming mode based on initial scan
      if should_use_streaming_mode?(pattern)
        @logger.debug "Using streaming mode for large dataset migration"
        migrate_keys_streaming(pattern, strategy, &progress_block)
      else
        keys = discover_keys(pattern, &progress_block)
        return @statistics if keys.empty?

        case strategy
        when :migrate
          migrate_using_migrate_command(keys, &progress_block)
        when :dump_restore
          migrate_using_dump_restore(keys, &progress_block)
        else
          raise "Unknown migration strategy: #{strategy}"
        end
      end

      @statistics
    end

    def generate_cli_commands(pattern = '*')
      validate_migration_params
      strategy = determine_migration_strategy

      commands = {
        strategy: strategy,
        discovery: [],
        migration: [],
        verification: [],
        cleanup: []
      }

      # Key discovery command
      commands[:discovery] << "# Discover matching keys:"
      commands[:discovery] << "redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} --scan --pattern \"#{pattern}\""

      case strategy
      when :migrate
        commands[:migration] << "# Bulk migration (Redis 3.0.6+, same instance):"

        # For MIGRATE command, we need to show how to batch keys
        commands[:migration] << "# First, get the key list:"
        commands[:migration] << "KEYS=$(redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} --scan --pattern \"#{pattern}\")"
        commands[:migration] << ""
        commands[:migration] << "# Then migrate in batches (example with first 100 keys):"
        commands[:migration] << "redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} \\"
        commands[:migration] << "  MIGRATE #{@target_uri.host} #{@target_uri.port || 6379} \"\" #{extract_db_number(@target_uri)} 5000 COPY REPLACE KEYS \\"
        commands[:migration] << "  $(echo \"$KEYS\" | head -100 | tr '\\n' ' ')"

      when :dump_restore
        commands[:migration] << "# Cross-server migration using DUMP/RESTORE:"
        commands[:migration] << "# Note: This requires scripting for efficient batch processing"
        commands[:migration] << ""
        commands[:migration] << "# Example for single key migration:"
        commands[:migration] << "KEY=\"#{pattern.gsub('*', 'example')}\""
        commands[:migration] << "DUMP=$(redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} DUMP \"$KEY\")"
        commands[:migration] << "TTL=$(redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} PTTL \"$KEY\")"
        commands[:migration] << "redis-cli -h #{@target_uri.host} -p #{@target_uri.port || 6379} -n #{extract_db_number(@target_uri)} RESTORE \"$KEY\" \"$TTL\" \"$DUMP\" REPLACE"
      end

      # Verification commands
      commands[:verification] << "# Verify migration results:"
      commands[:verification] << "echo \"Source database key count:\""
      commands[:verification] << "redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} --scan --pattern \"#{pattern}\" | wc -l"
      commands[:verification] << ""
      commands[:verification] << "echo \"Target database key count:\""
      commands[:verification] << "redis-cli -h #{@target_uri.host} -p #{@target_uri.port || 6379} -n #{extract_db_number(@target_uri)} --scan --pattern \"#{pattern}\" | wc -l"
      commands[:verification] << ""
      commands[:verification] << "echo \"Sample keys in target:\""
      commands[:verification] << "redis-cli -h #{@target_uri.host} -p #{@target_uri.port || 6379} -n #{extract_db_number(@target_uri)} --scan --pattern \"#{pattern}\" | head -5"

      # Cleanup commands (user must run manually)
      commands[:cleanup] << "# ⚠️  DANGER: Delete keys from source (RUN AT YOUR OWN RISK)"
      commands[:cleanup] << "# Only run these commands if you're sure the migration was successful!"
      commands[:cleanup] << ""
      commands[:cleanup] << "# List keys that would be deleted:"
      commands[:cleanup] << "redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} --scan --pattern \"#{pattern}\""
      commands[:cleanup] << ""
      commands[:cleanup] << "# Delete keys (IRREVERSIBLE):"
      commands[:cleanup] << "redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} --scan --pattern \"#{pattern}\" | \\"
      commands[:cleanup] << "  xargs redis-cli -h #{@source_uri.host} -p #{@source_uri.port || 6379} -n #{extract_db_number(@source_uri)} DEL"

      commands
    end

    private

    def initialize_statistics
      {
        total_keys: 0,
        migrated_keys: 0,
        failed_keys: 0,
        start_time: nil,
        end_time: nil,
        strategy_used: nil,
        errors: []
      }
    end

    def validate_migration_params
      raise ArgumentError, "Source URI cannot be nil" unless @source_uri
      raise ArgumentError, "Target URI cannot be nil" unless @target_uri
      raise ArgumentError, "Source and target cannot be identical" if uris_identical?
    end

    def uris_identical?
      source_normalized = normalize_uri(@source_uri)
      target_normalized = normalize_uri(@target_uri)
      source_normalized == target_normalized
    end

    def normalize_uri(uri)
      port = uri.port || 6379
      "#{uri.host}:#{port}/#{uri.path&.gsub('/', '') || uri.db || 0}"
    end

    def determine_migration_strategy
      if same_redis_instance? && same_database?
        # Same instance, same database - no migration needed
        raise ArgumentError, "Source and target are identical"
      elsif same_redis_instance?
        # Same instance, different database - use MIGRATE command
        @statistics[:strategy_used] = :migrate
        :migrate
      else
        # Different instances - use DUMP/RESTORE (MIGRATE doesn't work well for this)
        @statistics[:strategy_used] = :dump_restore
        :dump_restore
      end
    end

    def same_redis_instance?
      @source_uri.host == @target_uri.host &&
      @source_uri.port == @target_uri.port &&
      @source_uri.user == @target_uri.user &&
      @source_uri.password == @target_uri.password
    end

    def same_database?
      extract_db_number(@source_uri) == extract_db_number(@target_uri)
    end

    def discover_keys(pattern, &progress_block)
      @logger.debug "Discovering keys with pattern: #{pattern}"

      keys = []
      cursor = 0
      discovered_count = 0

      source_client = create_redis_client(@source_uri)

      @statistics[:start_time] = Time.now

      loop do
        begin
          cursor, batch_keys = source_client.scan(
            cursor,
            match: pattern,
            count: @options[:scan_count]
          )

          keys.concat(batch_keys)
          discovered_count += batch_keys.size

          if block_given? && should_report_progress?(discovered_count)
            progress_block.call(:discovery, discovered_count, nil, nil, nil)
          end

          break if cursor == "0"
        rescue => e
          handle_error("Key discovery failed", e)
          break
        end
      end

      @statistics[:total_keys] = keys.size
      @logger.debug "Discovered #{keys.size} keys matching pattern #{pattern}"

      keys
    ensure
      source_client&.disconnect!
    end

    def migrate_using_migrate_command(keys, &progress_block)
      @logger.debug "Using MIGRATE command for same-instance migration"

      source_client = create_redis_client(@source_uri)
      migrated_count = 0

      keys.each_slice(@options[:batch_size]) do |batch|
        begin
          # Extract target database number
          target_db = extract_db_number(@target_uri)

          # Use MIGRATE with COPY flag for safety - bulk mode
          # For bulk migration, we use the raw call method since Redis gem's migrate method doesn't support KEYS
          migrate_args = [@target_uri.host, @target_uri.port, '', target_db, @options[:timeout], 'COPY', 'REPLACE', 'KEYS'] + batch

          source_client.call('MIGRATE', *migrate_args)

          migrated_count += batch.size
          @statistics[:migrated_keys] = migrated_count

          if progress_block
            batch.each_with_index do |key, idx|
              progress_block.call(:migrate, migrated_count - batch.size + idx, 'migrate', key, -1)
            end
          end

        rescue => e
          handle_batch_error(batch, e, source_client, nil, &progress_block)
        end
      end

    ensure
      source_client&.disconnect!
      @statistics[:end_time] = Time.now
    end

    def migrate_using_dump_restore(keys, &progress_block)
      @logger.debug "Using DUMP/RESTORE for cross-server migration"

      source_client = create_redis_client(@source_uri)
      target_client = create_redis_client(@target_uri)
      migrated_count = 0

      keys.each_slice(@options[:batch_size]) do |batch|
        begin
          # Pipeline DUMP operations
          dumps = source_client.pipelined do |pipe|
            batch.each { |key| pipe.dump(key) }
          end

          # Pipeline TTL operations
          ttls = source_client.pipelined do |pipe|
            batch.each { |key| pipe.pttl(key) }
          end

          # Pipeline RESTORE operations
          target_client.pipelined do |pipe|
            batch.each_with_index do |key, idx|
              next if dumps[idx].nil?

              ttl = ttls[idx] == -1 ? 0 : ttls[idx]
              pipe.restore(key, ttl, dumps[idx], replace: true)
            end
          end

          migrated_count += batch.size
          @statistics[:migrated_keys] = migrated_count

          if progress_block
            batch.each_with_index do |key, idx|
              progress_block.call(:migrate, migrated_count - batch.size + idx, 'dump_restore', key, ttls[idx])
            end
          end

        rescue => e
          handle_batch_error(batch, e, source_client, target_client, &progress_block)
        end
      end

    ensure
      source_client&.disconnect!
      target_client&.disconnect!
      @statistics[:end_time] = Time.now
    end

    def handle_batch_error(batch, error, source_client = nil, target_client = nil, &progress_block)
      @logger.error "Batch migration failed (#{batch.size} keys): #{error.message}"
      @statistics[:errors] << { batch: batch, error: error.message }

      # Try partial batch retry first for better performance
      if batch.size > 1 && @options[:retry_attempts] > 0
        @logger.debug "Attempting partial batch retry"
        retry_partial_batch(batch, source_client, target_client, &progress_block)
      else
        # Fall back to individual key migration
        @logger.debug "Falling back to individual key migration"
        retry_individual_keys(batch, source_client, target_client, &progress_block)
      end
    end

    # Try partial batch retry by splitting the failed batch into smaller chunks
    def retry_partial_batch(batch, source_client = nil, target_client = nil, &progress_block)
      # Split batch in half and retry each part
      mid_point = batch.size / 2
      first_half = batch[0...mid_point]
      second_half = batch[mid_point..-1]

      [first_half, second_half].each do |sub_batch|
        next if sub_batch.empty?

        begin
          @logger.debug "Retrying partial batch (#{sub_batch.size} keys)"

          if target_client.nil?
            # Same instance migration
            target_db = extract_db_number(@target_uri)
            migrate_args = [@target_uri.host, @target_uri.port, '', target_db, @options[:timeout], 'COPY', 'REPLACE', 'KEYS'] + sub_batch
            source_client.call('MIGRATE', *migrate_args)
          else
            # Cross-server migration
            dumps = source_client.pipelined { |pipe| sub_batch.each { |key| pipe.dump(key) } }
            ttls = source_client.pipelined { |pipe| sub_batch.each { |key| pipe.pttl(key) } }

            target_client.pipelined do |pipe|
              sub_batch.each_with_index do |key, idx|
                next if dumps[idx].nil?
                ttl = ttls[idx] == -1 ? 0 : ttls[idx]
                pipe.restore(key, ttl, dumps[idx], replace: true)
              end
            end
          end

          @statistics[:migrated_keys] += sub_batch.size
          @logger.debug "Partial batch retry successful (#{sub_batch.size} keys)"

        rescue => e
          @logger.debug "Partial batch retry failed (#{sub_batch.size} keys): #{e.message}"
          # If partial retry fails, fall back to individual key migration
          retry_individual_keys(sub_batch, source_client, target_client, &progress_block)
        end
      end
    end

    # Retry individual keys when batch operations fail
    def retry_individual_keys(batch, source_client = nil, target_client = nil, &progress_block)
      batch.each do |key|
        begin
          migrate_single_key(key, source_client, target_client, &progress_block)
        rescue => e
          handle_error("Failed to migrate key #{key}", e)
          @statistics[:failed_keys] += 1
        end
      end
    end

    def migrate_single_key(key, source_client = nil, target_client = nil, &progress_block)
      # Create clients if not provided (for backward compatibility)
      created_source_client = source_client.nil?
      created_target_client = target_client.nil?

      source_client ||= create_redis_client(@source_uri)
      target_client ||= create_redis_client(@target_uri) unless same_redis_instance?

      if same_redis_instance?
        # Extract target database number
        target_db = extract_db_number(@target_uri)

        # Use Redis gem's migrate method for single key migration
        migrate_options = {
          host: @target_uri.host,
          port: @target_uri.port,
          destination_db: target_db,
          timeout: @options[:timeout] / 1000.0,  # Redis gem expects timeout in seconds
          copy: @options[:copy_mode],
          replace: true
        }
        source_client.migrate(key, migrate_options)
      else
        dumped = source_client.dump(key)
        return unless dumped

        ttl = source_client.pttl(key)
        ttl = 0 if ttl == -1

        target_client.restore(key, ttl, dumped, replace: true)
      end

      @statistics[:migrated_keys] += 1
      progress_block&.call(:migrate, @statistics[:migrated_keys], 'single', key, -1)

    ensure
      # Only disconnect clients we created
      source_client&.disconnect! if created_source_client
      target_client&.disconnect! if created_target_client
    end

    def handle_error(context, error)
      error_msg = "#{context}: #{error.message}"
      @logger.error error_msg
      @statistics[:errors] << { context: context, error: error.message }
    end

    def extract_db_number(uri)
      if uri.path && !uri.path.empty? && uri.path != '/'
        uri.path.gsub('/', '').to_i
      elsif uri.respond_to?(:db) && uri.db
        uri.db.to_i
      else
        0
      end
    end

    def create_redis_client(uri)
      # Extract database number from path or use the db attribute
      db_number = extract_db_number(uri)

      Redis.new(
        host: uri.host,
        port: uri.port || 6379,
        db: db_number,
        password: uri.password,
        username: uri.user,
        timeout: @options[:redis_timeout],
        reconnect_attempts: 3
      )
    end

    # Calculate appropriate Redis timeout based on expected operation complexity
    def calculate_redis_timeout(batch_size)
      # Base timeout: 30 seconds
      # Add 2 seconds per 100 keys in batch (for large batch operations)
      # Minimum: 30 seconds, Maximum: 300 seconds (5 minutes)
      base_timeout = 30
      additional_timeout = (batch_size / 100.0) * 2

      [base_timeout + additional_timeout, 300].min.to_i
    end

    # Adaptive progress reporting to avoid overwhelming output for large migrations
    def should_report_progress?(current_count)
      return true if current_count % @adaptive_progress_interval == 0

      # Dynamically adjust interval based on volume
      # For large datasets (>10k keys), reduce frequency to avoid spam
      if current_count > 10_000 && @adaptive_progress_interval < 1000
        @adaptive_progress_interval = [current_count / 100, 1000].min
      elsif current_count > 1_000 && @adaptive_progress_interval < 100
        @adaptive_progress_interval = [current_count / 50, 100].min
      end

      current_count % @adaptive_progress_interval == 0
    end

    # Determine if streaming mode should be used for large datasets
    def should_use_streaming_mode?(pattern)
      return true if @options[:streaming_mode]

      # Quick sample scan to estimate total key count
      source_client = create_redis_client(@source_uri)
      sample_cursor, sample_keys = source_client.scan(0, match: pattern, count: 1000)
      source_client.disconnect!

      # If we get a full batch (1000 keys) in one scan, dataset is likely large
      sample_keys.size >= 1000
    rescue
      # If estimation fails, default to regular mode
      false
    end

    # Memory-efficient streaming migration for large datasets
    def migrate_keys_streaming(pattern, strategy, &progress_block)
      @logger.debug "Starting streaming migration for pattern: #{pattern}"

      source_client = create_redis_client(@source_uri)
      target_client = create_redis_client(@target_uri) unless strategy == :migrate

      @statistics[:start_time] = Time.now
      cursor = 0
      migrated_count = 0
      batch_buffer = []

      loop do
        begin
          # Scan for next batch of keys
          cursor, keys = source_client.scan(
            cursor,
            match: pattern,
            count: @options[:scan_count]
          )

          batch_buffer.concat(keys)
          @statistics[:total_keys] += keys.size

          # Process full batches immediately to keep memory usage low
          while batch_buffer.size >= @options[:batch_size]
            batch = batch_buffer.shift(@options[:batch_size])

            case strategy
            when :migrate
              migrate_batch_streaming(batch, source_client, nil, &progress_block)
            when :dump_restore
              migrate_batch_streaming(batch, source_client, target_client, &progress_block)
            end

            migrated_count += batch.size
            @statistics[:migrated_keys] = migrated_count

            if should_report_progress?(migrated_count)
              progress_block&.call(:migrate, migrated_count, "streaming_#{strategy}", nil, -1)
            end
          end

          break if cursor == "0"
        rescue => e
          handle_error("Streaming migration failed", e)
          break
        end
      end

      # Process remaining keys in buffer
      unless batch_buffer.empty?
        case strategy
        when :migrate
          migrate_batch_streaming(batch_buffer, source_client, nil, &progress_block)
        when :dump_restore
          migrate_batch_streaming(batch_buffer, source_client, target_client, &progress_block)
        end

        @statistics[:migrated_keys] += batch_buffer.size
      end

    ensure
      source_client&.disconnect!
      target_client&.disconnect!
      @statistics[:end_time] = Time.now
    end

    # Process a batch of keys in streaming mode
    def migrate_batch_streaming(batch, source_client, target_client, &progress_block)
      if target_client.nil?
        # Same instance migration using MIGRATE command
        target_db = extract_db_number(@target_uri)
        migrate_args = [@target_uri.host, @target_uri.port, '', target_db, @options[:timeout], 'COPY', 'REPLACE', 'KEYS'] + batch
        source_client.call('MIGRATE', *migrate_args)
      else
        # Cross-server migration using DUMP/RESTORE
        dumps = source_client.pipelined { |pipe| batch.each { |key| pipe.dump(key) } }
        ttls = source_client.pipelined { |pipe| batch.each { |key| pipe.pttl(key) } }

        target_client.pipelined do |pipe|
          batch.each_with_index do |key, idx|
            next if dumps[idx].nil?
            ttl = ttls[idx] == -1 ? 0 : ttls[idx]
            pipe.restore(key, ttl, dumps[idx], replace: true)
          end
        end
      end
    rescue => e
      # Fall back to individual key migration for failed batch
      handle_batch_error(batch, e, source_client, target_client, &progress_block)
    end
  end
end
