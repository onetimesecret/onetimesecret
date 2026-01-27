#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads migrated data into Valkey/Redis from transformed JSONL files.
# Processes both transformed records (RESTORE) and index commands (ZADD/HSET/etc).
#
# Usage:
#   ruby scripts/migrations/2026-01-26/load_keys.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR      Input directory with model subdirs (default: exports)
#   --valkey-url=URL     Valkey/Redis URL (default: redis://127.0.0.1:6379)
#   --model=NAME         Load only specific model (customer, organization, customdomain, receipt, secret)
#   --dry-run            Count records without loading
#   --skip-indexes       Load only transformed records (skip index commands)
#   --skip-records       Load only indexes (skip RESTORE operations)
#
# Models are loaded in dependency order: customer -> organization -> customdomain -> receipt -> secret
#
# Input files per model (in subdirs):
#   - {model}_transformed.jsonl: Records to RESTORE (with dump blobs)
#   - {model}_indexes.jsonl: Redis commands to execute (ZADD, HSET, SADD, INCRBY)

require 'redis'
require 'json'
require 'base64'

class KeyLoader
  # Models in dependency order with their target databases
  MODELS = {
    'customer' => { db: 6 },
    'organization' => { db: 6 },
    'customdomain' => { db: 6 },
    'receipt' => { db: 7 },
    'secret' => { db: 8 },
  }.freeze

  VALID_COMMANDS = %w[ZADD HSET SADD INCRBY].freeze

  def initialize(input_dir:, valkey_url:, model: nil, dry_run: false, skip_indexes: false, skip_records: false)
    @input_dir     = input_dir
    @valkey_url    = valkey_url
    @target_model  = model
    @dry_run       = dry_run
    @skip_indexes  = skip_indexes
    @skip_records  = skip_records
    @redis_clients = {}

    @stats = Hash.new do |h, k|
      h[k] = {
        records_restored: 0,
        records_skipped: 0,
        indexes_executed: 0,
        indexes_skipped: 0,
        errors: [],
      }
    end
  end

  def run
    validate_options
    models_to_load = determine_models

    if models_to_load.empty?
      puts 'No models to load.'
      return @stats
    end

    puts "Loading #{models_to_load.join(', ')} from #{@input_dir}"
    puts "Target: #{@valkey_url}"
    puts "Mode: #{mode_description}"
    puts

    models_to_load.each do |model_name|
      load_model(model_name)
    end

    print_summary
    exit_with_status
  ensure
    close_connections
  end

  private

  def validate_options
    unless Dir.exist?(@input_dir)
      raise ArgumentError, "Input directory not found: #{@input_dir}"
    end

    if @target_model && !MODELS.key?(@target_model)
      raise ArgumentError, "Unknown model: #{@target_model}. Valid models: #{MODELS.keys.join(', ')}"
    end

    if @skip_indexes && @skip_records
      raise ArgumentError, 'Cannot specify both --skip-indexes and --skip-records'
    end
  end

  def determine_models
    if @target_model
      [@target_model]
    else
      MODELS.keys
    end
  end

  def mode_description
    parts = []
    parts << 'dry-run' if @dry_run
    parts << 'records only' if @skip_indexes
    parts << 'indexes only' if @skip_records
    parts << 'full load' if parts.empty?
    parts.join(', ')
  end

  def load_model(model_name)
    puts "=== Loading #{model_name} ==="
    model_dir = File.join(@input_dir, model_name)

    unless Dir.exist?(model_dir)
      puts "  Skipping: directory not found (#{model_dir})"
      @stats[model_name][:errors] << { error: "Directory not found: #{model_dir}" }
      return
    end

    # Load transformed records (RESTORE)
    unless @skip_records
      transformed_file = File.join(model_dir, "#{model_name}_transformed.jsonl")
      if File.exist?(transformed_file)
        load_transformed_records(model_name, transformed_file)
      else
        puts "  No transformed file: #{transformed_file}"
      end
    end

    # Execute index commands
    unless @skip_indexes
      indexes_file = File.join(model_dir, "#{model_name}_indexes.jsonl")
      if File.exist?(indexes_file)
        execute_index_commands(model_name, indexes_file)
      else
        puts "  No indexes file: #{indexes_file}"
      end
    end

    puts
  end

  def load_transformed_records(model_name, file_path)
    puts "  Loading records from #{File.basename(file_path)}..."
    target_db = MODELS[model_name][:db]
    redis     = get_redis(target_db)

    File.foreach(file_path) do |line|
      record = JSON.parse(line, symbolize_names: true)
      restore_record(model_name, redis, record)
    rescue JSON::ParserError => ex
      @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
    end

    puts "    Records restored: #{@stats[model_name][:records_restored]}"
    puts "    Records skipped: #{@stats[model_name][:records_skipped]}" if @stats[model_name][:records_skipped] > 0
  end

  def restore_record(model_name, redis, record)
    key      = record[:key]
    dump_b64 = record[:dump]
    ttl_ms   = record[:ttl_ms]

    unless key && dump_b64
      @stats[model_name][:records_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: 'Missing key or dump data' }
      return
    end

    if @dry_run
      @stats[model_name][:records_restored] += 1
      return
    end

    # Decode the dump blob
    dump_data = Base64.strict_decode64(dump_b64)

    # Determine TTL for RESTORE command
    # -1 in source means no expiry -> use 0 in RESTORE
    # Otherwise use the ttl_ms value directly
    restore_ttl = ttl_ms == -1 ? 0 : ttl_ms.to_i

    # RESTORE key ttl serialized-value REPLACE
    redis.restore(key, restore_ttl, dump_data, replace: true)
    @stats[model_name][:records_restored] += 1
  rescue ArgumentError => ex
    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: "Base64 decode failed: #{ex.message}" }
  rescue Redis::CommandError => ex
    @stats[model_name][:records_skipped] += 1
    @stats[model_name][:errors] << { key: key, error: "RESTORE failed: #{ex.message}" }
  end

  def execute_index_commands(model_name, file_path)
    puts "  Executing indexes from #{File.basename(file_path)}..."
    target_db = MODELS[model_name][:db]
    redis     = get_redis(target_db)

    File.foreach(file_path) do |line|
      cmd = JSON.parse(line, symbolize_names: true)
      execute_command(model_name, redis, cmd)
    rescue JSON::ParserError => ex
      @stats[model_name][:errors] << { error: "JSON parse error: #{ex.message}" }
    end

    puts "    Index commands executed: #{@stats[model_name][:indexes_executed]}"
    puts "    Index commands skipped: #{@stats[model_name][:indexes_skipped]}" if @stats[model_name][:indexes_skipped] > 0
  end

  def execute_command(model_name, redis, cmd)
    command = cmd[:command]
    key     = cmd[:key]
    args    = cmd[:args]

    unless VALID_COMMANDS.include?(command)
      @stats[model_name][:indexes_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: "Unknown command: #{command}" }
      return
    end

    unless key && args.is_a?(Array)
      @stats[model_name][:indexes_skipped] += 1
      @stats[model_name][:errors] << { key: key, error: 'Missing key or args' }
      return
    end

    if @dry_run
      @stats[model_name][:indexes_executed] += 1
      return
    end

    case command
    when 'ZADD'
      # args: [score, member] or [score, member, score, member, ...]
      redis.zadd(key, args)
    when 'HSET'
      # args: [field, value] or [field, value, field, value, ...]
      redis.hset(key, *args)
    when 'SADD'
      # args: [member, ...]
      redis.sadd(key, args)
    when 'INCRBY'
      # args: [increment]
      redis.incrby(key, args.first.to_i)
    end

    @stats[model_name][:indexes_executed] += 1
  rescue Redis::CommandError => ex
    @stats[model_name][:indexes_skipped] += 1
    @stats[model_name][:errors] << { key: key, command: command, error: ex.message }
  end

  def get_redis(db)
    @redis_clients[db] ||= begin
      client = Redis.new(url: "#{@valkey_url}/#{db}")
      client.ping # Verify connection
      client
    rescue Redis::CannotConnectError => ex
      warn "Failed to connect to Redis (DB #{db}): #{ex.message}"
      exit 1
    end
  end

  def close_connections
    @redis_clients.each_value(&:close)
    @redis_clients.clear
  end

  def print_summary
    puts '=' * 60
    puts 'LOAD SUMMARY'
    puts '=' * 60
    puts

    total_records = 0
    total_indexes = 0
    total_errors  = 0

    @stats.each do |model_name, stats|
      puts "#{model_name}:"
      puts "  Records restored:      #{stats[:records_restored]}"
      puts "  Records skipped:       #{stats[:records_skipped]}" if stats[:records_skipped] > 0
      puts "  Index commands:        #{stats[:indexes_executed]}"
      puts "  Index commands skipped: #{stats[:indexes_skipped]}" if stats[:indexes_skipped] > 0
      puts "  Errors:                #{stats[:errors].size}" if stats[:errors].any?
      puts

      total_records += stats[:records_restored]
      total_indexes += stats[:indexes_executed]
      total_errors  += stats[:errors].size
    end

    puts '-' * 60
    puts 'TOTALS:'
    puts "  Records restored:      #{total_records}"
    puts "  Index commands:        #{total_indexes}"
    puts "  Total errors:          #{total_errors}"
    puts

    return unless total_errors > 0

    puts 'ERRORS (first 20):'
    error_count = 0
    @stats.each do |model_name, stats|
      stats[:errors].each do |err|
        break if error_count >= 20

        puts "  [#{model_name}] #{err}"
        error_count += 1
      end
      break if error_count >= 20
    end
    puts "  ... and #{total_errors - 20} more" if total_errors > 20
  end

  def exit_with_status
    total_errors = @stats.values.sum { |s| s[:errors].size }
    exit(1) if total_errors > 0
  end
end

def parse_args(args)
  options = {
    input_dir: 'exports',
    valkey_url: 'redis://127.0.0.1:6379',
    model: nil,
    dry_run: false,
    skip_indexes: false,
    skip_records: false,
  }

  args.each do |arg|
    case arg
    when /\A--input-dir=(.+)\z/
      options[:input_dir] = Regexp.last_match(1)
    when /\A--valkey-url=(.+)\z/
      options[:valkey_url] = Regexp.last_match(1)
    when /\A--model=(.+)\z/
      options[:model] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--skip-indexes'
      options[:skip_indexes] = true
    when '--skip-records'
      options[:skip_records] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/2026-01-26/load_keys.rb [OPTIONS]

        Loads migrated data into Valkey/Redis from transformed JSONL files.

        Options:
          --input-dir=DIR      Input directory with model subdirs (default: exports)
          --valkey-url=URL     Valkey/Redis URL (default: redis://127.0.0.1:6379)
          --model=NAME         Load only specific model
          --dry-run            Count records without loading
          --skip-indexes       Load only transformed records (skip index commands)
          --skip-records       Load only indexes (skip RESTORE operations)
          --help               Show this help

        Models (loaded in dependency order):
          customer       -> DB 6
          organization   -> DB 6
          customdomain   -> DB 6
          receipt        -> DB 7
          secret         -> DB 8

        Input files per model (in subdirs):
          {model}_transformed.jsonl   Records to RESTORE (with dump blobs)
          {model}_indexes.jsonl       Redis commands (ZADD, HSET, SADD, INCRBY)

        Examples:
          # Load all models
          ruby load_keys.rb --valkey-url=redis://localhost:6379

          # Load single model
          ruby load_keys.rb --model=customer

          # Dry run to see counts
          ruby load_keys.rb --dry-run

          # Load only transformed records (no indexes)
          ruby load_keys.rb --skip-indexes

          # Load only indexes (no RESTORE)
          ruby load_keys.rb --skip-records
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  loader = KeyLoader.new(
    input_dir: options[:input_dir],
    valkey_url: options[:valkey_url],
    model: options[:model],
    dry_run: options[:dry_run],
    skip_indexes: options[:skip_indexes],
    skip_records: options[:skip_records],
  )

  loader.run
end
