#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: CustomDomain Transform (Phase 3)
#
# Transforms customdomain data from V1 dump format to V2 format.
# Uses lookups from Phase 1 (email_to_customer) and Phase 2 (email_to_org)
# to resolve owner_id and org_id references.
#
# Input:  ../exports/customdomain/customdomain_dump.jsonl (from dump)
# Output: exports/customdomain/customdomain_transformed.jsonl
#         exports/lookups/fqdn_to_domain_objid.json
#
# Usage:
#   cd migrations/2026-01-28
#   bundle exec ruby jobs/03_customdomain.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: ../exports/customdomain/customdomain_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports)
#   --redis-url=URL     Redis URL (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database (default: 15)
#   --dry-run           Parse and count without writing
#   --strict            Filter out records that fail validation

require 'fileutils'
require 'json'
require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class CustomdomainJob
  PHASE = 3
  MODEL = 'customdomain'

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
      validated: 0,
      validation_failures: 0,
      validation_skipped: 0,
      skipped_non_object: 0,
      skipped_no_fields: 0,
      skipped_no_custid: 0,
      skipped_no_owner: 0,
      skipped_no_org: 0,
      errors: [],
    }
  end

  def run
    validate_input!
    validate_lookups!

    puts "CustomDomain Transform Job (Phase #{PHASE})"
    puts '=' * 50
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

  def validate_lookups!
    lookups_dir = File.join(@output_dir, 'lookups')

    email_to_customer = File.join(lookups_dir, 'email_to_customer_objid.json')
    unless File.exist?(email_to_customer)
      raise ArgumentError, "Phase 1 lookup not found: #{email_to_customer}\n" \
                           'Run Phase 1 (01_customer.rb) first.'
    end

    email_to_org = File.join(lookups_dir, 'email_to_org_objid.json')
    unless File.exist?(email_to_org)
      raise ArgumentError, "Phase 2 lookup not found: #{email_to_org}\n" \
                           'Run Phase 2 (02_organization.rb) first.'
    end
  end

  def output_file
    File.join(@output_dir, MODEL, "#{MODEL}_transformed.jsonl")
  end

  def lookup_file
    File.join(@output_dir, 'lookups', 'fqdn_to_domain_objid.json')
  end

  def run_dry
    # Simple pass to count records
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record = JSON.parse(line, symbolize_names: true)

      if record[:key]&.end_with?(':object')
        @stats[:objects_found] += 1
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

    # Initialize lookup registry
    registry = Migration::Shared::LookupRegistry.new(exports_dir: @output_dir)
    registry.require_lookup(:email_to_customer, for_phase: PHASE)
    registry.require_lookup(:email_to_org, for_phase: PHASE)

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

      # Source: read customdomain JSONL
      source Migration::Sources::JsonlSource,
             file: input_file,
             key_pattern: /^customdomain:/

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
                schema: :customdomain_v1,
                field: :fields,
                strict: strict_validation,
                stats: stats

      # Transform: count object records
      transform do |record|
        if record[:key]&.end_with?(':object')
          stats[:objects_found] += 1
        end
        record
      end

      # Transform: apply field transformations with lookups
      transform Migration::Transforms::Customdomain::FieldTransformer,
                registry: registry,
                stats: stats,
                migrated_at: job_started_at

      # Transform: validate V2 output structure
      transform Migration::Transforms::SchemaValidator,
                schema: :customdomain_v2,
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
                      exclude_fields: %i[fields v2_fields decode_error encode_error validation_errors transform_error],
                    }],
                    [Migration::Destinations::LookupDestination, {
                      file: lookup_file_path,
                      key_field: :display_domain,
                      value_field: :objid,
                      phase: PHASE,
                      stats: stats,
                    }],
                  ]
    end
  end

  def print_summary
    puts
    puts '=== CustomDomain Transform Summary ==='
    puts "Records read:        #{@stats[:records_read]}"
    puts "Objects found:       #{@stats[:objects_found]}"
    puts "Objects transformed: #{@stats[:objects_transformed]}"
    puts
    puts "Records written:     #{@stats[:records_written]}"
    puts "Lookup entries:      #{@stats[:lookup_entries]}"
    puts
    puts 'Validation:'
    puts "  Validated:         #{@stats[:validated]}"
    puts "  Failures:          #{@stats[:validation_failures]}"
    puts "  Skipped:           #{@stats[:validation_skipped]}"
    puts
    puts 'Skipped records:'
    puts "  Non-object:        #{@stats[:skipped_non_object]}"
    puts "  Missing fields:    #{@stats[:skipped_no_fields]}"
    puts "  Missing custid:    #{@stats[:skipped_no_custid]}"
    puts "  Missing owner:     #{@stats[:skipped_no_owner]}"
    puts "  Missing org:       #{@stats[:skipped_no_org]}"

    return unless @stats[:errors].any?

    puts
    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(5).each { |err| puts "  - #{err}" }
  end
end

def parse_args(args)
  require 'optparse'

  # All paths resolved relative to migrations directory for consistency
  migrations_dir = File.expand_path('..', __dir__)

  options = {
    input_file: File.join(migrations_dir, 'exports/customdomain/customdomain_dump.jsonl'),
    output_dir: File.join(migrations_dir, 'exports'),
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
    strict_validation: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/03_customdomain.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL job for customdomain data transformation (Phase 3).'
    opts.separator 'Requires Phase 1 and Phase 2 lookups to be present.'
    opts.separator ''
    opts.separator 'Options:'

    opts.on('--input-file=FILE', 'Input JSONL file') do |file|
      options[:input_file] = File.expand_path(file, migrations_dir)
    end

    opts.on('--output-dir=DIR', 'Output directory') do |dir|
      options[:output_dir] = File.expand_path(dir, migrations_dir)
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
      puts 'Prerequisites:'
      puts '  Phase 1: exports/lookups/email_to_customer_objid.json'
      puts '  Phase 2: exports/lookups/email_to_org_objid.json'
      puts
      puts 'Output files:'
      puts '  exports/customdomain/customdomain_transformed.jsonl'
      puts '  exports/lookups/fqdn_to_domain_objid.json'
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
  CustomdomainJob.new(options).run
end
