#!/usr/bin/env ruby
# frozen_string_literal: true

# Enriches transformed JSONL files with _original_record field for rollback/audit.
#
# Reads transformed files (output of transform.rb scripts) and adds _original_record
# to :object records. This centralizes original record capture that was previously
# scattered across individual transform.rb scripts.
#
# The script:
# 1. Loads the original dump file to build a lookup of v1 fields by key
# 2. Reads the transformed file
# 3. For each :object record, looks up v1 fields using v1_identifier
# 4. Adds _original_record to the v2 hash and re-dumps
# 5. Writes the enriched transformed file
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory with dump/transformed files (default: data/upgrades/v0.24.0)
#   --output-dir=DIR   Output directory (default: results, overwrites in place)
#   --dry-run          Show what would be generated without writing
#
# Input:
#   data/upgrades/v0.24.0/{model}/{model}_dump.jsonl        (original v1 dump - source of v1_fields)
#   data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (transformed v2 records - to be enriched)
#
# Output:
#   data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (enriched with _original_record in dump)
#
# For :object records, adds _original_record hash field with structure:
#   {
#     "object": { ...original hash fields from v1... },
#     "data_types": {},  # Reserved for related hashkeys/lists
#     "key": "original:redis:key",
#     "db": 6,
#     "exported_at": "2026-01-26T12:00:00Z"
#   }
#
# Binary Handling (for secret model):
#   Fields with invalid UTF-8 encoding are base64-encoded as {"_binary": "..."}
#   to preserve exact byte values for encrypted content.
#
# Note: This script runs AFTER transform.rb scripts. Transform scripts should
# NOT add _original_record since it's handled here.

require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'redis'
require 'familia'

# Calculate project root from script location
PROJECT_ROOT     = File.expand_path('../../..', __dir__)
DEFAULT_DATA_DIR = File.join(PROJECT_ROOT, 'data/upgrades/v0.24.0')

class OriginalRecordEnricher
  TEMP_KEY_PREFIX = '_enrich_tmp_'

  # Model configurations
  # model_name => { dump_file: input, transformed_file: input/output, v1_key_field: lookup }
  MODEL_CONFIG = {
    'customer' => {
      dump_file: 'customer_dump.jsonl',
      transformed_file: 'customer_transformed.jsonl',
      binary_safe: false,
    },
    'customdomain' => {
      dump_file: 'customdomain_dump.jsonl',
      transformed_file: 'customdomain_transformed.jsonl',
      binary_safe: false,
    },
    'metadata' => {
      # NOTE: metadata becomes receipt, but dump file is still metadata
      # The transformed file lives in data/upgrades/v0.24.0/metadata/ with plural name
      dump_file: 'metadata_dump.jsonl',
      transformed_file: 'receipt_transformed.jsonl',
      binary_safe: false,
    },
    'secret' => {
      dump_file: 'secret_dump.jsonl',
      transformed_file: 'secret_transformed.jsonl',
      binary_safe: true,
    },
  }.freeze

  def initialize(input_dir:, output_dir:, redis_url:, temp_db:, dry_run: false)
    @input_dir  = input_dir
    @output_dir = output_dir
    @redis_url  = redis_url
    @temp_db    = temp_db
    @dry_run    = dry_run
    @redis      = nil
    @timestamp  = Time.now.utc.iso8601

    @stats = Hash.new { |h, k| h[k] = { total: 0, enriched: 0, related: 0, not_found: 0, errors: [] } }
  end

  def run
    connect_redis unless @dry_run

    MODEL_CONFIG.each do |model, config|
      process_model(model, config)
    end

    print_summary
    @stats
  ensure
    @redis&.close
  end

  private

  def connect_redis
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
    @redis.ping
  rescue Redis::CannotConnectError => ex
    warn "Failed to connect to Redis: #{ex.message}"
    warn 'Redis is required for restore/dump operations.'
    exit 1
  end

  def process_model(model, config)
    # Both dump and transformed files live in the same subdirectory
    # (metadata/ for metadata->receipts, secret/ for secrets, etc.)
    subdir = model

    dump_file        = File.join(@input_dir, subdir, config[:dump_file])
    transformed_file = File.join(@input_dir, subdir, config[:transformed_file])

    unless File.exist?(dump_file)
      puts "Skipping #{model}: #{dump_file} not found"
      return
    end

    unless File.exist?(transformed_file)
      puts "Skipping #{model}: #{transformed_file} not found"
      return
    end

    puts "Processing #{model}..."

    if @dry_run
      dry_run_model(model, dump_file, transformed_file)
    else
      enrich_model(model, config, dump_file, transformed_file, subdir)
    end
  end

  def dry_run_model(model, dump_file, transformed_file)
    stats = @stats[model]

    # Count v1 object records
    v1_count = 0
    File.foreach(dump_file) do |line|
      record    = JSON.parse(line.chomp, symbolize_names: true)
      v1_count += 1 if record[:key]&.end_with?(':object')
    rescue JSON::ParserError
      # Skip malformed lines
    end

    # Count v2 object records
    File.foreach(transformed_file) do |line|
      stats[:total] += 1
      record         = JSON.parse(line.chomp, symbolize_names: true)

      if record[:key]&.end_with?(':object')
        stats[:enriched] += 1
      else
        stats[:related] += 1
      end
    rescue JSON::ParserError => ex
      stats[:errors] << { line: stats[:total], error: ex.message }
    end

    puts "  V1 object records: #{v1_count}"
    puts "  Would enrich #{stats[:enriched]} :object records (#{stats[:related]} related records unchanged)"
  end

  def enrich_model(model, config, dump_file, transformed_file, transformed_subdir)
    stats       = @stats[model]
    binary_safe = config[:binary_safe]

    # Step 1: Load v1 dump into memory, keyed by original key
    v1_lookup = load_v1_dump(dump_file, binary_safe)
    puts "  Loaded #{v1_lookup.size} v1 object records"

    # Step 2: Process transformed file
    output_file = File.join(@output_dir, transformed_subdir, config[:transformed_file])
    temp_file   = "#{output_file}.tmp"

    FileUtils.mkdir_p(File.dirname(output_file))

    File.open(temp_file, 'w') do |out|
      File.foreach(transformed_file) do |line|
        stats[:total] += 1
        record         = JSON.parse(line.chomp, symbolize_names: true)

        if record[:key]&.end_with?(':object')
          enriched = enrich_record(record, v1_lookup, binary_safe, stats)
          out.puts(JSON.generate(enriched))
        else
          # Related records (lists, sets, etc.) pass through unchanged
          stats[:related] += 1
          out.puts(line.chomp)
        end
      rescue JSON::ParserError => ex
        stats[:errors] << { line: stats[:total], error: ex.message }
        out.puts(line.chomp) # Preserve malformed lines
      end
    end

    # Atomic replace
    FileUtils.mv(temp_file, output_file)
    puts "  Enriched #{stats[:enriched]} :object records (#{stats[:related]} related records unchanged)"
    puts "  Output: #{output_file}"
    puts "  Not found in v1: #{stats[:not_found]}" if stats[:not_found] > 0
  end

  def load_v1_dump(dump_file, binary_safe)
    lookup = {}

    File.foreach(dump_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      next unless record[:key]&.end_with?(':object')

      # Restore dump and read v1 fields
      v1_fields = restore_and_read_hash(record)
      next unless v1_fields

      # Store with structure for _original_record
      lookup[record[:key]] = {
        'object' => binary_safe ? safe_encode_hash(v1_fields) : v1_fields,
        'data_types' => {},
        'key' => record[:key],
        'db' => record[:db],
        'exported_at' => @timestamp,
      }
    rescue JSON::ParserError
      # Skip malformed lines
    end

    lookup
  end

  def enrich_record(record, v1_lookup, _binary_safe, stats)
    # Get v1_identifier from the transformed hash to find original record
    v2_fields = restore_and_read_hash(record)

    unless v2_fields
      stats[:errors] << { key: record[:key], error: 'Failed to restore v2 dump' }
      return record
    end

    # Deserialize v1_identifier - transform scripts write v2 JSON-serialized values
    # e.g., "customer:email@example.com:object" is stored as "\"customer:email@example.com:object\""
    v1_key = deserialize_v2_value(v2_fields['v1_identifier'])

    unless v1_key
      stats[:not_found] += 1
      return record
    end

    original_record_data = v1_lookup[v1_key]

    unless original_record_data
      stats[:not_found] += 1
      return record
    end

    # Add _original_record to v2_fields
    v2_fields['_original_record'] = JSON.generate(original_record_data)

    # Re-create the dump with the new field
    new_dump = create_dump_from_hash(v2_fields)

    stats[:enriched] += 1

    # Return updated record
    record.merge(dump: new_dump)
  end

  def restore_and_read_hash(record)
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    @redis.restore(temp_key, 0, dump_data)
    @redis.hgetall(temp_key)
  rescue Redis::CommandError => ex
    warn "  Warning: Failed to restore #{record[:key]}: #{ex.message}"
    nil
  ensure
    @redis&.del(temp_key)
  end

  # Deserialize a single v2 JSON-encoded value back to Ruby type
  # Transform scripts write JSON-serialized values (e.g., "value" -> "\"value\"")
  def deserialize_v2_value(raw_value)
    return nil if raw_value.nil? || raw_value == 'null'
    return raw_value if raw_value.empty?

    Familia::JsonSerializer.parse(raw_value)
  rescue Familia::SerializerError
    raw_value # Fallback for non-JSON values
  end

  def create_dump_from_hash(fields)
    temp_key = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"

    # Filter nil values - Redis doesn't accept them
    clean_fields = fields.compact

    @redis.hmset(temp_key, clean_fields.to_a.flatten)
    dump_data = @redis.dump(temp_key)
    Base64.strict_encode64(dump_data)
  ensure
    @redis&.del(temp_key)
  end

  # Encode hash values safely for JSON, handling binary data
  def safe_encode_hash(hash)
    hash.transform_values do |value|
      if value.is_a?(String) && !value.valid_encoding?
        { '_binary' => Base64.strict_encode64(value) }
      elsif value.is_a?(String)
        begin
          value.encode('UTF-8')
        rescue Encoding::UndefinedConversionError
          { '_binary' => Base64.strict_encode64(value) }
        end
      else
        value
      end
    end
  end

  def print_summary
    puts "\n=== Original Record Enrichment Summary ==="
    @stats.each do |model, stats|
      puts "#{model}:"
      puts "  Total records:    #{stats[:total]}"
      puts "  :object enriched: #{stats[:enriched]}"
      puts "  Related records:  #{stats[:related]} (lists, sets - unchanged)"
      puts "  V1 not found:     #{stats[:not_found]}" if stats[:not_found] > 0
      next unless stats[:errors].any?

      puts "  Errors:           #{stats[:errors].size}"
      stats[:errors].first(5).each do |err|
        msg = err[:line] ? "Line #{err[:line]}" : err[:key]
        puts "    #{msg}: #{err[:error]}"
      end
    end
  end
end

def parse_args(args)
  options = {
    input_dir: DEFAULT_DATA_DIR,
    output_dir: DEFAULT_DATA_DIR,
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb [OPTIONS]

        Enriches transformed JSONL files with _original_record for rollback/audit.

        Options:
          --input-dir=DIR    Input directory (default: data/upgrades/v0.24.0)
          --output-dir=DIR   Output directory (default: data/upgrades/v0.24.0)
          --redis-url=URL    Redis URL for temp operations (env: VALKEY_URL or REDIS_URL)
          --temp-db=N        Temp database number (default: 15)
          --dry-run          Preview without writing
          --help             Show this help

        Input files:
          data/upgrades/v0.24.0/{model}/{model}_dump.jsonl        (v1 source)
          data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (to be enriched)

        Output:
          data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (with _original_record)

        For each :object record, adds _original_record hash field with:
          - object: Original v1 hash fields (binary-safe for secret)
          - data_types: {} (reserved for related data)
          - key: Original Redis key
          - db: Source database number
          - exported_at: Enrichment timestamp

        This script runs AFTER transform.rb scripts.
        Transform scripts should NOT add _original_record.
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

  enricher = OriginalRecordEnricher.new(
    input_dir: options[:input_dir],
    output_dir: options[:output_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )

  enricher.run
end
