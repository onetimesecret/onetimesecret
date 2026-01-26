#!/usr/bin/env ruby
# frozen_string_literal: true

# Dumps Redis keys to JSONL format for migration, organized by model prefix.
# Each line: {"key": "...", "type": "...", "ttl_ms": ..., "dump": "<base64>", "created": "..."}
#
# For hash records, also extracts the 'created' field using HGET to preserve
# historical timestamps for UUIDv7 generation during transformation.
#
# Usage:
#   ruby scripts/dump_keys.rb [OPTIONS]
#
# Options:
#   --model=NAME     Model to dump (customer, customdomain, metadata, secret, feedback)
#   --all            Dump all models
#   --redis-url=URL  Redis URL (default: redis://127.0.0.1:6379)
#   --output-dir=DIR Output directory (default: exports)
#   --dry-run        Show what would be dumped without writing
#
# Output files are timestamped: customer_dump_20260124T120000Z.jsonl
# Idempotent: each run creates new files, never modifies existing.

require 'redis'
require 'json'
require 'base64'
require 'fileutils'

class KeyDumper
  MODEL_DB_MAP = {
    'customer' => 6,
    'customdomain' => 6,
    'metadata' => 7,
    'secret' => 8,
    'feedback' => 11,
  }.freeze

  VALID_MODELS = MODEL_DB_MAP.keys.freeze

  def initialize(redis_url:, output_dir:, dry_run: false)
    @redis_url  = redis_url
    @output_dir = output_dir
    @dry_run    = dry_run
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  end

  def dump_model(model_name)
    unless MODEL_DB_MAP.key?(model_name)
      raise ArgumentError, "Unknown model: #{model_name}. Valid: #{VALID_MODELS.join(', ')}"
    end

    db_number   = MODEL_DB_MAP[model_name]
    redis       = Redis.new(url: "#{@redis_url}/#{db_number}")
    output_file = File.join(@output_dir, "#{model_name}_dump_#{@timestamp}.jsonl")

    stats = { total: 0, dumped: 0, skipped: 0, errors: [] }

    if @dry_run
      puts "DRY RUN: Would dump model '#{model_name}' from DB #{db_number} to #{output_file}"
      count_keys_for_model(redis, model_name, stats)
      return stats
    end

    FileUtils.mkdir_p(@output_dir)

    File.open(output_file, 'w') do |f|
      scan_and_dump_model(redis, model_name, f, stats)
    end

    write_manifest(model_name, db_number, output_file, stats)

    puts "#{model_name}: #{stats[:dumped]} keys dumped to #{output_file}"
    puts "  Skipped: #{stats[:skipped]}, Errors: #{stats[:errors].size}"

    stats
  end

  def dump_all_models
    results = {}
    VALID_MODELS.each do |model|
      results[model] = dump_model(model)
    end
    results
  end

  private

  def key_matches_model?(key, model_name)
    case model_name
    when 'feedback'
      # feedback is a single key, exact match
      key == 'feedback'
    else
      # Other models use prefix pattern: model:* or model:id:suffix
      key.start_with?("#{model_name}:")
    end
  end

  def count_keys_for_model(redis, model_name, stats)
    cursor = '0'
    loop do
      cursor, keys   = redis.scan(cursor, count: 1000)
      matching       = keys.count { |key| key_matches_model?(key, model_name) }
      stats[:total] += matching
      break if cursor == '0'
    end
    puts "  Would dump #{stats[:total]} keys"
  end

  def scan_and_dump_model(redis, model_name, file, stats)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, count: 1000)

      keys.each do |key|
        next unless key_matches_model?(key, model_name)

        stats[:total] += 1
        dump_key(redis, file, key, stats)
      end

      break if cursor == '0'
    end
  end

  def dump_key(redis, file, key, stats)
    key_type = redis.type(key)

    if key_type == 'none'
      stats[:skipped] += 1
      return
    end

    ttl_ms = redis.pttl(key)

    if ttl_ms == -2
      stats[:skipped] += 1
      return
    end

    dump_data = redis.dump(key)

    if dump_data.nil?
      stats[:skipped] += 1
      return
    end

    record = {
      key: key,
      type: key_type,
      ttl_ms: ttl_ms,
      dump: Base64.strict_encode64(dump_data),
    }

    if key_type == 'hash'
      created_value    = redis.hget(key, 'created')
      record[:created] = created_value if created_value
    end

    file.puts(JSON.generate(record))
    stats[:dumped] += 1
  rescue Redis::CommandError => ex
    stats[:errors] << { key: key, error: ex.message }
  end

  def write_manifest(model_name, db_number, output_file, stats)
    manifest_file = output_file.sub('.jsonl', '_manifest.json')

    manifest = {
      model: model_name,
      source_db: db_number,
      source_url: @redis_url.sub(/:[^:@]*@/, ':***@'),
      output_file: File.basename(output_file),
      timestamp: @timestamp,
      stats: {
        total_scanned: stats[:total],
        dumped: stats[:dumped],
        skipped: stats[:skipped],
        errors: stats[:errors].size,
      },
      errors: stats[:errors].first(10),
    }

    File.write(manifest_file, JSON.pretty_generate(manifest))
  end
end

def parse_args(args)
  options = {
    redis_url: 'redis://127.0.0.1:6379',
    output_dir: 'exports',
    dry_run: false,
    model: nil,
    all: false,
  }

  args.each do |arg|
    case arg
    when /^--model=(.+)$/
      options[:model] = Regexp.last_match(1)
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
        Usage: ruby scripts/dump_keys.rb [OPTIONS]

        Options:
          --model=NAME     Model to dump (#{KeyDumper::VALID_MODELS.join(', ')})
          --all            Dump all models
          --redis-url=URL  Redis URL (default: redis://127.0.0.1:6379)
          --output-dir=DIR Output directory (default: exports)
          --dry-run        Show what would be dumped
          --help           Show this help

        Model-to-DB mapping:
          customer     => DB 6
          customdomain => DB 6
          metadata     => DB 7
          secret       => DB 8
          feedback     => DB 11
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  unless options[:model] || options[:all]
    puts 'Error: Must specify --model=NAME or --all'
    puts 'Use --help for usage'
    exit 1
  end

  dumper = KeyDumper.new(
    redis_url: options[:redis_url],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  if options[:all]
    dumper.dump_all_models
  else
    dumper.dump_model(options[:model])
  end
end
