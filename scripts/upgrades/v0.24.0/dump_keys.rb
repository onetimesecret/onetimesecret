#!/usr/bin/env ruby
# frozen_string_literal: true

# Dumps Redis keys to JSONL format for migration, organized by model.
# Each line: {"key": "...", "type": "...", "ttl_ms": ..., "dump": "<base64>", "created": ...}
#
# Usage:
#   ruby scripts/dump_keys.rb [OPTIONS]
#
# Options:
#   --db=N           Database number to dump (required, or use --all)
#   --all            Dump all migration databases (6, 7, 8, 11)
#   --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
#   --output-dir=DIR Output directory (default: data/upgrades/v0.24.0 in project root)
#   --dry-run        Show what would be dumped without writing
#
# Output files per model: data/upgrades/v0.24.0/customer/customer_dump.jsonl, etc.
# Includes 'created' timestamp for UUIDv7 generation during transform.
# Idempotent: each run overwrites existing model files.

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'uri'

# Calculate project root from script location (scripts/upgrades/v0.24.0/)
PROJECT_ROOT     = File.expand_path('../../..', __dir__)
DEFAULT_DATA_DIR = File.join(PROJECT_ROOT, 'data/upgrades/v0.24.0')

class KeyDumper
  MIGRATION_DBS = [6, 7, 8, 11].freeze

  # Map key prefixes to model names and their source databases
  # Format: prefix => { model: output_name, db: source_db }
  MODEL_MAPPING = {
    'customer' => { model: 'customer', db: 6 },
    'customdomain' => { model: 'customdomain', db: 6 },
    'onetime' => { model: 'customer', db: 6 },  # legacy: onetime:customer instances
    'metadata' => { model: 'metadata', db: 7 },  # becomes receipt
    'secret' => { model: 'secret', db: 8 },
    'feedback' => { model: 'feedback', db: 11 },
  }.freeze

  # Keys that are hash types and have a 'created' field
  MODELS_WITH_CREATED = %w[customer customdomain metadata secret].freeze

  def initialize(redis_url:, output_dir:, dry_run: false)
    @redis_url   = redis_url
    @output_dir  = output_dir
    @dry_run     = dry_run
    @timestamp   = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
    @model_files = {}
    @model_stats = Hash.new { |h, k| h[k] = { total: 0, dumped: 0, skipped: 0, errors: [] } }
  end

  # Build Redis URL with specified database number, properly handling existing path/query
  def redis_url_for_db(db_number)
    uri      = URI.parse(@redis_url)
    uri.path = "/#{db_number}"
    uri.to_s
  end

  def dump_database(db_number)
    redis = Redis.new(url: redis_url_for_db(db_number))

    if @dry_run
      puts "DRY RUN: Would dump DB #{db_number}"
      stats = { total: 0, dumped: 0, skipped: 0, errors: [] }
      count_keys(redis, stats)
      return stats
    end

    FileUtils.mkdir_p(@output_dir)

    scan_and_dump(redis, db_number)

    # Close any open files for this DB
    close_model_files

    # Print stats per model
    @model_stats.each do |model, stats|
      puts "  #{model}: #{stats[:dumped]} keys dumped"
      puts "    Skipped: #{stats[:skipped]}, Errors: #{stats[:errors].size}" if stats[:skipped] > 0 || stats[:errors].any?
    end

    @model_stats
  end

  def dump_all
    FileUtils.mkdir_p(@output_dir) unless @dry_run

    # Process all databases in one pass, collecting into model files
    MIGRATION_DBS.each do |db|
      puts "Processing DB #{db}..."
      redis = Redis.new(url: redis_url_for_db(db))

      if @dry_run
        stats = { total: 0, dumped: 0, skipped: 0, errors: [] }
        count_keys(redis, stats)
      else
        scan_and_dump(redis, db)
      end
    end

    # Close files and print stats
    close_model_files

    @model_stats.each do |model, stats|
      puts "#{model}: #{stats[:dumped]} keys dumped to #{model}/#{model}_dump.jsonl"
      puts "  Skipped: #{stats[:skipped]}, Errors: #{stats[:errors].size}" if stats[:skipped] > 0 || stats[:errors].any?
    end

    # Write combined manifest
    write_combined_manifest(MIGRATION_DBS) unless @dry_run

    @model_stats
  end

  private

  def count_keys(redis, stats)
    cursor = '0'
    loop do
      cursor, keys   = redis.scan(cursor, count: 1000)
      stats[:total] += keys.size
      break if cursor == '0'
    end
    puts "  Would dump #{stats[:total]} keys"
  end

  def scan_and_dump(redis, db_number)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, count: 1000)

      keys.each do |key|
        dump_key(redis, key, db_number)
      end

      break if cursor == '0'
    end
  end

  def get_model_for_key(key)
    prefix = key.split(':').first
    MODEL_MAPPING[prefix]
  end

  def get_file_for_model(model_name)
    @model_files[model_name] ||= begin
      model_dir = File.join(@output_dir, model_name)
      FileUtils.mkdir_p(model_dir)
      filename  = File.join(model_dir, "#{model_name}_dump.jsonl")
      File.open(filename, 'w')
    end
  end

  def close_model_files
    @model_files.each_value(&:close)
    @model_files.clear
  end

  def dump_key(redis, key, db_number)
    model_info = get_model_for_key(key)

    # Skip keys that don't match our model mapping
    unless model_info
      return
    end

    model_name     = model_info[:model]
    stats          = @model_stats[model_name]
    stats[:total] += 1

    # Get key type
    key_type = redis.type(key)

    # Skip if key expired between scan and type check
    if key_type == 'none'
      stats[:skipped] += 1
      return
    end

    # Get TTL in milliseconds (-1 = no expiry, -2 = key doesn't exist)
    ttl_ms = redis.pttl(key)

    if ttl_ms == -2
      stats[:skipped] += 1
      return
    end

    # Get serialized value
    dump_data = redis.dump(key)

    if dump_data.nil?
      stats[:skipped] += 1
      return
    end

    record = {
      key: key,
      type: key_type,
      ttl_ms: ttl_ms,
      db: db_number,
      dump: Base64.strict_encode64(dump_data),
    }

    # Extract 'created' field for hash types that have it (needed for UUIDv7)
    if key_type == 'hash' && key.end_with?(':object')
      prefix = key.split(':').first
      if MODELS_WITH_CREATED.include?(prefix)
        created          = redis.hget(key, 'created')
        record[:created] = created.to_i if created && !created.empty?
      end
    end

    file            = get_file_for_model(model_name)
    file.puts(JSON.generate(record))
    stats[:dumped] += 1
  rescue Redis::CommandError => ex
    stats[:errors] << { key: key, error: ex.message }
  end

  def write_combined_manifest(databases)
    manifest_file = File.join(@output_dir, "dump_manifest_#{@timestamp}.json")

    model_summaries = {}
    @model_stats.each do |model, stats|
      model_summaries[model] = {
        file: "#{model}/#{model}_dump.jsonl",
        total_scanned: stats[:total],
        dumped: stats[:dumped],
        skipped: stats[:skipped],
        errors: stats[:errors].size,
      }
    end

    manifest = {
      source_url: @redis_url.sub(/:[^:@]*@/, ':***@'), # Redact password
      timestamp: @timestamp,
      databases_processed: databases,
      models: model_summaries,
      errors: @model_stats.flat_map { |_, s| s[:errors] }.first(20),
    }

    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "\nManifest written to #{manifest_file}"
  end
end

def parse_args(args)
  options = {
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    output_dir: DEFAULT_DATA_DIR,
    dry_run: false,
    db: nil,
    all: false,
  }

  args.each do |arg|
    case arg
    when /^--db=(\d+)$/
      options[:db] = Regexp.last_match(1).to_i
    when '--all'
      options[:all] = true
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/dump_keys.rb [OPTIONS]

        Options:
          --db=N           Database number to dump
          --all            Dump migration databases (6, 7, 8, 11)
          --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
          --output-dir=DIR Output directory (default: #{DEFAULT_DATA_DIR})
          --dry-run        Show what would be dumped
          --help           Show this help

        Output files per model (in subdirectories):
          data/upgrades/v0.24.0/customer/customer_dump.jsonl
          data/upgrades/v0.24.0/customdomain/customdomain_dump.jsonl
          data/upgrades/v0.24.0/metadata/metadata_dump.jsonl
          data/upgrades/v0.24.0/secret/secret_dump.jsonl
          data/upgrades/v0.24.0/feedback/feedback_dump.jsonl

        Each record includes 'created' timestamp for UUIDv7 generation.
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  unless options[:db] || options[:all]
    puts 'Error: Must specify --db=N or --all'
    puts 'Use --help for usage'
    exit 1
  end

  dumper = KeyDumper.new(
    redis_url: options[:redis_url],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  if options[:all]
    dumper.dump_all
  else
    dumper.dump_database(options[:db])
  end
end
