#!/usr/bin/env ruby
# frozen_string_literal: true

# Kiba ETL Job: Organization Generation (Phase 2)
#
# Generates organization records from Phase 1 customer output.
# Organizations are NEW in V2 - one is created per Customer.
#
# Input:  exports/customer/customer_transformed.jsonl (from Phase 1)
# Output: exports/organization/organization_transformed.jsonl
#         exports/lookups/email_to_org_objid.json
#         exports/lookups/customer_objid_to_org_objid.json
#
# Usage:
#   cd migrations/2026-01-26/kiba
#   bundle exec ruby jobs/02_organization.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: exports/customer/customer_transformed.jsonl)
#   --output-dir=DIR    Output directory (default: exports)
#   --redis-url=URL     Redis URL (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database (default: 15)
#   --dry-run           Parse and count without writing
#   --strict            Filter out records that fail validation

require 'kiba'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'migration'

class OrganizationJob
  PHASE = 2
  MODEL = 'organization'

  def initialize(options)
    @input_file = options[:input_file]
    @output_dir = options[:output_dir]
    @redis_url = options[:redis_url]
    @temp_db = options[:temp_db]
    @dry_run = options[:dry_run]
    @strict_validation = options[:strict_validation]

    @stats = {
      records_read: 0,
      customer_objects: 0,
      organizations_generated: 0,
      records_written: 0,
      email_lookups: 0,
      customer_lookups: 0,
      stripe_customers: 0,
      stripe_subscriptions: 0,
      validated: 0,
      validation_failures: 0,
      validation_skipped: 0,
      skipped_non_customer_object: 0,
      skipped_no_objid: 0,
      skipped_no_fields: 0,
      errors: [],
    }
  end

  def run
    validate_input!

    puts "Organization Generation Job (Phase #{PHASE})"
    puts '=' * 50
    puts "Input:  #{@input_file}"
    puts "Output: #{output_file}"
    puts "Lookup: #{email_lookup_file}"
    puts "Lookup: #{customer_lookup_file}"
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

  def email_lookup_file
    File.join(@output_dir, 'lookups', 'email_to_org_objid.json')
  end

  def customer_lookup_file
    File.join(@output_dir, 'lookups', 'customer_objid_to_org_objid.json')
  end

  def run_dry
    # Simple pass to count records
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record = JSON.parse(line, symbolize_names: true)

      if record[:key]&.end_with?(':object') && record[:key]&.start_with?('customer:')
        @stats[:customer_objects] += 1
        @stats[:organizations_generated] += 1 if record[:objid]
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

    # Build and run Kiba job
    job = build_kiba_job(redis_helper)
    Kiba.run(job)
  ensure
    redis_helper&.cleanup!
    redis_helper&.disconnect!
  end

  def build_kiba_job(redis_helper)
    input_file = @input_file
    output_file_path = output_file
    email_lookup_path = email_lookup_file
    customer_lookup_path = customer_lookup_file
    stats = @stats
    job_started_at = Time.now
    strict_validation = @strict_validation

    Kiba.parse do
      # Pre-process: setup directories
      pre_process do
        FileUtils.mkdir_p(File.dirname(output_file_path))
        FileUtils.mkdir_p(File.dirname(email_lookup_path))
      end

      # Source: read customer transformed JSONL
      source Migration::Sources::JsonlSource,
             file: input_file,
             key_pattern: /^customer:/

      # Transform: count records read
      transform do |record|
        stats[:records_read] += 1
        record
      end

      # Transform: decode Redis DUMP to get customer fields
      # Phase 1 output has DUMP data containing v2_fields - decoded into :fields
      transform Migration::Transforms::RedisDumpDecoder,
                redis_helper: redis_helper,
                stats: stats

      # Transform: count customer objects
      transform do |record|
        if record[:key]&.end_with?(':object')
          stats[:customer_objects] += 1
        end
        record
      end

      # Transform: generate organization from customer
      transform Migration::Transforms::Organization::Generator,
                stats: stats,
                migrated_at: job_started_at

      # Transform: validate V2 output structure
      transform Migration::Transforms::SchemaValidator,
                schema: :organization_v2,
                field: :v2_fields,
                strict: strict_validation,
                stats: stats

      # Transform: encode fields to DUMP
      transform Migration::Transforms::RedisDumpEncoder,
                redis_helper: redis_helper,
                fields_key: :v2_fields,
                stats: stats

      # Transform: count records being written
      transform do |record|
        stats[:records_written] += 1
        record
      end

      # Destination: write transformed JSONL and lookup files
      destination Migration::Destinations::CompositeDestination,
                  destinations: [
                    [Migration::Destinations::JsonlDestination, {
                      file: output_file_path,
                      exclude_fields: %i[fields v2_fields decode_error encode_error validation_errors generation_error],
                    }],
                    [Migration::Destinations::LookupDestination, {
                      file: email_lookup_path,
                      key_field: :contact_email,
                      value_field: :objid,
                      phase: PHASE,
                      stats: stats,
                    }],
                    [Migration::Destinations::LookupDestination, {
                      file: customer_lookup_path,
                      key_field: :owner_id,
                      value_field: :objid,
                      phase: PHASE,
                      stats: stats,
                    }],
                  ]
    end
  end

  def print_summary
    puts
    puts '=== Organization Generation Summary ==='
    puts "Records read:             #{@stats[:records_read]}"
    puts "Customer objects:         #{@stats[:customer_objects]}"
    puts "Organizations generated:  #{@stats[:organizations_generated]}"
    puts
    puts "Records written:          #{@stats[:records_written]}"
    puts "Email lookups:            #{@stats[:email_lookups]}"
    puts "Customer lookups:         #{@stats[:customer_lookups]}"
    puts
    puts 'Stripe data:'
    puts "  With customer ID:       #{@stats[:stripe_customers]}"
    puts "  With subscription:      #{@stats[:stripe_subscriptions]}"
    puts
    puts 'Validation:'
    puts "  Validated:              #{@stats[:validated]}"
    puts "  Failures:               #{@stats[:validation_failures]}"
    puts "  Skipped:                #{@stats[:validation_skipped]}"
    puts
    puts 'Skipped records:'
    puts "  Non-customer objects:   #{@stats[:skipped_non_customer_object]}"
    puts "  Missing objid:          #{@stats[:skipped_no_objid]}"
    puts "  Missing fields:         #{@stats[:skipped_no_fields]}"

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

  options = {
    input_file: File.join(kiba_dir, 'exports/customer/customer_transformed.jsonl'),
    output_dir: File.join(kiba_dir, 'exports'),
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
    strict_validation: false,
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby jobs/02_organization.rb [OPTIONS]'
    opts.separator ''
    opts.separator 'Kiba ETL job for organization generation (Phase 2).'
    opts.separator 'Generates organization records from Phase 1 customer output.'
    opts.separator ''
    opts.separator 'Options:'

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

    opts.on('--strict', 'Filter out records that fail validation') do
      options[:strict_validation] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      puts
      puts 'Output files:'
      puts '  exports/organization/organization_transformed.jsonl'
      puts '  exports/lookups/email_to_org_objid.json'
      puts '  exports/lookups/customer_objid_to_org_objid.json'
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
  OrganizationJob.new(options).run
end
