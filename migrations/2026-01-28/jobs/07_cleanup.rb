#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Cleanup (Phase 7)
#
# Removes all migration artifacts to enable a pristine restart.
# Cleans both Redis data (DB 0) and generated files.
#
# Redis cleanup:
#   - Deletes all keys for migrated models in DB 0
#   - Models: customer, organization, customdomain, receipt, secret
#
# File cleanup:
#   - results/*_transformed.jsonl
#   - results/*_indexes.jsonl
#   - results/*_dump.jsonl
#   - results/lookups/*.json
#   - results/*_manifest_*.json
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/07_cleanup.rb [OPTIONS]
#
# Options:
#   --results-dir=DIR    Results directory (default: results)
#   --valkey-url=URL     Valkey/Redis URL (default: redis://127.0.0.1:6379)
#   --redis-only         Clean only Redis data (skip files)
#   --files-only         Clean only files (skip Redis)
#   --dry-run            Show what would be deleted without deleting

require 'fileutils'
require 'json'
require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

module Migration
  module Sources
    # Kiba source that scans Redis keys for cleanup.
    #
    # Yields keys matching model prefixes in the target database.
    #
    class RedisCleanupSource
      SCAN_BATCH_SIZE = 1000

      attr_reader :valkey_url, :db, :prefixes

      def initialize(valkey_url:, db:, prefixes:)
        @valkey_url = valkey_url
        @db = db
        @prefixes = prefixes
        @redis = nil
      end

      def each
        connect!

        @prefixes.each do |prefix|
          scan_prefix(prefix) { |key| yield({ key: key, prefix: prefix }) }
        end
      ensure
        disconnect!
      end

      private

      def connect!
        base_url = @valkey_url.sub(%r{/\d+$}, '')
        @redis = Redis.new(url: "#{base_url}/#{@db}")
        @redis.ping
      rescue Redis::CannotConnectError => ex
        raise ArgumentError, "Failed to connect to Redis (DB #{@db}): #{ex.message}"
      end

      def disconnect!
        @redis&.close
        @redis = nil
      end

      def scan_prefix(prefix)
        cursor = '0'
        loop do
          cursor, keys = @redis.scan(cursor, match: "#{prefix}:*", count: SCAN_BATCH_SIZE)
          keys.each { |key| yield key }
          break if cursor == '0'
        end
      end
    end
  end

  module Destinations
    # Kiba destination that deletes Redis keys.
    #
    class RedisDeleteDestination
      attr_reader :valkey_url, :db, :dry_run, :stats

      def initialize(valkey_url:, db:, dry_run: false, stats: nil)
        @valkey_url = valkey_url
        @db = db
        @dry_run = dry_run
        @stats = stats || { deleted: 0, errors: [] }
        @redis = nil
        @batch = []
        @batch_size = 100
      end

      def write(record)
        return if record.nil?

        key = record[:key]
        return unless key

        if @dry_run
          @stats[:deleted] += 1
          return
        end

        @batch << key
        flush_batch if @batch.size >= @batch_size
      end

      def close
        flush_batch unless @batch.empty?
        @redis&.close
        @redis = nil
      end

      private

      def connect!
        base_url = @valkey_url.sub(%r{/\d+$}, '')
        @redis = Redis.new(url: "#{base_url}/#{@db}")
        @redis.ping
      rescue Redis::CannotConnectError => ex
        raise ArgumentError, "Failed to connect to Redis (DB #{@db}): #{ex.message}"
      end

      def flush_batch
        return if @batch.empty?

        connect! unless @redis

        deleted = @redis.del(*@batch)
        @stats[:deleted] += deleted
        @batch.clear
      rescue Redis::CommandError => ex
        @stats[:errors] << { batch_size: @batch.size, error: ex.message }
        @batch.clear
      end
    end
  end
end

class CleanupJob
  PHASE = 7
  JOB_NAME = 'Migration Cleanup'

  # Model prefixes to delete from DB 0
  MODEL_PREFIXES = %w[
    customer
    organization
    customdomain
    receipt
    secret
  ].freeze

  # File patterns to delete (relative to results_dir)
  FILE_PATTERNS = [
    '*_transformed.jsonl',
    '*_indexes.jsonl',
    '*_dump.jsonl',
    'lookups/*.json',
    '*_manifest_*.json',
  ].freeze

  def initialize(options)
    @results_dir = options[:results_dir]
    @valkey_url = options[:valkey_url]
    @dry_run = options[:dry_run]
    @redis_only = options[:redis_only]
    @files_only = options[:files_only]

    @stats = {
      redis_keys_deleted: 0,
      redis_errors: [],
      files_deleted: 0,
      file_errors: [],
    }
  end

  def run
    puts "#{JOB_NAME} (Phase #{PHASE})"
    puts '=' * 50
    puts "Results: #{@results_dir}"
    puts "Target:  #{@valkey_url}"
    puts "Mode:    #{mode_description}"
    puts

    clean_redis unless @files_only
    clean_files unless @redis_only

    print_summary
  end

  private

  def mode_description
    parts = []
    parts << 'dry-run' if @dry_run
    parts << 'redis only' if @redis_only
    parts << 'files only' if @files_only
    parts << 'full cleanup' if parts.empty?
    parts.join(', ')
  end

  def clean_redis
    puts '-' * 50
    puts 'Cleaning Redis (DB 0)'
    puts '-' * 50

    valkey_url = @valkey_url
    dry_run = @dry_run
    dest_stats = { deleted: 0, errors: [] }

    job = Kiba.parse do
      source Migration::Sources::RedisCleanupSource,
             valkey_url: valkey_url,
             db: 0,
             prefixes: MODEL_PREFIXES

      destination Migration::Destinations::RedisDeleteDestination,
                  valkey_url: valkey_url,
                  db: 0,
                  dry_run: dry_run,
                  stats: dest_stats
    end

    Kiba.run(job)

    @stats[:redis_keys_deleted] = dest_stats[:deleted]
    @stats[:redis_errors] = dest_stats[:errors]

    puts "  Keys #{@dry_run ? 'would be ' : ''}deleted: #{@stats[:redis_keys_deleted]}"
    puts
  end

  def clean_files
    puts '-' * 50
    puts "Cleaning files in #{@results_dir}"
    puts '-' * 50

    return unless Dir.exist?(@results_dir)

    FILE_PATTERNS.each do |pattern|
      Dir.glob(File.join(@results_dir, pattern)).each do |file|
        delete_file(file)
      end
    end

    # Clean empty lookups directory
    lookups_dir = File.join(@results_dir, 'lookups')
    if Dir.exist?(lookups_dir) && Dir.empty?(lookups_dir)
      delete_directory(lookups_dir)
    end

    puts "  Files #{@dry_run ? 'would be ' : ''}deleted: #{@stats[:files_deleted]}"
    puts
  end

  def delete_file(file)
    if @dry_run
      puts "    [dry-run] Would delete: #{File.basename(file)}"
      @stats[:files_deleted] += 1
      return
    end

    File.delete(file)
    @stats[:files_deleted] += 1
  rescue SystemCallError => ex
    @stats[:file_errors] << { file: file, error: ex.message }
  end

  def delete_directory(dir)
    if @dry_run
      puts "    [dry-run] Would remove: #{File.basename(dir)}/"
      return
    end

    Dir.rmdir(dir)
  rescue SystemCallError => ex
    @stats[:file_errors] << { dir: dir, error: ex.message }
  end

  def print_summary
    puts
    puts '=' * 50
    puts "#{JOB_NAME} Summary"
    puts '=' * 50

    unless @files_only
      puts "Redis keys deleted: #{@stats[:redis_keys_deleted]}"
      if @stats[:redis_errors].any?
        puts "Redis errors:       #{@stats[:redis_errors].size}"
      end
    end

    unless @redis_only
      puts "Files deleted:      #{@stats[:files_deleted]}"
      if @stats[:file_errors].any?
        puts "File errors:        #{@stats[:file_errors].size}"
      end
    end

    total_errors = @stats[:redis_errors].size + @stats[:file_errors].size
    return unless total_errors > 0

    puts
    puts 'Errors:'
    (@stats[:redis_errors] + @stats[:file_errors]).first(10).each do |err|
      puts "  #{err}"
    end
  end
end

def parse_args(args)
  require 'optparse'

  migration_dir = File.expand_path('..', __dir__)
  results_dir = File.join(migration_dir, 'results')

  options = {
    results_dir: results_dir,
    valkey_url: 'redis://127.0.0.1:6379',
    dry_run: false,
    redis_only: false,
    files_only: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/07_cleanup.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Cleanup job for resetting migration state (Phase 7).'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--results-dir=DIR', 'Results directory') do |dir|
      options[:results_dir] = File.expand_path(dir, migration_dir)
    end

    opts.on('--valkey-url=URL', 'Valkey/Redis URL (default: redis://127.0.0.1:6379)') do |url|
      options[:valkey_url] = url
    end

    opts.on('--redis-only', 'Clean only Redis data (skip files)') do
      options[:redis_only] = true
    end

    opts.on('--files-only', 'Clean only files (skip Redis)') do
      options[:files_only] = true
    end

    opts.on('--dry-run', 'Show what would be deleted without deleting') do
      options[:dry_run] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Redis cleanup (DB 0):'
      puts '  Deletes keys: customer:*, organization:*, custom_domain:*,'
      puts '                receipt:*, secret:*'
      puts
      puts 'File cleanup:'
      puts '  results/*_transformed.jsonl'
      puts '  results/*_indexes.jsonl'
      puts '  results/*_dump.jsonl'
      puts '  results/lookups/*.json'
      puts '  results/*_manifest_*.json'
      exit 0
    end
  end

  parser.parse!(args)

  if options[:redis_only] && options[:files_only]
    warn 'Cannot specify both --redis-only and --files-only'
    exit 1
  end

  options
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  warn e.message
  warn 'Use --help for usage information'
  exit 1
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)
  CleanupJob.new(options).run
end
