#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Customer Transform (Phase 1)
#
# Transforms customer data from V1 dump format to V2 format.
# This is a proof-of-concept spike to validate the Kiba architecture.
#
# Input:  ../exports/customer/customer_dump.jsonl (enriched with identifiers)
# Output: exports/customer/customer_transformed.jsonl
#         exports/lookups/email_to_customer_objid.json
#
# Usage:
#   cd migrations/2026-01-26/kiba
#   bundle exec ruby jobs/01_customer.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: ../exports/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports)
#   --redis-url=URL     Redis URL (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database (default: 15)
#   --dry-run           Parse and count without writing

require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class CustomerJob
  PHASE = 1
  MODEL = 'customer'

  def initialize(options)
    @input_file = options[:input_file]
    @output_dir = options[:output_dir]
    @redis_url = options[:redis_url]
    @temp_db = options[:temp_db]
    @dry_run = options[:dry_run]

    @stats = {
      records_read: 0,
      objects_found: 0,
      objects_transformed: 0,
      records_written: 0,
      lookup_entries: 0,
      errors: [],
    }
  end

  def run
    validate_input!

    puts "Customer Transform Job (Phase #{PHASE})"
    puts "=" * 50
    puts "Input:  #{@input_file}"
    puts "Output: #{output_file}"
    puts "Lookup: #{lookup_file}"
    puts "Mode:   #{@dry_run ? 'DRY RUN' : 'LIVE'}"
    puts

    if @dry_run
      run_dry
    else
      run_live
    end

    print_summary
  end

  private

  def validate_input!
    unless File.exist?(@input_file)
      raise ArgumentError, "Input file not found: #{@input_file}"
    end
  end

  def output_file
    File.join(@output_dir, MODEL, "#{MODEL}_transformed.jsonl")
  end

  def lookup_file
    File.join(@output_dir, 'lookups', 'email_to_customer_objid.json')
  end

  def run_dry
    # Simple pass to count records
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record = JSON.parse(line, symbolize_names: true)

      if record[:key]&.end_with?(':object')
        @stats[:objects_found] += 1
        @stats[:objects_transformed] += 1 if record[:objid]
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: ex.message }
    end
  end

  def run_live
    redis_helper = Migration::Shared::RedisTempKey.new(
      redis_url: @redis_url,
      temp_db: @temp_db
    )
    redis_helper.connect!

    registry = Migration::Shared::LookupRegistry.new(exports_dir: @output_dir)

    # Build and run Kiba job
    job = build_kiba_job(redis_helper, registry)
    Kiba.run(job)

    # Save lookup data
    save_lookups(registry)

    # Stats are tracked via the stats hash passed to transforms
    # records_written is tracked by a post-transform counter
  ensure
    redis_helper&.cleanup!
    redis_helper&.disconnect!
  end

  def build_kiba_job(redis_helper, registry)
    input_file = @input_file
    output_file_path = output_file
    lookup_file_path = lookup_file
    stats = @stats
    job_started_at = Time.now

    Kiba.parse do
      # Pre-process: setup
      pre_process do
        FileUtils.mkdir_p(File.dirname(output_file_path))
        FileUtils.mkdir_p(File.dirname(lookup_file_path))
      end

      # Source: read JSONL
      source Migration::Sources::JsonlSource,
             file: input_file,
             key_pattern: /^customer:/

      # Transform: count records
      transform do |record|
        stats[:records_read] += 1
        record
      end

      # Transform: decode Redis DUMP
      transform Migration::Transforms::RedisDumpDecoder,
                redis_helper: redis_helper,
                stats: stats

      # Transform: enrich with identifiers (if not already present)
      transform Migration::Transforms::Customer::IdentifierEnricher,
                stats: stats

      # Transform: filter to :object records for main transform
      # (pass through others for related record handling)
      transform do |record|
        if record[:key]&.end_with?(':object')
          stats[:objects_found] += 1
        end
        record
      end

      # Transform: apply field transformations
      transform Migration::Transforms::Customer::FieldTransformer,
                registry: registry,
                stats: stats,
                migrated_at: job_started_at

      # Transform: encode fields back to DUMP
      transform Migration::Transforms::RedisDumpEncoder,
                redis_helper: redis_helper,
                fields_key: :v2_fields,
                stats: stats

      # Transform: count records being written
      transform do |record|
        stats[:records_written] += 1
        record
      end

      # Destination: write transformed JSONL
      destination Migration::Destinations::JsonlDestination,
                  file: output_file_path,
                  exclude_fields: %i[fields v2_fields decode_error encode_error]
    end
  end

  def save_lookups(registry)
    data = registry.collected(:email_to_customer)
    return if data.empty?

    FileUtils.mkdir_p(File.dirname(lookup_file))
    File.write(lookup_file, JSON.pretty_generate(data))
    @stats[:lookup_entries] = data.size
  end

  def print_summary
    puts
    puts "=== Customer Transform Summary ==="
    puts "Records read:        #{@stats[:records_read]}"
    puts "Objects found:       #{@stats[:objects_found]}"
    puts "Objects transformed: #{@stats[:objects_transformed]}"
    puts
    puts "Records written:     #{@stats[:records_written]}"
    puts "Lookup entries:      #{@stats[:lookup_entries]}"

    return unless @stats[:errors].any?

    puts
    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(5).each { |err| puts "  - #{err}" }
  end
end

def parse_args(args)
  require 'optparse'

  # All paths resolved relative to kiba directory for consistency
  kiba_dir = File.expand_path('..', __dir__)
  migrations_dir = File.expand_path('../..', kiba_dir)

  options = {
    input_file: File.join(migrations_dir, 'exports/customer/customer_dump.jsonl'),
    output_dir: File.join(kiba_dir, 'exports'),
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby jobs/01_customer.rb [OPTIONS]"
    opts.separator ""
    opts.separator "Kiba ETL job for customer data transformation (Phase 1)."
    opts.separator ""
    opts.separator "Options:"

    opts.on('--input-file=FILE', 'Input JSONL file') do |file|
      options[:input_file] = File.expand_path(file, kiba_dir)
    end

    opts.on('--output-dir=DIR', 'Output directory') do |dir|
      options[:output_dir] = File.expand_path(dir, kiba_dir)
    end

    opts.on('--redis-url=URL', 'Redis URL (default: redis://127.0.0.1:6379)') do |url|
      options[:redis_url] = url
    end

    opts.on('--temp-db=N', Integer, 'Temp database (default: 15)') do |db|
      options[:temp_db] = db
    end

    opts.on('--dry-run', 'Parse and count without writing') do
      options[:dry_run] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts "Output files:"
      puts "  exports/customer/customer_transformed.jsonl"
      puts "  exports/lookups/email_to_customer_objid.json"
      exit 0
    end
  end

  parser.parse!(args)
  options
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  warn e.message
  warn "Use --help for usage information"
  exit 1
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)
  CustomerJob.new(options).run
end
