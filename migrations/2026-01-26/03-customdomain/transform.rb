#!/usr/bin/env ruby
# frozen_string_literal: true

# Transforms CustomDomain data from V1 dump to V2 format.
#
# Reads a JSONL dump file, groups records by domain, and applies transformations
# based on the migration spec. This includes:
# - Renaming keys from custom_domain:{domainid} to custom_domain:{objid}
# - Transforming custid (email) -> org_id (organization objid) + owner_id (customer objid)
# - Preserving original custid as v1_custid
# - Creating new Redis DUMPs for transformed objects
# - Outputting a new JSONL file with V2 records
#
# Usage:
#   ruby scripts/migrations/2026-01-26/03-customdomain/transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE        Input JSONL dump file (default: results/customdomain/customdomain_dump.jsonl)
#   --output-dir=DIR         Output directory (default: results/customdomain)
#   --email-to-org=FILE      JSON map of email -> org_objid (default: results/organization/email_to_org_objid.json)
#   --email-to-customer=FILE JSON map of email -> customer_objid (built from customer transform)
#   --redis-url=URL          Redis URL for temporary operations (default: redis://127.0.0.1:6379)
#   --temp-db=N              Temporary database for restore/dump (default: 15)
#   --dry-run                Parse and count without writing output
#
# Output: customdomain_transformed.jsonl with V2 records in Redis DUMP format.
#
# Dependencies:
#   - Phase 1 Customer migration (provides email->customer_objid via customer_transformed.jsonl)
#   - Phase 2 Organization migration (provides email->org_objid via email_to_org_objid.json)

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'

class CustomDomainTransformer
  TEMP_KEY_PREFIX = '_migrate_tmp_domain_'

  # V1 index keys that should be skipped (not domain-specific records)
  # These are 2-part keys like custom_domain:owners, custom_domain:display_domains
  V1_INDEX_KEYS = %w[owners display_domains instances values].freeze

  # Fields to copy directly without transformation
  DIRECT_COPY_FIELDS = %w[
    domainid display_domain base_domain subdomain trd tld sld
    txt_validation_host txt_validation_value status vhost verified
    resolving created updated
  ].freeze

  def initialize(input_file:, output_dir:, email_to_org_file:, email_to_customer_file:, redis_url:, temp_db:, dry_run: false)
    @input_file             = input_file
    @output_dir             = output_dir
    @email_to_org_file      = email_to_org_file
    @email_to_customer_file = email_to_customer_file
    @redis_url              = redis_url
    @temp_db                = temp_db
    @dry_run                = dry_run
    @redis                  = nil

    @email_to_org      = {}
    @email_to_customer = {}

    @fqdn_to_objid = {}  # FQDN -> objid mapping for downstream consumers

    @stats = {
      domains_processed: 0,
      v1_records_read: 0,
      v2_records_written: 0,
      transformed_objects: 0,
      renamed_related: Hash.new(0),
      skipped_domains: 0,
      missing_org_mapping: 0,
      missing_object_records: [],    # Domains with no :object record
      unmapped_custids: [],          # Domains where custid couldn't be mapped to org
      errors: [],
    }
  end

  def run
    validate_input_file
    connect_redis unless @dry_run
    load_mappings

    # 1. Group records by domain ID from the dump file
    records_by_domain = group_records_by_domain

    # 2. Process each domain group to generate V2 records
    v2_records = []
    records_by_domain.each do |domainid, records|
      v2_records.concat(process_domain(domainid, records))
    rescue StandardError => ex
      @stats[:errors] << { domain: domainid, records: records, error: "Processing failed: #{ex.message}" }
    end

    # 3. Write the transformed records to the output file
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
    # Load email -> org_objid mapping (direct from organization generate.rb output)
    if @email_to_org_file.nil? || @email_to_org_file.empty?
      raise ArgumentError, 'Email-to-org mapping file is required'
    end

    unless File.exist?(@email_to_org_file)
      raise ArgumentError, "Email-to-org mapping file not found: #{@email_to_org_file}"
    end

    @email_to_org = JSON.parse(File.read(@email_to_org_file))
    puts "Loaded #{@email_to_org.size} email->org mappings from #{@email_to_org_file}"

    # Load email -> customer_objid mapping by reading customer_transformed.jsonl
    if @email_to_customer_file && File.exist?(@email_to_customer_file)
      build_email_to_customer_mapping(@email_to_customer_file)
      puts "Loaded #{@email_to_customer.size} email->customer_objid mappings from #{@email_to_customer_file}"
    elsif @email_to_customer_file
      warn "Warning: email_to_customer file not found: #{@email_to_customer_file}"
    end
  end

  def build_email_to_customer_mapping(customer_file)
    # Read customer_transformed.jsonl and build email -> customer_objid mapping
    # The v1_custid field contains the original email
    File.foreach(customer_file) do |line|
      record = JSON.parse(line, symbolize_names: true)
      next unless record[:key]&.end_with?(':object')

      # Decode the hash to get v1_custid (email)
      if @dry_run
        # In dry run, we can't decode the hash, but we can try to extract from the record
        next
      end

      objid = record[:objid]
      next unless objid

      # We need to decode the dump to get v1_custid
      temp_key  = "#{TEMP_KEY_PREFIX}cust_#{SecureRandom.hex(4)}"
      dump_data = Base64.strict_decode64(record[:dump])

      begin
        @redis.restore(temp_key, 0, dump_data, replace: true)
        fields = @redis.hgetall(temp_key)

        email                     = fields['v1_custid'] || fields['email']
        @email_to_customer[email] = objid if email && !email.empty?
      rescue Redis::CommandError => ex
        @stats[:errors] << { key: record[:key], error: "Mapping restore failed: #{ex.message}" }
      ensure
        begin
          @redis.del(temp_key)
        rescue StandardError
          nil
        end
      end
    rescue JSON::ParserError
      next
    end
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

  def group_records_by_domain
    puts "Reading and grouping records from #{@input_file}..."
    groups = Hash.new { |h, k| h[k] = [] }

    File.foreach(@input_file) do |line|
      @stats[:v1_records_read] += 1
      record                    = JSON.parse(line, symbolize_names: true)

      key = record[:key]
      next unless key

      # Parse key parts: custom_domain:{identifier}:{type} or custom_domain:{identifier}
      key_parts = key.split(':')
      next unless key_parts.first == 'customdomain' && key_parts.size >= 2

      # Skip V1 index keys (2-part keys where second part is an index name)
      # e.g., custom_domain:owners, custom_domain:display_domains, custom_domain:values
      if key_parts.size == 2 && V1_INDEX_KEYS.include?(key_parts[1])
        # Store instance indexes for later processing if needed
        groups['__instance_index__'] << record if key_parts[1] == 'values'
        next
      end

      domainid = key_parts[1]
      groups[domainid] << record
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:v1_records_read], error: "JSON parse error: #{ex.message}" }
    end

    puts "Found #{@stats[:v1_records_read]} records for #{groups.size - (groups.key?('__instance_index__') ? 1 : 0)} distinct domains."
    groups
  end

  def process_domain(domainid, records)
    # Skip the instance index - handled separately
    return [] if domainid == '__instance_index__'

    object_record = records.find { |r| r[:key].end_with?(':object') }
    unless object_record
      @stats[:skipped_domains] += 1
      related_keys              = records.map { |r| r[:key] }
      @stats[:missing_object_records] << {
        domainid: domainid,
        related_keys: related_keys,
        record_count: records.size,
      }
      @stats[:errors] << { domain: domainid, error: 'No :object record found.' }
      return []
    end

    return [] if @dry_run

    v1_fields    = restore_and_read_hash(object_record)
    objid, extid = resolve_identifiers(object_record, v1_fields)

    unless objid && !objid.empty?
      @stats[:skipped_domains] += 1
      @stats[:errors] << { domain: domainid, error: 'Could not resolve objid.' }
      return []
    end

    # Transform the main object
    v2_object_record = transform_domain_object(object_record, v1_fields, objid, extid)

    # Rename related records (brand, logo, icon hashes)
    related_records    = records.reject { |r| r[:key].end_with?(':object') }
    v2_related_records = rename_related_records(related_records, objid)

    @stats[:domains_processed] += 1
    [v2_object_record].concat(v2_related_records)
  end

  def transform_domain_object(v1_record, v1_fields, objid, extid)
    v2_fields = {}

    # Copy direct fields
    DIRECT_COPY_FIELDS.each do |field|
      v2_fields[field] = v1_fields[field] if v1_fields.key?(field)
    end

    # Set canonical identifiers
    # objid: UUIDv7 generated by enrich_with_identifiers.rb from created timestamp
    # extid: Derived from objid with "cd" prefix (27 chars: cd + 25 base36)
    v2_fields['objid'] = objid
    v2_fields['extid'] = extid if extid && !extid.empty?

    # Transform custid (email) -> org_id, preserve original as v1_custid
    # Domains are now associated to the organization, NOT the customer
    custid = v1_fields['custid']
    if custid && !custid.empty?
      v2_fields['v1_custid'] = custid

      # Resolve org_id from email
      org_id = @email_to_org[custid]
      if org_id
        v2_fields['org_id'] = org_id
      else
        @stats[:missing_org_mapping] += 1
        customer_objid                = @email_to_customer[custid]
        @stats[:unmapped_custids] << {
          domainid: v1_fields['domainid'],
          objid: objid,
          custid: custid,
          display_domain: v1_fields['display_domain'],
          created: v1_fields['created'],
          customer_objid: customer_objid,
          reason: customer_objid ? 'customer_objid not in org mapping' : 'custid not in customer mapping',
        }
        @stats[:errors] << { domain: objid, error: "No org mapping for custid: #{custid}" }
      end
    end

    # Add migration tracking fields
    # NOTE: _original_record is added by enrich_with_original_record.rb
    v2_fields['v1_identifier']    = v1_record[:key]
    v2_fields['migration_status'] = 'completed'
    v2_fields['migrated_at']      = Time.now.to_f.to_s

    # Create new dump for the transformed hash
    temp_key    = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    v2_dump_b64 = begin
      @redis.hmset(temp_key, v2_fields.to_a.flatten)
      dump_data = @redis.dump(temp_key)
      Base64.strict_encode64(dump_data)
    ensure
      @redis.del(temp_key)
    end

    @stats[:transformed_objects] += 1

    # Track FQDN -> objid mapping for downstream consumers (receipt/secret indexers)
    display_domain = v2_fields['display_domain']
    if display_domain && !display_domain.empty?
      @fqdn_to_objid[display_domain] = objid
    end

    {
      key: "custom_domain:#{objid}:object",  # NOTE: underscore added per spec
      type: 'hash',
      ttl_ms: v1_record[:ttl_ms],
      db: v1_record[:db],
      dump: v2_dump_b64,
      objid: objid,
      extid: v2_fields['extid'],
      org_id: v2_fields['org_id'],
      created: v1_record[:created] || v1_fields['created']&.to_i,
    }
  end

  def rename_related_records(records, objid)
    records.map do |record|
      v2_record = record.dup
      key_parts = record[:key].split(':')  # custom_domain:{domainid}:{type}

      # Get the data type (brand, logo, icon, etc.)
      data_type = key_parts.last

      # Rename key with underscore: customdomain -> custom_domain
      new_key                              = "custom_domain:#{objid}:#{data_type}"
      v2_record[:key]                      = new_key
      @stats[:renamed_related][data_type] += 1

      v2_record
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

  def resolve_identifiers(record, fields)
    # Use enriched objid/extid from JSONL record (set by enrich_with_identifiers.rb)
    # objid is UUIDv7 generated from created timestamp, NOT the v1 domainid
    # Fall back to domainid only if enrichment wasn't run (shouldn't happen in normal flow)
    objid   = record[:objid]
    objid ||= fields['objid']
    objid ||= fields['domainid']  # Fallback only

    extid   = record[:extid]
    extid ||= fields['extid']

    [objid, extid]
  end

  def write_output(records)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'customdomain_transformed.jsonl')

    File.open(output_file, 'w') do |f|
      records.each do |record|
        f.puts(JSON.generate(record))
        @stats[:v2_records_written] += 1
      end
    end
    puts "Wrote #{@stats[:v2_records_written]} transformed records to #{output_file}"

    # Write FQDN -> objid lookup for downstream consumers (receipt/secret indexers)
    lookup_file = File.join(@output_dir, 'fqdn_to_objid.json')
    File.write(lookup_file, JSON.pretty_generate(@fqdn_to_objid))
    puts "Wrote #{@fqdn_to_objid.size} FQDN->objid mappings to #{lookup_file}"
  end

  def print_summary
    puts "\n=== CustomDomain Transformation Summary ==="
    puts "Input file: #{@input_file}"
    puts "V1 records read: #{@stats[:v1_records_read]}"
    puts "Domains processed: #{@stats[:domains_processed]}"
    puts "Domains skipped: #{@stats[:skipped_domains]}"
    puts

    puts 'V2 Records Written:'
    puts "  Total: #{@stats[:v2_records_written]}"
    puts "  Transformed objects: #{@stats[:transformed_objects]}"
    puts

    puts 'Renamed Related Records:'
    @stats[:renamed_related].each do |type, count|
      puts "  #{type}: #{count}"
    end
    puts '  (none)' if @stats[:renamed_related].empty?
    puts

    puts 'Mapping Issues:'
    puts "  Missing org mappings: #{@stats[:missing_org_mapping]}"
    puts "  Missing object records: #{@stats[:missing_object_records].size}"
    puts

    # Detail missing object records
    if @stats[:missing_object_records].any?
      puts '=== Domains Missing :object Record (Manual Follow-up Required) ==='
      @stats[:missing_object_records].each do |record|
        puts "  Domain ID: #{record[:domainid]}"
        puts "    Related keys (#{record[:record_count]}): #{record[:related_keys].join(', ')}"
      end
      puts
    end

    # Detail unmapped custids with actionable information
    if @stats[:unmapped_custids].any?
      puts '=== Domains With Unmapped Custid (Manual Follow-up Required) ==='
      by_reason = @stats[:unmapped_custids].group_by { |r| r[:reason] }

      by_reason.each do |reason, records|
        puts "  #{reason} (#{records.size}):"
        records.first(10).each do |record|
          puts "    - #{record[:display_domain] || record[:domainid]}"
          puts "      custid: #{record[:custid]}"
          puts "      objid: #{record[:objid]}"
          puts "      customer_objid: #{record[:customer_objid] || '(not found)'}"
          puts "      created: #{record[:created]}"
        end
        puts "    ... and #{records.size - 10} more" if records.size > 10
      end
      puts
    end

    # Write follow-up files for manual review
    write_followup_files unless @dry_run

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(20).each { |err| puts "  - #{err}" }
    puts "  ... and #{@stats[:errors].size - 20} more" if @stats[:errors].size > 20
  end

  def write_followup_files
    return if @stats[:missing_object_records].empty? && @stats[:unmapped_custids].empty?

    FileUtils.mkdir_p(@output_dir)

    # Write missing object records for follow-up
    if @stats[:missing_object_records].any?
      file = File.join(@output_dir, 'followup_missing_objects.json')
      File.write(file, JSON.pretty_generate(@stats[:missing_object_records]))
      puts "Wrote #{@stats[:missing_object_records].size} missing object records to #{file}"
    end

    # Write unmapped custids for follow-up
    return unless @stats[:unmapped_custids].any?

    file     = File.join(@output_dir, 'followup_unmapped_custids.json')
    File.write(file, JSON.pretty_generate(@stats[:unmapped_custids]))
    puts "Wrote #{@stats[:unmapped_custids].size} unmapped custid records to #{file}"

    # Also write a simple CSV for easier review
    csv_file = File.join(@output_dir, 'followup_unmapped_custids.csv')
    File.open(csv_file, 'w') do |f|
      f.puts 'domainid,objid,custid,display_domain,customer_objid,reason,created'
      @stats[:unmapped_custids].each do |record|
        f.puts [
          record[:domainid],
          record[:objid],
          record[:custid],
          record[:display_domain],
          record[:customer_objid],
          record[:reason],
          record[:created],
        ].map { |v| "\"#{v}\"" }.join(',')
      end
    end
    puts "Wrote CSV summary to #{csv_file}"
  end
end

def parse_args(args)
  options = {
    input_file: 'results/customdomain/customdomain_dump.jsonl',
    output_dir: 'results/customdomain',
    email_to_org: 'results/organization/email_to_org_objid.json',
    email_to_customer: 'results/customer/customer_transformed.jsonl',
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/ then options[:input_file]               = Regexp.last_match(1)
    when /^--output-dir=(.+)$/ then options[:output_dir]               = Regexp.last_match(1)
    when /^--email-to-org=(.+)$/ then options[:email_to_org]           = Regexp.last_match(1)
    when /^--email-to-customer=(.+)$/ then options[:email_to_customer] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/ then options[:redis_url]                 = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/ then options[:temp_db]                    = Regexp.last_match(1).to_i
    when '--dry-run' then options[:dry_run]                            = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Transforms CustomDomain data from V1 dump to V2 format.

        Options:
          --input-file=FILE        Input JSONL dump (default: results/customdomain/customdomain_dump.jsonl)
          --output-dir=DIR         Output directory (default: results/customdomain)
          --email-to-org=FILE      email->org_objid JSON map (default: results/organization/email_to_org_objid.json)
          --email-to-customer=FILE customer transformed JSONL for email->objid (default: results/customer/customer_transformed.jsonl)
          --redis-url=URL          Redis URL for temp operations (default: redis://127.0.0.1:6379)
          --temp-db=N              Temp database number (default: 15)
          --dry-run                Parse and count without writing output
          --help                   Show this help

        Output file: customdomain_transformed.jsonl

        Dependencies:
          Requires Phase 1 (Customer) and Phase 2 (Organization) to be complete.

        Key transformations:
          - Key prefix: custom_domain:{id} -> custom_domain:{objid}
          - custid (email) -> org_id (organization objid) + owner_id (customer objid)
          - Preserves v1_custid for rollback
          - Renames related hashes (brand, logo, icon)
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

  transformer = CustomDomainTransformer.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    email_to_org_file: options[:email_to_org],
    email_to_customer_file: options[:email_to_customer],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )
  transformer.run
end
