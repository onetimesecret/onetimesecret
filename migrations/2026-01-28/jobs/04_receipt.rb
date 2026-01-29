#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Receipt Transform (Phase 4)
#
# Transforms metadata records from V1 dump format to V2 receipt format.
# Uses lookups from Phases 1-3 to resolve ownership.
#
# Input:  ../exports/metadata/metadata_dump.jsonl
# Output: exports/receipt/receipt_transformed.jsonl
#         exports/lookups/metadata_key_to_receipt_objid.json
#
# Dependencies (lookups from previous phases):
#   - Phase 1: email_to_customer_objid.json
#   - Phase 2: email_to_org_objid.json
#   - Phase 3: fqdn_to_domain_objid.json
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/04_receipt.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: ../exports/metadata/metadata_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports)
#   --redis-url=URL     Redis URL (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database (default: 15)
#   --dry-run           Parse and count without writing
#   --strict            Filter out records that fail validation

require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class ReceiptJob
  PHASE = 4
  MODEL = 'receipt'

  def initialize(options)
    @input_file = options[:input_file]
    @output_dir = options[:output_dir]
    @redis_url = options[:redis_url]
    @temp_db = options[:temp_db]
    @dry_run = options[:dry_run]
    @strict_validation = options[:strict_validation]

    @stats = {
      records_read: 0,
      objects_found: 0,
      objects_transformed: 0,
      records_written: 0,
      lookup_entries: 0,
      owner_resolved: 0,
      owner_unresolved: 0,
      org_resolved: 0,
      org_unresolved: 0,
      domain_resolved: 0,
      domain_unresolved: 0,
      no_custid: 0,
      validated: 0,
      validation_failures: 0,
      validation_skipped: 0,
      skipped_non_metadata_object: 0,
      skipped_no_fields: 0,
      skipped_no_secret_key: 0,
      errors: [],
    }
  end

  def run
    validate_input!
    validate_lookups!

    puts "Receipt Transform Job (Phase #{PHASE})"
    puts '=' * 50
    puts "Input:  #{@input_file}"
    puts "Output: #{output_file}"
    puts "Lookup: #{lookup_file}"
    puts "Mode:   #{@dry_run ? 'DRY RUN' : 'LIVE'}"
    puts
    puts 'Required lookups:'
    puts "  - #{email_to_customer_lookup}"
    puts "  - #{email_to_org_lookup}"
    puts "  - #{fqdn_to_domain_lookup}"
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

  def validate_lookups!
    missing = []

    missing << email_to_customer_lookup unless File.exist?(email_to_customer_lookup)
    missing << email_to_org_lookup unless File.exist?(email_to_org_lookup)
    missing << fqdn_to_domain_lookup unless File.exist?(fqdn_to_domain_lookup)

    return if missing.empty?

    raise ArgumentError, "Required lookup files not found:\n  #{missing.join("\n  ")}\n\nRun Phases 1-3 first."
  end

  def output_file
    File.join(@output_dir, MODEL, "#{MODEL}_transformed.jsonl")
  end

  def lookup_file
    File.join(@output_dir, 'lookups', 'metadata_key_to_receipt_objid.json')
  end

  def email_to_customer_lookup
    File.join(@output_dir, 'lookups', 'email_to_customer_objid.json')
  end

  def email_to_org_lookup
    File.join(@output_dir, 'lookups', 'email_to_org_objid.json')
  end

  def fqdn_to_domain_lookup
    File.join(@output_dir, 'lookups', 'fqdn_to_domain_objid.json')
  end

  def run_dry
    # Simple pass to count records
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record = JSON.parse(line, symbolize_names: true)

      if record[:key]&.end_with?(':object') && record[:key]&.start_with?('metadata:')
        @stats[:objects_found] += 1
        @stats[:objects_transformed] += 1
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

    # Load lookup registry
    registry = Migration::Shared::LookupRegistry.new(exports_dir: @output_dir)
    registry.require_lookup(:email_to_customer, for_phase: PHASE)
    registry.require_lookup(:email_to_org, for_phase: PHASE)
    registry.require_lookup(:fqdn_to_domain, for_phase: PHASE)

    # Build and run Kiba job
    job = build_kiba_job(redis_helper, registry)
    Kiba.run(job)
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
    strict_validation = @strict_validation

    Kiba.parse do
      # Pre-process: setup directories
      pre_process do
        FileUtils.mkdir_p(File.dirname(output_file_path))
        FileUtils.mkdir_p(File.dirname(lookup_file_path))
      end

      # Source: read metadata JSONL
      source Migration::Sources::JsonlSource,
             file: input_file,
             key_pattern: /^metadata:/

      # Transform: count records read
      transform do |record|
        stats[:records_read] += 1
        record
      end

      # Transform: decode Redis DUMP
      transform Migration::Transforms::RedisDumpDecoder,
                redis_helper: redis_helper,
                stats: stats

      # Transform: validate V1 input structure
      transform Migration::Transforms::SchemaValidator,
                schema: :metadata_v1,
                field: :fields,
                strict: strict_validation,
                stats: stats

      # Transform: count objects
      transform do |record|
        if record[:key]&.end_with?(':object')
          stats[:objects_found] += 1
        end
        record
      end

      # Transform: apply field transformations with lookups
      transform Migration::Transforms::Receipt::FieldTransformer,
                registry: registry,
                stats: stats,
                migrated_at: job_started_at

      # Transform: validate V2 output structure
      transform Migration::Transforms::SchemaValidator,
                schema: :receipt_v2,
                field: :v2_fields,
                strict: strict_validation,
                stats: stats

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

      # Destination: write transformed JSONL and lookup file
      destination Migration::Destinations::CompositeDestination,
                  destinations: [
                    [Migration::Destinations::JsonlDestination, {
                      file: output_file_path,
                      exclude_fields: %i[fields v2_fields decode_error encode_error validation_errors],
                    }],
                    [Migration::Destinations::LookupDestination, {
                      file: lookup_file_path,
                      key_field: :secret_key,
                      value_field: :objid,
                      phase: PHASE,
                      stats: stats,
                    }],
                  ]
    end
  end

  def print_summary
    puts
    puts '=== Receipt Transform Summary ==='
    puts "Records read:           #{@stats[:records_read]}"
    puts "Objects found:          #{@stats[:objects_found]}"
    puts "Objects transformed:    #{@stats[:objects_transformed]}"
    puts
    puts "Records written:        #{@stats[:records_written]}"
    puts "Lookup entries:         #{@stats[:lookup_entries]}"
    puts
    puts 'Ownership resolution:'
    puts "  Owner resolved:       #{@stats[:owner_resolved]}"
    puts "  Owner unresolved:     #{@stats[:owner_unresolved]}"
    puts "  Org resolved:         #{@stats[:org_resolved]}"
    puts "  Org unresolved:       #{@stats[:org_unresolved]}"
    puts "  Domain resolved:      #{@stats[:domain_resolved]}"
    puts "  Domain unresolved:    #{@stats[:domain_unresolved]}"
    puts "  No custid:            #{@stats[:no_custid]}"
    puts
    puts 'Validation:'
    puts "  Validated:            #{@stats[:validated]}"
    puts "  Failures:             #{@stats[:validation_failures]}"
    puts "  Skipped:              #{@stats[:validation_skipped]}"
    puts
    puts 'Skipped records:'
    puts "  Non-metadata objects: #{@stats[:skipped_non_metadata_object]}"
    puts "  Missing fields:       #{@stats[:skipped_no_fields]}"
    puts "  Missing secret key:   #{@stats[:skipped_no_secret_key]}"

    return unless @stats[:errors].any?

    puts
    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(5).each { |err| puts "  - #{err}" }
  end
end

def parse_args(args)
  require 'optparse'

  # All paths resolved relative to migration directory for consistency
  migration_dir = File.expand_path('..', __dir__)
  exports_parent = File.expand_path('../..', migration_dir)

  options = {
    input_file: File.join(exports_parent, 'exports/metadata/metadata_dump.jsonl'),
    output_dir: File.join(migration_dir, 'exports'),
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
    strict_validation: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/04_receipt.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL job for receipt data transformation (Phase 4).'
    opts.separator 'Transforms metadata records to receipts with ownership resolution.'
    opts.separator ''
    opts.separator 'Dependencies:'
    opts.separator '  Requires lookups from Phases 1-3 in exports/lookups/'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--input-file=FILE', 'Input JSONL file') do |file|
      options[:input_file] = File.expand_path(file, migration_dir)
    end

    opts.on('--output-dir=DIR', 'Output directory') do |dir|
      options[:output_dir] = File.expand_path(dir, migration_dir)
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

    opts.on('--strict', 'Filter out records that fail validation') do
      options[:strict_validation] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Output files:'
      puts '  exports/receipt/receipt_transformed.jsonl'
      puts '  exports/lookups/metadata_key_to_receipt_objid.json'
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
  ReceiptJob.new(options).run
end
