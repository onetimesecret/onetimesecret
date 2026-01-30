#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Redis Dump (Phase 0)
#
# Extracts data from Redis databases and writes to JSONL dump files.
# This replaces the standalone dump_keys.rb script with Kiba-based extraction.
#
# Output: results/{model}_dump.jsonl for each model (customer, customdomain, metadata, secret)
#
# Each record contains:
#   - key: Redis key name
#   - type: Redis data type
#   - ttl_ms: TTL in milliseconds (-1 = no expiry)
#   - db: Source database number
#   - dump: Base64-encoded DUMP data
#   - created: Timestamp for UUIDv7 generation (hash objects only)
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/00_dump.rb [OPTIONS]
#
# Options:
#   --output-dir=DIR   Output directory (default: results)
#   --redis-url=URL    Redis URL (default: redis://127.0.0.1:6379)
#   --model=NAME       Dump only specific model (customer, customdomain, metadata, secret)
#   --dry-run          Count keys without writing

require 'fileutils'
require 'json'
require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class DumpJob
  PHASE = 0
  JOB_NAME = 'Redis Dump'

  # Models to dump with their source databases and key prefixes
  MODELS = {
    'customer' => { db: 6, prefix: 'customer' },
    'customdomain' => { db: 6, prefix: 'customdomain' },
    'metadata' => { db: 7, prefix: 'metadata' },
    'secret' => { db: 8, prefix: 'secret' },
  }.freeze

  def initialize(options)
    @output_dir = options[:output_dir]
    @redis_url = options[:redis_url]
    @dry_run = options[:dry_run]
    @target_model = options[:model]
    @timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    @stats = Hash.new do |h, k|
      h[k] = { records_read: 0, records_written: 0, errors: [] }
    end
  end

  def run
    puts "#{JOB_NAME} (Phase #{PHASE})"
    puts '=' * 50
    puts "Output: #{@output_dir}"
    puts "Redis:  #{@redis_url}"
    puts "Mode:   #{@dry_run ? 'DRY RUN' : 'LIVE'}"
    puts

    models_to_dump.each do |model_name, config|
      dump_model(model_name, config)
    end

    write_manifest unless @dry_run
    print_summary
  end

  private

  def models_to_dump
    if @target_model
      unless MODELS.key?(@target_model)
        raise ArgumentError, "Unknown model: #{@target_model}. Valid: #{MODELS.keys.join(', ')}"
      end

      { @target_model => MODELS[@target_model] }
    else
      MODELS
    end
  end

  def dump_model(model_name, config)
    puts "-" * 50
    puts "Dumping: #{model_name} (DB #{config[:db]})"
    puts "-" * 50

    output_file = File.join(@output_dir, "#{model_name}_dump.jsonl")
    stats = @stats[model_name]

    if @dry_run
      run_dry_count(model_name, config, stats)
    else
      run_kiba_dump(model_name, config, output_file, stats)
    end

    puts "  Records: #{stats[:records_written]}"
    puts
  end

  def run_dry_count(model_name, config, stats)
    # Simple count without Kiba for dry run
    source = Migration::Sources::RedisSource.new(
      redis_url: @redis_url,
      db: config[:db],
      model: config[:prefix],
      dry_run: true
    )

    source.each do |_record|
      stats[:records_read] += 1
      stats[:records_written] += 1
    end
  end

  def run_kiba_dump(model_name, config, output_file, stats)
    FileUtils.mkdir_p(File.dirname(output_file))

    redis_url = @redis_url
    db = config[:db]
    prefix = config[:prefix]

    job = Kiba.parse do
      source Migration::Sources::RedisSource,
             redis_url: redis_url,
             db: db,
             model: prefix

      # Count records
      transform do |record|
        stats[:records_read] += 1
        record
      end

      # Track written records
      transform do |record|
        stats[:records_written] += 1
        record
      end

      destination Migration::Destinations::JsonlDestination,
                  file: output_file
    end

    Kiba.run(job)
  end

  def write_manifest
    manifest_file = File.join(@output_dir, "dump_manifest_#{@timestamp}.json")

    model_summaries = {}
    @stats.each do |model, stats|
      model_summaries[model] = {
        file: "#{model}_dump.jsonl",
        records_read: stats[:records_read],
        records_written: stats[:records_written],
        errors: stats[:errors].size,
      }
    end

    manifest = {
      source_url: @redis_url.sub(/:[^:@]*@/, ':***@'), # Redact password
      timestamp: @timestamp,
      models: model_summaries,
      errors: @stats.flat_map { |_, s| s[:errors] }.first(20),
    }

    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "Manifest: #{manifest_file}"
  end

  def print_summary
    puts
    puts '=' * 50
    puts "#{JOB_NAME} Summary"
    puts '=' * 50

    total_records = 0
    total_errors = 0

    @stats.each do |model_name, stats|
      puts "#{model_name}:"
      puts "  Records written: #{stats[:records_written]}"
      puts "  Errors:          #{stats[:errors].size}" if stats[:errors].any?
      puts

      total_records += stats[:records_written]
      total_errors += stats[:errors].size
    end

    puts '-' * 50
    puts "Total records: #{total_records}"
    puts "Total errors:  #{total_errors}" if total_errors > 0
  end
end

def parse_args(args)
  require 'optparse'

  migration_dir = File.expand_path('..', __dir__)
  results_dir = File.join(migration_dir, 'results')

  options = {
    output_dir: results_dir,
    redis_url: 'redis://127.0.0.1:6379',
    model: nil,
    dry_run: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/00_dump.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL job for extracting data from Redis (Phase 0).'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--output-dir=DIR', 'Output directory') do |dir|
      options[:output_dir] = File.expand_path(dir, migration_dir)
    end

    opts.on('--redis-url=URL', 'Redis URL (default: redis://127.0.0.1:6379)') do |url|
      options[:redis_url] = url
    end

    opts.on('--model=NAME', 'Dump specific model (customer, customdomain, metadata, secret)') do |model|
      options[:model] = model
    end

    opts.on('--dry-run', 'Count keys without writing') do
      options[:dry_run] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Output files:'
      puts '  results/customer_dump.jsonl'
      puts '  results/customdomain_dump.jsonl'
      puts '  results/metadata_dump.jsonl'
      puts '  results/secret_dump.jsonl'
      puts '  results/dump_manifest_<timestamp>.json'
      exit 0
    end
  end

  parser.parse!(args)
  options
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  warn e.message
  warn 'Use --help for usage information'
  exit 1
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)
  DumpJob.new(options).run
end
