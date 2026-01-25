#!/usr/bin/env ruby
# frozen_string_literal: true

# Dumps Redis keys to JSONL format for migration.
# Each line: {"key": "...", "type": "...", "ttl_ms": ..., "dump": "<base64>"}
#
# Usage:
#   ruby scripts/dump_keys.rb [OPTIONS]
#
# Options:
#   --db=N           Database number to dump (required, or use --all)
#   --all            Dump all migration databases (6, 7, 8, 11)
#   --redis-url=URL  Redis URL (default: redis://127.0.0.1:6379)
#   --output-dir=DIR Output directory (default: exports)
#   --dry-run        Show what would be dumped without writing
#
# Output files are timestamped: db6_keys_20260124T120000Z.jsonl
# Idempotent: each run creates new files, never modifies existing.

require 'redis'
require 'json'
require 'base64'
require 'fileutils'

class KeyDumper
  MIGRATION_DBS = [6, 7, 8, 11].freeze

  def initialize(redis_url:, output_dir:, dry_run: false)
    @redis_url  = redis_url
    @output_dir = output_dir
    @dry_run    = dry_run
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  end

  def dump_database(db_number)
    redis       = Redis.new(url: "#{@redis_url}/#{db_number}")
    output_file = File.join(@output_dir, "db#{db_number}_keys_#{@timestamp}.jsonl")

    stats = { total: 0, dumped: 0, skipped: 0, errors: [] }

    if @dry_run
      puts "DRY RUN: Would dump DB #{db_number} to #{output_file}"
      count_keys(redis, stats)
      return stats
    end

    FileUtils.mkdir_p(@output_dir)

    File.open(output_file, 'w') do |f|
      scan_and_dump(redis, f, stats)
    end

    # Write manifest for this dump
    write_manifest(db_number, output_file, stats)

    puts "DB #{db_number}: #{stats[:dumped]} keys dumped to #{output_file}"
    puts "  Skipped: #{stats[:skipped]}, Errors: #{stats[:errors].size}"

    stats
  end

  def dump_all
    results = {}
    MIGRATION_DBS.each do |db|
      results[db] = dump_database(db)
    end
    results
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

  def scan_and_dump(redis, file, stats)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, count: 1000)

      keys.each do |key|
        stats[:total] += 1
        dump_key(redis, file, key, stats)
      end

      break if cursor == '0'
    end
  end

  def dump_key(redis, file, key, stats)
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
      dump: Base64.strict_encode64(dump_data),
    }

    file.puts(JSON.generate(record))
    stats[:dumped] += 1
  rescue Redis::CommandError => ex
    stats[:errors] << { key: key, error: ex.message }
  end

  def write_manifest(db_number, output_file, stats)
    manifest_file = output_file.sub('.jsonl', '_manifest.json')

    manifest = {
      source_db: db_number,
      source_url: @redis_url.sub(/:[^:@]*@/, ':***@'), # Redact password
      output_file: File.basename(output_file),
      timestamp: @timestamp,
      stats: {
        total_scanned: stats[:total],
        dumped: stats[:dumped],
        skipped: stats[:skipped],
        errors: stats[:errors].size,
      },
      errors: stats[:errors].first(10), # First 10 errors only
    }

    File.write(manifest_file, JSON.pretty_generate(manifest))
  end
end

def parse_args(args)
  options = {
    redis_url: 'redis://127.0.0.1:6379',
    output_dir: 'exports',
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
        Usage: ruby scripts/dump_keys.rb [OPTIONS]

        Options:
          --db=N           Database number to dump
          --all            Dump migration databases (6, 7, 8, 11)
          --redis-url=URL  Redis URL (default: redis://127.0.0.1:6379)
          --output-dir=DIR Output directory (default: exports)
          --dry-run        Show what would be dumped
          --help           Show this help
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
