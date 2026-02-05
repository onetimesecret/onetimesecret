#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates index records for Secret model from dump file.
# Reads JSONL dump and outputs Redis commands for index creation.
#
# Usage:
#   ruby scripts/migrations/jan24/create_indexes_secret.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input dump file (default: data/upgrades/v0.24.0/secret/secret_dump.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/secret)
#   --dry-run           Show what would be created without writing
#
# Output: data/upgrades/v0.24.0/secret/secret_indexes.jsonl
#
# Indexes created:
#   - secret:instances (sorted set): score=created, member=objid
#   - secret:objid_lookup (hash): objid -> "objid" (JSON quoted)

require 'json'
require 'base64'
require 'fileutils'

# Calculate project root from script location
PROJECT_ROOT     = File.expand_path('../../../..', __dir__)
DEFAULT_DATA_DIR = File.join(PROJECT_ROOT, 'data/upgrades/v0.24.0')

class SecretIndexCreator
  # Pattern to extract objid from key: secret:<objid>:object
  KEY_PATTERN = /\Asecret:([^:]+):object\z/

  def initialize(input_file:, output_dir:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @dry_run    = dry_run
    @stats      = {
      records_read: 0,
      records_processed: 0,
      records_skipped: 0,
      email_keys_skipped: 0,
      missing_created: 0,
      missing_objid: 0,
      errors: [],
    }
  end

  def run
    unless File.exist?(@input_file)
      puts "Error: Input file not found: #{@input_file}"
      exit 1
    end

    if @dry_run
      puts "DRY RUN: Would process #{@input_file}"
      analyze_input
      print_stats
      return @stats
    end

    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'secret_indexes.jsonl')

    File.open(output_file, 'w') do |out|
      process_dump(out)
    end

    print_stats
    puts "\nOutput written to #{output_file}"
    @stats
  end

  private

  def analyze_input
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line.chomp)

      # Only process :object keys (skip :email suffix keys)
      unless record['key']&.end_with?(':object')
        @stats[:email_keys_skipped] += 1 if record['key']&.end_with?(':email')
        next
      end

      objid   = extract_objid(record['key'])
      created = record['created']

      if objid.nil?
        @stats[:missing_objid] += 1
        next
      end

      if created.nil? || created.to_i <= 0
        @stats[:missing_created] += 1
      end

      @stats[:records_processed] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: ex.message }
    end

    @stats[:records_skipped] = @stats[:records_read] - @stats[:records_processed]
  end

  def process_dump(out)
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line.chomp)

      # Only process :object keys (skip :email suffix keys)
      unless record['key']&.end_with?(':object')
        @stats[:email_keys_skipped] += 1 if record['key']&.end_with?(':email')
        @stats[:records_skipped]    += 1
        next
      end

      objid = extract_objid(record['key'])
      if objid.nil?
        @stats[:missing_objid]   += 1
        @stats[:records_skipped] += 1
        next
      end

      created = record['created']
      if created.nil? || created.to_i <= 0
        @stats[:missing_created] += 1
        # Use 0 as fallback for missing created timestamp
        created                   = 0
      end

      # Write instance index command (sorted set)
      # ZADD secret:instances <created> <objid>
      out.puts JSON.generate(
        {
          command: 'ZADD',
          key: 'secret:instances',
          args: [created.to_i, objid],
        },
      )

      # Write objid lookup command (hash)
      # HSET secret:objid_lookup <objid> "<objid>" (JSON quoted)
      out.puts JSON.generate(
        {
          command: 'HSET',
          key: 'secret:objid_lookup',
          args: [objid, JSON.generate(objid)],
        },
      )

      @stats[:records_processed] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: ex.message }
      @stats[:records_skipped] += 1
    end
  end

  def extract_objid(key)
    match = KEY_PATTERN.match(key)
    match ? match[1] : nil
  end

  def print_stats
    puts "\nSecret Index Creation Summary"
    puts '=' * 40
    puts "Records read:      #{@stats[:records_read]}"
    puts "Records processed: #{@stats[:records_processed]}"
    puts "Records skipped:   #{@stats[:records_skipped]} (#{@stats[:email_keys_skipped]} :email suffix keys)"
    puts "Missing created:   #{@stats[:missing_created]}" if @stats[:missing_created] > 0
    puts "Missing objid:     #{@stats[:missing_objid]}" if @stats[:missing_objid] > 0
    puts "Errors:            #{@stats[:errors].size}" if @stats[:errors].any?

    if @stats[:errors].any?
      puts "\nFirst 5 errors:"
      @stats[:errors].first(5).each do |err|
        puts "  Line #{err[:line]}: #{err[:error]}"
      end
    end

    puts "\nIndexes created:"
    puts "  - secret:instances (sorted set): #{@stats[:records_processed]} members"
    puts "  - secret:objid_lookup (hash): #{@stats[:records_processed]} entries"
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'secret/secret_dump.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'secret'),
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /\A--input-file=(.+)\z/
      options[:input_file] = Regexp.last_match(1)
    when /\A--output-dir=(.+)\z/
      options[:output_dir] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/create_indexes_secret.rb [OPTIONS]

        Creates index records for Secret model from dump file.

        Options:
          --input-file=FILE   Input dump file (default: data/upgrades/v0.24.0/secret/secret_dump.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/secret)
          --dry-run           Show what would be created without writing
          --help              Show this help

        Output: <output-dir>/secret_indexes.jsonl

        Indexes created:
          - secret:instances (sorted set): score=created, member=objid
          - secret:objid_lookup (hash): objid -> "objid" (JSON quoted)
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  creator = SecretIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  creator.run
end
