#!/usr/bin/env ruby
# frozen_string_literal: true

# Transform v1 Redis keys to v2 Valkey format.
#
# Reads per-model JSONL exports from ./exports/, transforms keys/fields according
# to v1->v2 migration rules, outputs transformed JSONL ready for loading.
#
# Input structure (per-model directories or flat files):
#   exports/customer/customer_dump.jsonl     (preferred)
#   exports/customer_dump_*.jsonl            (legacy flat format)
#
# Output structure (same directory as input):
#   exports/customer/customer_transformed.jsonl
#   exports/organization/organization_generated.jsonl
#   exports/membership/membership_generated.jsonl
#   exports/customdomain/customdomain_transformed.jsonl
#   exports/receipt/receipt_transformed.jsonl
#   exports/secret/secret_transformed.jsonl
#
# Usage:
#   ruby scripts/migrations/jan24/transform_keys.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory (default: exports)
#   --output-dir=DIR   Output directory (default: exports/transformed)
#   --dry-run          Show what would be transformed without writing
#
# Transformations:
# - Customer: key unchanged, custid=objid, store email in email field
# - Organization: NEW records created 1:1 with each Customer
# - OrganizationMembership: NEW records linking Customer to Organization
# - CustomDomain: custid (email) -> org_id (Organization objid)
# - Receipt: metadata:{id}: -> receipt:{id}:, custid -> owner_id
# - Secret: custid -> owner_id, remove original_size

require 'json'
require 'base64'
require 'fileutils'

require_relative 'transformers/base_transformer'
require_relative 'transformers/customer_transformer'
require_relative 'transformers/organization_transformer'
require_relative 'transformers/membership_transformer'
require_relative 'transformers/customdomain_transformer'
require_relative 'transformers/receipt_transformer'
require_relative 'transformers/secret_transformer'
require_relative 'transformers/feedback_transformer'

class KeyTransformer
  # Model names and their output file mappings
  MODELS = %w[customer customdomain metadata secret feedback].freeze

  def initialize(input_dir:, dry_run: false)
    @input_dir = input_dir
    @dry_run   = dry_run
    @timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    # Shared context for all transformers
    @context = {
      # Mappings built during customer processing
      email_to_objid: {},       # email -> customer objid
      email_to_org_objid: {},   # email -> organization objid
      email_to_org_data: {},    # email -> organization record (for deferred write)
      email_to_membership: {},  # email -> membership record (for deferred write)

      # Mappings built during customdomain processing
      domainid_to_objid: {},    # old hex domainid -> new UUID objid

      # Shared stats
      stats: {
        customers: { scanned: 0, transformed: 0, skipped: 0 },
        organizations: { generated: 0 },
        memberships: { generated: 0 },
        custom_domains: { scanned: 0, transformed: 0, hashkeys: 0, skipped: 0 },
        receipts: { scanned: 0, transformed: 0, skipped: 0 },
        secrets: { scanned: 0, transformed: 0, skipped: 0 },
        feedback: { scanned: 0, passed_through: 0 },
        indexes: { skipped: 0 },
        other: { skipped: 0 },
      },
    }

    # Initialize transformers
    @transformers = {
      customer: Transformers::CustomerTransformer.new(@context),
      customdomain: Transformers::CustomdomainTransformer.new(@context),
      metadata: Transformers::ReceiptTransformer.new(@context),
      secret: Transformers::SecretTransformer.new(@context),
      feedback: Transformers::FeedbackTransformer.new(@context),
    }

    # Generated record writers
    @organization_transformer = Transformers::OrganizationTransformer.new(@context)
    @membership_transformer   = Transformers::MembershipTransformer.new(@context)
  end

  def transform_all
    # Phase 1: Process customers first (builds email mappings)
    puts '=== Phase 1: Processing Customers ==='
    process_model_file('customer')

    # Phase 2: Process custom domains (needs email->org mapping)
    puts "\n=== Phase 2: Processing Custom Domains ==="
    process_model_file('customdomain')

    # Phase 3: Process receipts (metadata -> receipt)
    puts "\n=== Phase 3: Processing Receipts (Metadata) ==="
    process_model_file('metadata')

    # Phase 4: Process secrets
    puts "\n=== Phase 4: Processing Secrets ==="
    process_model_file('secret')

    # Phase 5: Process feedback (pass through)
    puts "\n=== Phase 5: Processing Feedback ==="
    process_model_file('feedback')

    # Phase 6: Write generated organizations and memberships
    puts "\n=== Phase 6: Writing Generated Records ==="
    write_generated_records unless @dry_run

    # Write manifest
    write_manifest unless @dry_run

    # Sync transformer stats to context stats
    sync_stats

    print_summary
  end

  private

  def process_model_file(model_name)
    input_file = find_input_file(model_name)

    unless input_file
      puts "  No input file found for #{model_name}"
      return
    end

    # Output file: metadata -> receipt (different dir), others same dir as input
    output_model = model_name == 'metadata' ? 'receipt' : model_name
    output_dir   = File.join(@input_dir, output_model)
    output_file  = File.join(output_dir, "#{output_model}_transformed.jsonl")

    puts "  Reading: #{input_file}"
    puts "  Writing: #{output_file}" unless @dry_run

    FileUtils.mkdir_p(output_dir) unless @dry_run

    records_written = 0
    output_handle   = @dry_run ? nil : File.open(output_file, 'w')
    transformer     = @transformers[model_name.to_sym]

    File.foreach(input_file) do |line|
      record = JSON.parse(line.strip)
      key    = record['key']

      transformed = transformer.route(record, key)

      next unless transformed

      unless @dry_run
        output_handle.puts(JSON.generate(transformed))
        records_written += 1
      end
    end

    output_handle&.close
    puts "  Records written: #{records_written}" unless @dry_run
  end

  # Find input file - check model subdirectory first, then flat format
  def find_input_file(model_name)
    # Preferred: exports/{model}/{model}_dump.jsonl
    dir_path = File.join(@input_dir, model_name, "#{model_name}_dump.jsonl")
    return dir_path if File.exist?(dir_path)

    # Legacy: exports/{model}_dump_*.jsonl (timestamped flat files)
    pattern = File.join(@input_dir, "#{model_name}_dump_*.jsonl")
    files   = Dir.glob(pattern).sort
    return files.last if files.any?

    nil
  end

  def write_generated_records
    @organization_transformer.write_generated_records(@input_dir, @timestamp)
    @membership_transformer.write_generated_records(@input_dir, @timestamp)
  end

  def sync_stats
    # Copy transformer stats to context stats for summary
    @context[:stats][:customers]      = @transformers[:customer].stats
    @context[:stats][:custom_domains] = @transformers[:customdomain].stats
    @context[:stats][:receipts]       = @transformers[:metadata].stats
    @context[:stats][:secrets]        = @transformers[:secret].stats
    @context[:stats][:feedback]       = @transformers[:feedback].stats
  end

  def write_manifest
    manifest = {
      timestamp: @timestamp,
      input_dir: @input_dir,
      stats: @context[:stats],
      mappings: {
        email_to_objid_count: @context[:email_to_objid].size,
        email_to_org_count: @context[:email_to_org_objid].size,
      },
    }

    manifest_file = File.join(@input_dir, "transform_manifest_#{@timestamp}.json")
    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "\n  Manifest: #{File.basename(manifest_file)}"
  end

  def print_summary
    stats = @context[:stats]
    puts "\n=== Transformation Summary ==="
    puts "Customers:      #{stats[:customers][:transformed]} transformed, #{stats[:customers][:skipped]} skipped"
    puts "Organizations:  #{stats[:organizations][:generated]} generated"
    puts "Memberships:    #{stats[:memberships][:generated]} generated"
    puts "Custom Domains: #{stats[:custom_domains][:transformed]} transformed, #{stats[:custom_domains][:hashkeys]} hashkeys"
    puts "Receipts:       #{stats[:receipts][:transformed]} transformed"
    puts "Secrets:        #{stats[:secrets][:transformed]} transformed"
    puts "Feedback:       #{stats[:feedback][:passed_through]} passed through"
    puts "Indexes:        #{stats[:indexes][:skipped]} skipped (will rebuild)"
    puts "Other:          #{stats[:other][:skipped]} skipped"
  end
end

def parse_args(args)
  options = {
    input_dir: 'exports',
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--exports-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/transform_keys.rb [OPTIONS]

        Options:
          --input-dir=DIR    Exports directory (default: exports)
          --exports-dir=DIR  Alias for --input-dir
          --dry-run          Show what would be transformed
          --help             Show this help

        Input/Output structure (all files in same model directory):
          exports/customer/customer_dump.jsonl
          exports/customer/customer_transformed.jsonl
          exports/organization/organization_generated.jsonl
          exports/membership/membership_generated.jsonl
          exports/receipt/receipt_transformed.jsonl  (from metadata/)
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  transformer = KeyTransformer.new(
    input_dir: options[:input_dir],
    dry_run: options[:dry_run],
  )

  transformer.transform_all
end
