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
      copy_mode: true,
      retry_attempts: 3,
      progress_interval: 100
    }.freeze

    def initialize(source_uri, target_uri, options = {})
      @source_uri = source_uri.is_a?(String) ? URI.parse(source_uri) : source_uri
      @target_uri = target_uri.is_a?(String) ? URI.parse(target_uri) : target_uri
      @options = DEFAULT_OPTIONS.merge(options)
      @statistics = initialize_statistics
      @logger = options[:logger] || Logger.new($stdout, level: Logger::WARN)
    end

    def migrate_keys(pattern = '*', &progress_block)
      validate_migration_params

      strategy = determine_migration_strategy
      @logger.debug "Using migration strategy: #{strategy}"

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
      "#{uri.host}:#{uri.port}/#{uri.path&.gsub('/', '') || uri.db || 0}"
    end

    def determine_migration_strategy
      if same_redis_instance? && same_database?
        # Same instance, same database - no migration needed
        raise ArgumentError, "Source and target are identical"
      elsif same_redis_instance?
        # Same instance, different database - use DUMP/RESTORE (MIGRATE doesn't work well for this)
        @statistics[:strategy_used] = :dump_restore
        :dump_restore
      else
        # Different instances - use MIGRATE command
        @statistics[:strategy_used] = :migrate
        :migrate
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

          if block_given? && discovered_count % @options[:progress_interval] == 0
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
          target_db = if @target_uri.path && !@target_uri.path.empty? && @target_uri.path != '/'
                        @target_uri.path.gsub('/', '').to_i
                      elsif @target_uri.respond_to?(:db) && @target_uri.db
                        @target_uri.db.to_i
                      else
                        0
                      end

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
          handle_batch_error(batch, e, &progress_block)
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
          handle_batch_error(batch, e, &progress_block)
        end
      end

    ensure
      source_client&.disconnect!
      target_client&.disconnect!
      @statistics[:end_time] = Time.now
    end

    def handle_batch_error(batch, error, &progress_block)
      @logger.error "Batch migration failed: #{error.message}"
      @statistics[:errors] << { batch: batch, error: error.message }

      # Try individual key migration for failed batch
      batch.each do |key|
        begin
          migrate_single_key(key, &progress_block)
        rescue => e
          handle_error("Failed to migrate key #{key}", e)
          @statistics[:failed_keys] += 1
        end
      end
    end

    def migrate_single_key(key, &progress_block)
      source_client = create_redis_client(@source_uri)
      target_client = create_redis_client(@target_uri)

      if same_redis_instance?
        # Extract target database number
        target_db = if @target_uri.path && !@target_uri.path.empty? && @target_uri.path != '/'
                      @target_uri.path.gsub('/', '').to_i
                    elsif @target_uri.respond_to?(:db) && @target_uri.db
                      @target_uri.db.to_i
                    else
                      0
                    end

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
      source_client&.disconnect!
      target_client&.disconnect!
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
        timeout: 30,
        reconnect_attempts: 3
      )
    end
  end
end
