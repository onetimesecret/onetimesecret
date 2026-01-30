#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Redis Load (Phase 6)
#
# Loads transformed data into Redis/Valkey from JSONL files.
# This replaces the standalone load_keys.rb script with Kiba-based loading.
#
# Input files per model:
#   - {model}_transformed.jsonl: Records to RESTORE (with dump blobs)
#   - {model}_indexes.jsonl: Redis commands to execute (ZADD, HSET, SADD, INCRBY)
#
# Models are loaded in dependency order:
#   customer -> organization -> customdomain -> receipt -> secret
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/06_load.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR      Input directory with JSONL files (default: results)
#   --valkey-url=URL     Valkey/Redis URL (default: redis://127.0.0.1:6379)
#   --model=NAME         Load only specific model
#   --dry-run            Count records without loading
#   --skip-indexes       Load only transformed records (skip index commands)
#   --skip-records       Load only indexes (skip RESTORE operations)

require 'fileutils'
require 'json'
require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class LoadJob
  PHASE = 6
  JOB_NAME = 'Redis Load'

  # Models in dependency order - all load to DB 0 (Familia v2 consolidation)
  MODELS = {
    'customer' => { db: 0 },
    'organization' => { db: 0 },
    'customdomain' => { db: 0 },
    'receipt' => { db: 0 },
    'secret' => { db: 0 },
  }.freeze

  def initialize(options)
    @input_dir = options[:input_dir]
    @valkey_url = options[:valkey_url]
    @target_model = options[:model]
    @dry_run = options[:dry_run]
    @skip_indexes = options[:skip_indexes]
    @skip_records = options[:skip_records]

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
    validate_options!

    puts "#{JOB_NAME} (Phase #{PHASE})"
    puts '=' * 50
    puts "Input:  #{@input_dir}"
    puts "Target: #{@valkey_url}"
    puts "Mode:   #{mode_description}"
    puts

    models_to_load.each do |model_name, config|
      load_model(model_name, config)
    end

    print_summary
    exit_with_status
  end

  private

  def validate_options!
    unless Dir.exist?(@input_dir)
      raise ArgumentError, "Input directory not found: #{@input_dir}"
    end

    if @target_model && !MODELS.key?(@target_model)
      raise ArgumentError, "Unknown model: #{@target_model}. Valid: #{MODELS.keys.join(', ')}"
    end

    if @skip_indexes && @skip_records
      raise ArgumentError, 'Cannot specify both --skip-indexes and --skip-records'
    end
  end

  def models_to_load
    if @target_model
      { @target_model => MODELS[@target_model] }
    else
      MODELS
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

  def load_model(model_name, config)
    puts "-" * 50
    puts "Loading: #{model_name} (DB #{config[:db]})"
    puts "-" * 50

    stats = @stats[model_name]

    # Load transformed records (RESTORE)
    unless @skip_records
      transformed_file = File.join(@input_dir, "#{model_name}_transformed.jsonl")
      if File.exist?(transformed_file)
        load_transformed_records(model_name, config, transformed_file, stats)
      else
        puts "  No transformed file: #{File.basename(transformed_file)}"
      end
    end

    # Execute index commands
    unless @skip_indexes
      indexes_file = File.join(@input_dir, "#{model_name}_indexes.jsonl")
      if File.exist?(indexes_file)
        execute_index_commands(model_name, config, indexes_file, stats)
      else
        puts "  No indexes file: #{File.basename(indexes_file)}"
      end
    end

    puts
  end

  def load_transformed_records(model_name, config, file_path, stats)
    puts "  Loading records from #{File.basename(file_path)}..."

    valkey_url = @valkey_url
    db = config[:db]
    dry_run = @dry_run

    # Create shared stats hash for the destination
    dest_stats = { restored: 0, skipped: 0, errors: [] }

    job = Kiba.parse do
      source Migration::Sources::JsonlSource,
             file: file_path

      destination Migration::Destinations::RedisDestination,
                  valkey_url: valkey_url,
                  db: db,
                  dry_run: dry_run,
                  stats: dest_stats
    end

    Kiba.run(job)

    # Copy stats back
    stats[:records_restored] = dest_stats[:restored]
    stats[:records_skipped] = dest_stats[:skipped]
    stats[:errors].concat(dest_stats[:errors])

    puts "    Records restored: #{stats[:records_restored]}"
    puts "    Records skipped:  #{stats[:records_skipped]}" if stats[:records_skipped] > 0
  end

  def execute_index_commands(model_name, config, file_path, stats)
    puts "  Executing indexes from #{File.basename(file_path)}..."

    valkey_url = @valkey_url
    db = config[:db]
    dry_run = @dry_run

    # Create shared stats hash for the destination
    dest_stats = { executed: 0, skipped: 0, errors: [] }

    job = Kiba.parse do
      source Migration::Sources::JsonlSource,
             file: file_path

      destination Migration::Destinations::RedisIndexDestination,
                  valkey_url: valkey_url,
                  db: db,
                  dry_run: dry_run,
                  stats: dest_stats
    end

    Kiba.run(job)

    # Copy stats back
    stats[:indexes_executed] = dest_stats[:executed]
    stats[:indexes_skipped] = dest_stats[:skipped]
    stats[:errors].concat(dest_stats[:errors])

    puts "    Index commands: #{stats[:indexes_executed]}"
    puts "    Index skipped:  #{stats[:indexes_skipped]}" if stats[:indexes_skipped] > 0
  end

  def print_summary
    puts
    puts '=' * 50
    puts "#{JOB_NAME} Summary"
    puts '=' * 50

    total_records = 0
    total_indexes = 0
    total_errors = 0

    @stats.each do |model_name, stats|
      puts "#{model_name}:"
      puts "  Records restored: #{stats[:records_restored]}"
      puts "  Records skipped:  #{stats[:records_skipped]}" if stats[:records_skipped] > 0
      puts "  Index commands:   #{stats[:indexes_executed]}"
      puts "  Index skipped:    #{stats[:indexes_skipped]}" if stats[:indexes_skipped] > 0
      puts "  Errors:           #{stats[:errors].size}" if stats[:errors].any?
      puts

      total_records += stats[:records_restored]
      total_indexes += stats[:indexes_executed]
      total_errors += stats[:errors].size
    end

    puts '-' * 50
    puts "Total records restored: #{total_records}"
    puts "Total index commands:   #{total_indexes}"
    puts "Total errors:           #{total_errors}" if total_errors > 0

    return unless total_errors > 0

    puts
    puts 'Errors (first 20):'
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
  require 'optparse'

  migration_dir = File.expand_path('..', __dir__)
  results_dir = File.join(migration_dir, 'results')

  options = {
    input_dir: results_dir,
    valkey_url: 'redis://127.0.0.1:6379',
    model: nil,
    dry_run: false,
    skip_indexes: false,
    skip_records: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/06_load.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL job for loading data into Redis/Valkey (Phase 6).'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--input-dir=DIR', 'Input directory with JSONL files') do |dir|
      options[:input_dir] = File.expand_path(dir, migration_dir)
    end

    opts.on('--valkey-url=URL', 'Valkey/Redis URL (default: redis://127.0.0.1:6379)') do |url|
      options[:valkey_url] = url
    end

    opts.on('--model=NAME', 'Load specific model') do |model|
      options[:model] = model
    end

    opts.on('--dry-run', 'Count records without loading') do
      options[:dry_run] = true
    end

    opts.on('--skip-indexes', 'Load only transformed records') do
      options[:skip_indexes] = true
    end

    opts.on('--skip-records', 'Load only indexes') do
      options[:skip_records] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Models (loaded in dependency order to DB 0):'
      puts '  customer, organization, customdomain, receipt, secret'
      puts
      puts 'Input files:'
      puts '  {model}_transformed.jsonl   Records to RESTORE'
      puts '  {model}_indexes.jsonl       Redis commands (ZADD, HSET, etc.)'
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
  LoadJob.new(options).run
end
