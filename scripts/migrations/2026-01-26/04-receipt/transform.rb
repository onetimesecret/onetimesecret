#!/usr/bin/env ruby
# frozen_string_literal: true

# Transforms Receipt (formerly Metadata) data from V1 dump to V2 format.
#
# Reads a JSONL dump file, processes each metadata record, and applies transformations
# based on the migration spec. This includes:
# - Renaming keys from metadata:{objid}:object to receipt:{objid}:object
# - Transforming custid (email) -> owner_id (customer objid)
# - Linking to org_id (organization objid) and domain_id (if share_domain set)
# - Transforming state values: 'viewed' -> 'previewed', 'received' -> 'revealed'
# - Renaming viewed -> previewed, received -> revealed (keeping originals for compat)
# - Creating new Redis DUMPs for transformed objects
# - Outputting a new JSONL file with V2 records
#
# Usage:
#   ruby scripts/migrations/2026-01-26/04-receipt/transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE        Input JSONL dump file (default: exports/metadata/metadata_dump.jsonl)
#   --output-dir=DIR         Output directory (default: exports/receipt)
#   --email-to-customer=FILE JSON map of email -> customer_objid
#   --customer-to-org=FILE   JSON map of customer_objid -> org_objid
#   --fqdn-to-domain=FILE    JSON map of fqdn -> domain_objid
#   --redis-url=URL          Redis URL for temporary operations (default: redis://127.0.0.1:6379)
#   --temp-db=N              Temporary database for restore/dump (default: 15)
#   --dry-run                Parse and count without writing output
#
# Output: receipt_transformed.jsonl with V2 records in Redis DUMP format.
#
# Dependencies:
#   - Phase 1 Customer migration (provides email->customer_objid)
#   - Phase 2 Organization migration (provides customer_objid->org_objid)
#   - Phase 3 CustomDomain migration (provides fqdn->domain_objid)

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'

class ReceiptTransformer
  TEMP_KEY_PREFIX = '_migrate_tmp_receipt_'

  # Fields to copy directly without transformation
  DIRECT_COPY_FIELDS = %w[
    objid secret_identifier secret_shortid secret_ttl lifespan
    share_domain passphrase recipients memo created updated burned
    shared truncate secret_key key
  ].freeze

  # State value transformations
  STATE_TRANSFORMS = {
    'viewed' => 'previewed',
    'received' => 'revealed',
  }.freeze

  def initialize(input_file:, output_dir:, email_to_customer_file:, customer_to_org_file:, fqdn_to_domain_file:, redis_url:, temp_db:, dry_run: false)
    @input_file              = input_file
    @output_dir              = output_dir
    @email_to_customer_file  = email_to_customer_file
    @customer_to_org_file    = customer_to_org_file
    @fqdn_to_domain_file     = fqdn_to_domain_file
    @redis_url               = redis_url
    @temp_db                 = temp_db
    @dry_run                 = dry_run
    @redis                   = nil

    @email_to_customer = {}
    @customer_to_org   = {}
    @fqdn_to_domain    = {}

    @stats = {
      receipts_processed: 0,
      v1_records_read: 0,
      v2_records_written: 0,
      transformed_objects: 0,
      skipped_receipts: 0,
      anonymous_receipts: 0,
      state_transforms: Hash.new(0),
      missing_customer_lookup: 0,
      missing_org_lookup: 0,
      missing_domain_lookup: 0,
      failed_customer_lookups: [],
      failed_org_lookups: [],
      failed_domain_lookups: [],
      errors: [],
    }
  end

  def run
    validate_input_file
    load_mappings
    connect_redis unless @dry_run

    # Process each metadata record and generate V2 receipt records
    v2_records = []

    File.foreach(@input_file) do |line|
      @stats[:v1_records_read] += 1
      v2_records.concat(process_record(line.strip))
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:v1_records_read], error: "JSON parse error: #{ex.message}" }
    rescue StandardError => ex
      @stats[:errors] << { line: @stats[:v1_records_read], error: "Processing failed: #{ex.message}" }
    end

    # Write the transformed records to the output file
    write_output(v2_records) unless @dry_run

    print_summary
  ensure
    cleanup_redis
  end

  private

  def validate_input_file
    raise ArgumentError, "Input file not found: #{@input_file}" unless File.exist?(@input_file)
  end

  def load_mappings
    # Load email -> customer_objid mapping
    @email_to_customer = load_json_mapping(@email_to_customer_file, 'email_to_customer')

    # Load customer_objid -> org_objid mapping
    @customer_to_org = load_json_mapping(@customer_to_org_file, 'customer_to_org')

    # Load fqdn -> domain_objid mapping
    @fqdn_to_domain = load_json_mapping(@fqdn_to_domain_file, 'fqdn_to_domain')

    puts "Loaded mappings: #{@email_to_customer.size} customers, #{@customer_to_org.size} orgs, #{@fqdn_to_domain.size} domains"
  end

  def load_json_mapping(file_path, name)
    return {} if file_path.nil? || file_path.empty?

    unless File.exist?(file_path)
      warn "Warning: #{name} mapping file not found: #{file_path}"
      return {}
    end

    JSON.parse(File.read(file_path))
  rescue JSON::ParserError => ex
    warn "Error parsing #{name} mapping file: #{ex.message}"
    {}
  end

  def connect_redis
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
    @redis.ping
  end

  def cleanup_redis
    return unless @redis

    cursor = '0'
    loop do
      cursor, keys = @redis.scan(cursor, match: "#{TEMP_KEY_PREFIX}*", count: 100)
      @redis.del(*keys) unless keys.empty?
      break if cursor == '0'
    end
    @redis.close
  end

  def process_record(line)
    return [] if line.empty?

    record = JSON.parse(line, symbolize_names: true)
    key    = record[:key]

    # Only process :object keys
    return [] unless key&.end_with?(':object')

    # Must be a metadata key pattern: metadata:{objid}:object
    return [] unless key.start_with?('metadata:')

    return [] if @dry_run

    v1_fields = restore_and_read_hash(record)
    objid     = extract_objid(key)

    unless objid && !objid.empty?
      @stats[:skipped_receipts] += 1
      @stats[:errors] << { key: key, error: 'Could not extract objid from key.' }
      return []
    end

    # Transform the metadata object to receipt
    v2_record = transform_receipt_object(record, v1_fields, objid)

    @stats[:receipts_processed] += 1
    [v2_record]
  end

  def extract_objid(key)
    # Pattern: metadata:{objid}:object
    match = key.match(/^metadata:([^:]+):object$/)
    match ? match[1] : nil
  end

  def transform_receipt_object(v1_record, v1_fields, objid)
    v2_fields = {}

    # Copy direct fields
    DIRECT_COPY_FIELDS.each do |field|
      v2_fields[field] = v1_fields[field] if v1_fields.key?(field)
    end

    # Ensure objid is set (Receipt uses VerifiableIdentifier - no extid)
    v2_fields['objid'] = objid

    # Transform custid -> owner_id, org_id, domain_id
    custid = v1_fields['custid']
    transform_ownership(v2_fields, custid, v1_fields['share_domain'])

    # Preserve original custid
    v2_fields['v1_custid'] = custid if custid && !custid.empty?

    # Transform state value
    if v1_fields['state']
      old_state                             = v1_fields['state']
      new_state                             = STATE_TRANSFORMS[old_state] || old_state
      v2_fields['state']                    = new_state
      @stats[:state_transforms][old_state] += 1 if STATE_TRANSFORMS.key?(old_state)
    end

    # Rename viewed -> previewed, received -> revealed (keep originals for compat)
    if v1_fields.key?('viewed')
      v2_fields['previewed'] = v1_fields['viewed']
      v2_fields['viewed']    = v1_fields['viewed']  # Keep for backward compat
    end

    if v1_fields.key?('received')
      v2_fields['revealed'] = v1_fields['received']
      v2_fields['received'] = v1_fields['received']  # Keep for backward compat
    end

    # Add migration tracking fields
    v2_fields['v1_key']           = v1_record[:key]
    v2_fields['v1_identifier']    = v1_record[:key]
    v2_fields['migration_status'] = 'completed'
    v2_fields['migrated_at']      = Time.now.to_f.to_s
    v2_fields['_original_record'] = v1_fields.to_json

    # Create new dump for the transformed hash
    # Filter out nil values - Redis doesn't accept them
    v2_fields_clean = v2_fields.reject { |_k, v| v.nil? }

    temp_key    = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    v2_dump_b64 = begin
      @redis.hmset(temp_key, v2_fields_clean.to_a.flatten)
      dump_data = @redis.dump(temp_key)
      Base64.strict_encode64(dump_data)
    ensure
      @redis.del(temp_key)
    end

    @stats[:transformed_objects] += 1

    {
      key: "receipt:#{objid}:object",
      type: 'hash',
      ttl_ms: v1_record[:ttl_ms],
      db: v1_record[:db],
      dump: v2_dump_b64,
      objid: objid,
      owner_id: v2_fields['owner_id'],
      org_id: v2_fields['org_id'],
      domain_id: v2_fields['domain_id'],
      created: v1_record[:created] || v1_fields['created']&.to_i,
    }
  end

  def transform_ownership(v2_fields, custid, share_domain)
    # Handle anonymous receipts
    if custid.nil? || custid.empty? || custid == 'anon'
      v2_fields['owner_id']        = 'anon'
      @stats[:anonymous_receipts] += 1
      return
    end

    # Lookup owner_id from email
    owner_id = @email_to_customer[custid]
    if owner_id
      v2_fields['owner_id'] = owner_id

      # Lookup org_id from owner_id
      org_id = @customer_to_org[owner_id]
      if org_id
        v2_fields['org_id'] = org_id
      else
        @stats[:missing_org_lookup] += 1
        @stats[:failed_org_lookups] << owner_id
      end
    else
      @stats[:missing_customer_lookup] += 1
      @stats[:failed_customer_lookups] << custid
      # Still set owner_id to nil to indicate lookup failure
      v2_fields['owner_id']             = nil
    end

    # Lookup domain_id from share_domain (fqdn)
    return unless share_domain && !share_domain.empty?

    domain_id = @fqdn_to_domain[share_domain]
    if domain_id
      v2_fields['domain_id'] = domain_id
    else
      @stats[:missing_domain_lookup] += 1
      @stats[:failed_domain_lookups] << share_domain
    end
  end

  def restore_and_read_hash(record)
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])
    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.hgetall(temp_key)
    rescue Redis::CommandError => ex
      raise "Restore failed for key #{record[:key]}: #{ex.message}"
    ensure
      @redis.del(temp_key) if @redis
    end
  end

  def write_output(records)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'receipts_transformed.jsonl')

    File.open(output_file, 'w') do |f|
      records.each do |record|
        f.puts(JSON.generate(record))
        @stats[:v2_records_written] += 1
      end
    end
    puts "Wrote #{@stats[:v2_records_written]} transformed records to #{output_file}"
  end

  def print_summary
    puts "\n=== Receipt Transformation Summary ==="
    puts "Input file: #{@input_file}"
    puts "V1 records read: #{@stats[:v1_records_read]}"
    puts "Receipts processed: #{@stats[:receipts_processed]}"
    puts "Receipts skipped: #{@stats[:skipped_receipts]}"
    puts

    puts 'V2 Records Written:'
    puts "  Total: #{@stats[:v2_records_written]}"
    puts "  Transformed objects: #{@stats[:transformed_objects]}"
    puts

    puts 'Ownership:'
    puts "  Anonymous receipts: #{@stats[:anonymous_receipts]}"
    puts "  Missing customer lookups: #{@stats[:missing_customer_lookup]}"
    puts "  Missing org lookups: #{@stats[:missing_org_lookup]}"
    puts "  Missing domain lookups: #{@stats[:missing_domain_lookup]}"
    puts

    # Print failed lookups (unique values only)
    failed_customers = @stats[:failed_customer_lookups].uniq
    if failed_customers.any?
      puts "Failed customer lookups (#{failed_customers.size} unique):"
      failed_customers.first(20).each { |email| puts "  - #{email}" }
      puts "  ... and #{failed_customers.size - 20} more" if failed_customers.size > 20
      puts
    end

    failed_orgs = @stats[:failed_org_lookups].uniq
    if failed_orgs.any?
      puts "Failed org lookups (#{failed_orgs.size} unique):"
      failed_orgs.first(20).each { |owner_id| puts "  - #{owner_id}" }
      puts "  ... and #{failed_orgs.size - 20} more" if failed_orgs.size > 20
      puts
    end

    failed_domains = @stats[:failed_domain_lookups].uniq
    if failed_domains.any?
      puts "Failed domain lookups (#{failed_domains.size} unique):"
      failed_domains.first(20).each { |fqdn| puts "  - #{fqdn}" }
      puts "  ... and #{failed_domains.size - 20} more" if failed_domains.size > 20
      puts
    end

    puts 'State Transforms:'
    @stats[:state_transforms].each do |old_state, count|
      new_state = STATE_TRANSFORMS[old_state]
      puts "  #{old_state} -> #{new_state}: #{count}"
    end
    puts '  (none)' if @stats[:state_transforms].empty?
    puts

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  - #{err}" }
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    input_file: 'exports/metadata/metadata_dump.jsonl',
    output_dir: 'exports/metadata',
    email_to_customer: nil,
    customer_to_org: nil,
    fqdn_to_domain: nil,
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/ then options[:input_file]               = Regexp.last_match(1)
    when /^--output-dir=(.+)$/ then options[:output_dir]               = Regexp.last_match(1)
    when /^--email-to-customer=(.+)$/ then options[:email_to_customer] = Regexp.last_match(1)
    when /^--customer-to-org=(.+)$/ then options[:customer_to_org]     = Regexp.last_match(1)
    when /^--fqdn-to-domain=(.+)$/ then options[:fqdn_to_domain]       = Regexp.last_match(1)
    when /^--redis-url=(.+)$/ then options[:redis_url]                 = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/ then options[:temp_db]                    = Regexp.last_match(1).to_i
    when '--dry-run' then options[:dry_run]                            = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Transforms Receipt (Metadata) data from V1 dump to V2 format.

        Options:
          --input-file=FILE        Input JSONL dump (default: exports/metadata/metadata_dump.jsonl)
          --output-dir=DIR         Output directory (default: exports/metadata)
          --email-to-customer=FILE JSON map: email -> customer_objid
          --customer-to-org=FILE   JSON map: customer_objid -> org_objid
          --fqdn-to-domain=FILE    JSON map: fqdn -> domain_objid
          --redis-url=URL          Redis URL for temp operations (default: redis://127.0.0.1:6379)
          --temp-db=N              Temp database number (default: 15)
          --dry-run                Parse and count without writing output
          --help                   Show this help

        Output file: receipts_transformed.jsonl

        Dependencies:
          Requires Phase 1 (Customer), Phase 2 (Organization), Phase 3 (CustomDomain).

        Key transformations:
          - Key: metadata:{objid}:object -> receipt:{objid}:object
          - custid (email) -> owner_id (customer objid)
          - Links org_id (via owner) and domain_id (via share_domain)
          - State: 'viewed' -> 'previewed', 'received' -> 'revealed'
          - Renames viewed->previewed, received->revealed (keeps originals)
          - Preserves v1_custid for rollback

        Note: Receipt uses VerifiableIdentifier (no extid generation).
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end
  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  transformer = ReceiptTransformer.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    email_to_customer_file: options[:email_to_customer],
    customer_to_org_file: options[:customer_to_org],
    fqdn_to_domain_file: options[:fqdn_to_domain],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )
  transformer.run
end
