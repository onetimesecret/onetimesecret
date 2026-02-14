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
#   ruby scripts/upgrades/v0.24.0/04-receipt/transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: data/upgrades/v0.24.0/metadata/metadata_dump.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/metadata)
#   --exports-dir=DIR   Base exports directory for loading indexes (default: data/upgrades/v0.24.0)
#   --redis-url=URL     Redis URL for temporary operations (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N         Temporary database for restore/dump (default: 15)
#   --dry-run           Parse and count without writing output
#
# Output: receipt_transformed.jsonl with V2 records in Redis DUMP format.
#
# Required index files (from prior migration phases):
#   - data/upgrades/v0.24.0/customer/customer_indexes.jsonl (email -> customer_objid)
#   - data/upgrades/v0.24.0/organization/organization_indexes.jsonl (email -> org_objid)
#   - data/upgrades/v0.24.0/customdomain/customdomain_indexes.jsonl (fqdn -> domain_objid)

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'familia'
require 'uri'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.0/04-receipt/transform.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class ReceiptTransformer
  TEMP_KEY_PREFIX = '_migrate_tmp_receipt_'

  # Field type mappings for Familia v2 JSON serialization
  # IMPORTANT: All fields must be declared here. Unknown fields will raise errors.
  FIELD_TYPES = {
    # Core fields (receipt.rb)
    'objid' => :string,
    'extid' => :string,
    'owner_id' => :string,
    'state' => :string,
    'secret_identifier' => :string,
    'secret_shortid' => :string,
    'secret_ttl' => :integer,
    'lifespan' => :integer,
    'share_domain' => :string,
    'passphrase' => :string,
    'org_id' => :string,
    'domain_id' => :string,
    'recipients' => :string,  # JSON array stored as string
    'memo' => :string,
    # Required fields - timestamps stored as floats
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields
    'v1_identifier' => :string,
    'v1_key' => :string,
    'v1_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
    # _original_record removed: v1 data now stored as _original_object hashkey via RESTORE
    # Deprecated fields (features/deprecated_fields.rb)
    'key' => :string,
    'viewed' => :timestamp,    # renamed to 'previewed' in v2
    'received' => :timestamp,  # renamed to 'revealed' in v2
    'shared' => :timestamp,
    'burned' => :timestamp,
    'custid' => :string,       # legacy owner field
    'truncate' => :boolean,
    'secret_key' => :string,   # use secret_identifier
    'secret_shortkey' => :string,  # renamed to 'secret_shortid' in v2
    'previewed' => :timestamp,
    'revealed' => :timestamp,
  }.freeze

  # Serialize hash fields for Familia v2 JSON format
  # Empty strings become 'null', typed values are JSON-encoded
  def serialize_for_v2(fields)
    fields.each_with_object({}) do |(key, value), result|
      result[key] = if value == ''
                      'null'
                    else
                      ruby_val = parse_to_ruby_type(key, value)
                      Familia::JsonSerializer.dump(ruby_val)
                    end
    end
  end

  # Convert string value to appropriate Ruby type based on FIELD_TYPES
  def parse_to_ruby_type(key, value)
    field_type = FIELD_TYPES[key.to_s]
    raise ArgumentError, "Unknown field '#{key}' not in FIELD_TYPES - add it to the mapping" unless field_type

    case field_type
    when :string then value
    when :integer then value.to_i
    when :float, :timestamp then value.to_f  # timestamps stored as floats
    when :boolean then value == 'true'
    else
      raise ArgumentError, "Unknown field type '#{field_type}' for field '#{key}'"
    end
  end

  # Fields to copy directly without transformation
  #
  # NOTE: "objid", "secret_identifier", and "secret_shortid" must be populated correctly for
  # the transformed object to be valid. The rest are best-effort copies if present in the v1 data.
  DIRECT_COPY_FIELDS = %w[
    secret_ttl lifespan
    share_domain passphrase recipients memo created updated burned
    shared truncate key
  ].freeze

  # State value transformations
  STATE_TRANSFORMS = {
    'viewed' => 'previewed',
    'received' => 'revealed',
  }.freeze

  # Expected index files relative to exports_dir
  CUSTOMER_INDEXES_FILE = 'customer/customer_indexes.jsonl'
  ORG_INDEXES_FILE      = 'organization/organization_indexes.jsonl'
  DOMAIN_INDEXES_FILE   = 'customdomain/customdomain_indexes.jsonl'

  # Index key names (must match what create_indexes.rb writes)
  CUSTOMER_EMAIL_INDEX_KEY = 'customer:email_index'
  ORG_CONTACT_EMAIL_KEY    = 'organization:contact_email_index'
  DOMAIN_DISPLAY_INDEX_KEY = 'custom_domain:display_domain_index'  # NOTE: underscore in custom_domain

  def initialize(input_file:, output_dir:, exports_dir:, redis_url:, temp_db:, dry_run: false)
    @input_file  = input_file
    @output_dir  = output_dir
    @exports_dir = exports_dir
    @redis_url   = redis_url
    @temp_db     = temp_db
    @dry_run     = dry_run
    @redis       = nil

    @email_to_customer = {}  # email -> customer_objid
    @email_to_org      = {}  # email -> org_objid
    @fqdn_to_domain    = {}  # fqdn -> domain_objid

    @stats = {
      receipts_processed: 0,
      v1_records_read: 0,
      v2_records_written: 0,
      transformed_objects: 0,
      skipped_receipts: 0,
      anonymous_receipts: 0,
      state_transforms: Hash.new(0),
      direct_copy_field_hits: DIRECT_COPY_FIELDS.each_with_object(Hash.new(0)) { |f, h| h[f] = 0 },
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
    # Load from customer_indexes.jsonl: customer:email_index -> email -> objid
    customer_file = File.join(@exports_dir, CUSTOMER_INDEXES_FILE)
    validate_index_file!(customer_file, 'customer')
    load_index_file(customer_file, CUSTOMER_EMAIL_INDEX_KEY) do |email, objid|
      @email_to_customer[email] = objid
    end
    puts "Loaded #{@email_to_customer.size} email->customer mappings"

    # Load from organization_indexes.jsonl: organization:contact_email_index -> email -> org_objid
    org_file = File.join(@exports_dir, ORG_INDEXES_FILE)
    validate_index_file!(org_file, 'organization')
    load_index_file(org_file, ORG_CONTACT_EMAIL_KEY) do |email, org_objid|
      @email_to_org[email] = org_objid
    end
    puts "Loaded #{@email_to_org.size} email->org mappings"

    # Load from customdomain_indexes.jsonl: custom_domain:display_domain_index -> fqdn -> domain_objid
    domain_file = File.join(@exports_dir, DOMAIN_INDEXES_FILE)
    validate_index_file!(domain_file, 'customdomain')
    load_index_file(domain_file, DOMAIN_DISPLAY_INDEX_KEY) do |fqdn, domain_objid|
      @fqdn_to_domain[fqdn] = domain_objid
    end
    puts "Loaded #{@fqdn_to_domain.size} fqdn->domain mappings"
  end

  def validate_index_file!(file_path, name)
    return if File.exist?(file_path)

    raise ArgumentError,
      "Required #{name} index file not found: #{file_path}\n" \
      "Run the #{name} migration phase first to generate this file."
  end

  def load_index_file(file_path, target_key)
    File.foreach(file_path) do |line|
      record = JSON.parse(line)
      next unless record['command'] == 'HSET' && record['key'] == target_key

      # args: [lookup_key, json_quoted_objid]
      args       = record['args']
      lookup_key = args[0]
      objid      = JSON.parse(args[1])  # Remove JSON quoting

      yield(lookup_key, objid)
    rescue JSON::ParserError
      next
    end
  end

  def connect_redis
    uri      = URI.parse(@redis_url)
    uri.path = "/#{@temp_db}"
    @redis   = Redis.new(url: uri.to_s)
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
      if v1_fields.key?(field)
        v2_fields[field] = v1_fields[field]
        @stats[:direct_copy_field_hits][field] += 1
      end
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

    # Rename V1 secret_key -> V2 secret_identifier
    if v1_fields.key?('secret_key') && !v2_fields.key?('secret_identifier')
      v2_fields['secret_identifier'] = v1_fields['secret_key']
    end

    # Rename V1 secret_shortkey -> V2 secret_shortid
    if v1_fields.key?('secret_shortkey') && !v2_fields.key?('secret_shortid')
      v2_fields['secret_shortid'] = v1_fields['secret_shortkey']
    end

    # Add migration tracking fields
    # NOTE: v1 original data is restored as _original_object hashkey by enrich_with_original_record.rb
    v2_fields['v1_key']           = v1_record[:key]
    v2_fields['v1_identifier']    = v1_record[:key]
    v2_fields['migration_status'] = 'completed'
    v2_fields['migrated_at']      = Time.now.to_f.to_s

    # Create new dump for the transformed hash
    # Filter out nil values - Redis doesn't accept them
    v2_fields_clean = v2_fields.compact

    # Serialize values for Familia v2 JSON format
    v2_fields_serialized = serialize_for_v2(v2_fields_clean)

    temp_key    = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    v2_dump_b64 = begin
      @redis.hmset(temp_key, v2_fields_serialized.to_a.flatten)
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
    else
      @stats[:missing_customer_lookup] += 1
      @stats[:failed_customer_lookups] << custid
      # Set owner_id to nil to indicate lookup failure
      v2_fields['owner_id']             = nil
    end

    # Lookup org_id directly from email (organization:contact_email_index)
    org_id = @email_to_org[custid]
    if org_id
      v2_fields['org_id'] = org_id
    else
      @stats[:missing_org_lookup] += 1
      @stats[:failed_org_lookups] << custid
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
    output_file = File.join(@output_dir, 'receipt_transformed.jsonl')

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

    # Warn about DIRECT_COPY_FIELDS that were never found in any v1 record
    zero_hit_fields = @stats[:direct_copy_field_hits].select { |_, count| count.zero? }.keys
    if zero_hit_fields.any? && @stats[:receipts_processed] > 0
      puts 'Direct Copy Field Warnings:'
      zero_hit_fields.each do |field|
        puts "  WARNING: DIRECT_COPY_FIELDS entry '#{field}' had zero hits across #{@stats[:receipts_processed]} records"
      end
      puts
    end

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  - #{err}" }
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'metadata/metadata_dump.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'metadata'),
    exports_dir: DEFAULT_DATA_DIR,
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/ then options[:input_file]   = Regexp.last_match(1)
    when /^--output-dir=(.+)$/ then options[:output_dir]   = Regexp.last_match(1)
    when /^--exports-dir=(.+)$/ then options[:exports_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/ then options[:redis_url]     = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/ then options[:temp_db]        = Regexp.last_match(1).to_i
    when '--dry-run' then options[:dry_run]                = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Transforms Receipt (Metadata) data from V1 dump to V2 format.

        Options:
          --input-file=FILE   Input JSONL dump (default: data/upgrades/v0.24.0/metadata/metadata_dump.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/metadata)
          --exports-dir=DIR   Base exports directory for index files (default: data/upgrades/v0.24.0)
          --redis-url=URL     Redis URL for temp operations (env: VALKEY_URL or REDIS_URL)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Parse and count without writing output
          --help              Show this help

        Output file: receipt_transformed.jsonl

        Required index files (loaded automatically from exports-dir):
          - customer/customer_indexes.jsonl
          - organization/organization_indexes.jsonl
          - customdomain/customdomain_indexes.jsonl

        Key transformations:
          - Key: metadata:{objid}:object -> receipt:{objid}:object
          - custid (email) -> owner_id (customer objid)
          - custid (email) -> org_id (organization objid)
          - share_domain (fqdn) -> domain_id (customdomain objid)
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
    exports_dir: options[:exports_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )
  transformer.run
end
