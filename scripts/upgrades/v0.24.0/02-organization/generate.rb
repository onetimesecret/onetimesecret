#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates Organization records from Customer transformed data.
# Organizations are NEW in V2 - one is created per Customer.
#
# This script runs BEFORE create_indexes.rb to establish org_objid values.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/02-organization/generate.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: data/upgrades/v0.24.0/customer/customer_transformed.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/organization)
#   --redis-url=URL     Redis URL for temporary operations (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N         Temporary database for restore/dump (default: 15)
#   --dry-run           Parse and count without writing output
#
# Input: data/upgrades/v0.24.0/customer/customer_transformed.jsonl (V2 customer records)
# Output:
#   - data/upgrades/v0.24.0/organization/organization_transformed.jsonl (V2 organization records)
#   - data/upgrades/v0.24.0/organization/customer_objid_to_org_objid.json (customer_objid -> org_objid)
#   - data/upgrades/v0.24.0/organization/email_to_org_objid.json (email -> org_objid, for customdomain)

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'digest'
require 'openssl'
require 'familia'
require 'uri'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.0/02-organization/generate.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class OrganizationGenerator
  TEMP_KEY_PREFIX = '_migrate_tmp_org_'

  # Field type mappings for Familia v2 JSON serialization
  # IMPORTANT: All fields must be declared here. Unknown fields will raise errors.
  FIELD_TYPES = {
    # Core fields (organization.rb)
    'objid' => :string,
    'extid' => :string,
    'display_name' => :string,
    'description' => :string,
    'owner_id' => :string,
    'contact_email' => :string,
    'is_default' => :boolean,
    # Billing fields (features/with_organization_billing.rb)
    'planid' => :string,
    'billing_email' => :string,
    'email_hash' => :string,
    'email_hash_synced_at' => :string,  # ISO-ish format: "2024-02-04@15:00Z"
    'stripe_customer_id' => :string,
    'stripe_subscription_id' => :string,
    'stripe_checkout_email' => :string,
    'subscription_status' => :string,
    'subscription_period_end' => :timestamp,
    # Required fields (features/required_fields.rb)
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields (features/with_migration_fields.rb + organization-specific)
    'v1_identifier' => :string,
    'v1_source_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
    # _original_record removed: v1 data now stored as _original_object hashkey via RESTORE
  }.freeze

  def initialize(input_file:, output_dir:, redis_url:, temp_db:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @redis_url  = redis_url
    @temp_db    = temp_db
    @dry_run    = dry_run
    @redis      = nil

    @stats = {
      records_read: 0,          # Total lines read from JSONL (includes related records)
      customer_objects: 0,      # Customer :object records processed
      organizations_created: 0,
      stripe_customers: 0,
      stripe_subscriptions: 0,
      skipped: 0,
      errors: [],
    }

    @customer_to_org = {}  # customer_objid -> org_objid
    @email_to_org    = {}  # email -> org_objid
    @org_records     = []  # Generated organization JSONL records
  end

  def run
    validate_input_file
    connect_redis unless @dry_run

    puts "Processing: #{@input_file}"
    puts "Output: #{@output_dir}"
    puts 'Mode: DRY RUN' if @dry_run

    process_customers
    write_outputs unless @dry_run

    print_summary
    @stats
  ensure
    cleanup_redis
  end

  private

  def compute_email_hash(email)
    return nil if email.to_s.strip.empty?

    secret = ENV['FEDERATION_SECRET']
    return nil if secret.to_s.empty?

    normalized = email.to_s.downcase.strip
    OpenSSL::HMAC.hexdigest('sha256', secret, normalized)[0...32]
  end

  def validate_input_file
    unless File.exist?(@input_file)
      raise ArgumentError, "Input file not found: #{@input_file}"
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

  def serialize_for_v2(fields)
    fields.each_with_object({}) do |(key, value), result|
      result[key] = if value == '' || value.nil?
                      'null'
                    else
                      ruby_val = parse_to_ruby_type(key, value)
                      Familia::JsonSerializer.dump(ruby_val)
                    end
    end
  end

  # Deserialize a single v2 JSON-encoded value back to Ruby type
  # Used when reading data from upstream transforms that already wrote v2 format
  def deserialize_v2_value(raw_value)
    return nil if raw_value.nil? || raw_value == 'null'
    return raw_value if raw_value.empty?

    Familia::JsonSerializer.parse(raw_value)
  rescue Familia::SerializerError
    raw_value # Fallback for non-JSON values
  end

  # Deserialize all fields in a hash from v2 JSON format
  def deserialize_v2_fields(fields)
    fields.transform_values { |v| deserialize_v2_value(v) }
  end

  def parse_to_ruby_type(key, value)
    field_type = FIELD_TYPES[key.to_s]
    raise ArgumentError, "Unknown field '#{key}' not in FIELD_TYPES - add it to the mapping" unless field_type

    case field_type
    when :string then value.to_s
    when :integer then value.to_i
    when :float, :timestamp then value.to_f  # timestamps stored as floats
    when :boolean then ['true', true].include?(value)
    else
      raise ArgumentError, "Unknown field type '#{field_type}' for field '#{key}'"
    end
  end

  def process_customers
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line, symbolize_names: true)

      # Only process :object records (skip related records like receipts, domains)
      next unless record[:key]&.end_with?(':object')

      # Skip GLOBAL singleton records — not real customers.
      # The renamed key (onetime:GLOBAL_STATS:object) won't match the customer:
      # prefix check in process_customer_record, but skip explicitly for clarity.
      if record[:key]&.include?(':GLOBAL:') || record[:key]&.include?(':GLOBAL_STATS:')
        @stats[:skipped] += 1
        next
      end

      @stats[:customer_objects] += 1
      process_customer_record(record)
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: "JSON parse: #{ex.message}" }
    end
  end

  def process_customer_record(record)
    customer_objid = record[:objid]
    unless customer_objid && !customer_objid.empty?
      @stats[:skipped] += 1
      @stats[:errors] << { key: record[:key], error: 'Missing customer objid' }
      return
    end

    return if @dry_run

    # Decode customer fields from DUMP
    # NOTE: Customer transform writes v2 JSON-serialized values, so we must
    # deserialize them before using for comparisons/lookups
    customer_fields = restore_and_read_hash(record)
    return unless customer_fields

    customer_fields = deserialize_v2_fields(customer_fields)

    # Generate organization record
    org_record = generate_organization(customer_objid, customer_fields, record)
    return unless org_record

    @org_records << org_record
    @customer_to_org[customer_objid] = org_record[:objid]

    # Also track email -> org_objid for downstream scripts (customdomain, etc.)
    email                = org_record[:contact_email]
    @email_to_org[email] = org_record[:objid] if email && !email.empty?

    @stats[:organizations_created] += 1
  end

  def restore_and_read_hash(record)
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.hgetall(temp_key)
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record[:key], error: "Restore failed: #{ex.message}" }
      nil
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end
  end

  def generate_organization(customer_objid, customer_fields, customer_record)
    # Use customer's created timestamp for org (org inherits customer's creation time)
    created = customer_record[:created] || customer_fields['created']&.to_i || Time.now.to_i

    # Generate deterministic org_objid from customer_objid using UUIDv7
    # Uses customer's created timestamp to ensure chronological ordering
    org_objid = generate_org_objid_from_customer(customer_objid, created)
    org_extid = derive_extid_from_uuid(org_objid, prefix: 'on')

    # Extract fields from customer
    email                  = customer_fields['email'] || customer_fields['v1_custid']
    stripe_customer_id     = customer_fields['stripe_customer_id']
    stripe_subscription_id = customer_fields['stripe_subscription_id']
    stripe_checkout_email  = customer_fields['stripe_checkout_email']
    planid                 = customer_fields['planid'] || 'free'

    # Track Stripe stats
    @stats[:stripe_customers]     += 1 if stripe_customer_id&.start_with?('cus_')
    @stats[:stripe_subscriptions] += 1 if stripe_subscription_id&.start_with?('sub_')

    # Build organization fields
    org_fields = {
      'objid' => org_objid,
      'extid' => org_extid,
      'display_name' => derive_display_name(email),
      'description' => nil,
      'owner_id' => customer_objid,
      'contact_email' => email,
      'billing_email' => email,
      'email_hash' => compute_email_hash(email),
      'email_hash_synced_at' => Time.now.utc.strftime('%Y-%m-%d@%H:%MZ'),
      'is_default' => 'true',
      'planid' => planid,
      'created' => created.to_s,
      'updated' => Time.now.to_f.to_s,

      # Billing fields from customer
      'stripe_customer_id' => stripe_customer_id,
      'stripe_subscription_id' => stripe_subscription_id,
      'stripe_checkout_email' => stripe_checkout_email,

      # Migration tracking
      # NOTE: v1 original data is restored as _original_object hashkey by enrich_with_original_record.rb
      'v1_identifier' => customer_record[:key],
      'v1_source_custid' => customer_fields['v1_custid'] || customer_fields['email'],
      'migration_status' => 'completed',
      'migrated_at' => Time.now.to_f.to_s,
    }

    # Remove nil values
    org_fields.compact!

    # Create Redis DUMP for the organization hash
    # Serialize values for Familia v2 JSON format before writing to Redis
    temp_key     = "#{TEMP_KEY_PREFIX}org_#{SecureRandom.hex(8)}"
    serialized   = serialize_for_v2(org_fields)
    org_dump_b64 = begin
      @redis.hmset(temp_key, serialized.to_a.flatten)
      dump_data = @redis.dump(temp_key)
      Base64.strict_encode64(dump_data)
    ensure
      @redis.del(temp_key)
    end

    {
      key: "organization:#{org_objid}:object",
      type: 'hash',
      ttl_ms: -1,  # Organizations don't expire
      db: customer_record[:db],
      dump: org_dump_b64,
      objid: org_objid,
      extid: org_extid,
      owner_id: customer_objid,
      contact_email: email,
      created: created,
    }
  end

  # Generate deterministic org_objid from customer_objid and created timestamp
  # Uses UUIDv7 format with:
  #   - Timestamp from customer's created date (preserves chronological ordering)
  #   - Deterministic "random" bits derived from customer_objid (reproducible)
  def generate_org_objid_from_customer(customer_objid, created_timestamp)
    # Create deterministic seed from customer objid for random portion
    seed = Digest::SHA256.digest("organization:#{customer_objid}")

    # Use customer's created timestamp for UUIDv7 time component
    # This preserves chronological ordering (older customers -> older orgs)
    timestamp_ms = (created_timestamp.to_f * 1000).to_i

    # Encode timestamp as 48-bit hex (12 hex chars)
    hex = timestamp_ms.to_s(16).rjust(12, '0')

    # Use deterministic PRNG seeded from customer objid for "random" portion
    # This ensures re-running the script produces the same objid
    prng       = Random.new(seed.unpack1('Q>'))
    rand_bytes = prng.bytes(10)
    rand_hex   = rand_bytes.unpack1('H*')

    # Construct UUID v7 parts
    time_hi  = hex[0, 8]
    time_mid = hex[8, 4]
    ver_rand = '7' + rand_hex[0, 3]
    variant  = ((rand_hex[4, 2].to_i(16) & 0x3F) | 0x80).to_s(16).rjust(2, '0') + rand_hex[6, 2]
    node     = rand_hex[8, 12]

    "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
  end

  # Derive extid from UUID - matches Familia v2.0.0-pre26
  def derive_extid_from_uuid(uuid_string, prefix:)
    normalized_hex = uuid_string.delete('-')
    seed           = Digest::SHA256.digest(normalized_hex)
    prng           = Random.new(seed.unpack1('Q>'))
    random_bytes   = prng.bytes(16)
    external_part  = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')
    "#{prefix}#{external_part}"
  end

  def derive_display_name(email)
    return 'Default Workspace' unless email && !email.empty?

    # Extract domain part for display name
    domain = email.split('@').last
    if domain
      # Capitalize first letter of domain name
      domain.split('.').first.capitalize + "'s Workspace"
    else
      'Default Workspace'
    end
  end

  def write_outputs
    FileUtils.mkdir_p(@output_dir)

    # Write organization records JSONL
    org_file = File.join(@output_dir, 'organization_transformed.jsonl')
    File.open(org_file, 'w') do |f|
      @org_records.each do |record|
        f.puts(JSON.generate(record))
      end
    end
    puts "Wrote #{@org_records.size} organization records to #{org_file}"

    # Write customer_objid -> org_objid lookup (debug/reference)
    customer_lookup_file = File.join(@output_dir, 'customer_objid_to_org_objid.json')
    File.write(customer_lookup_file, JSON.pretty_generate(@customer_to_org))
    puts "Wrote #{@customer_to_org.size} customer->org mappings to #{customer_lookup_file}"

    # Write email -> org_objid lookup (used by customdomain create_indexes.rb)
    email_lookup_file = File.join(@output_dir, 'email_to_org_objid.json')
    File.write(email_lookup_file, JSON.pretty_generate(@email_to_org))
    puts "Wrote #{@email_to_org.size} email->org mappings to #{email_lookup_file}"
  end

  def print_summary
    puts "\n=== Organization Generation Summary ==="
    puts "Input file: #{@input_file}"
    puts "Records read: #{@stats[:records_read]}"
    puts "Customer objects: #{@stats[:customer_objects]}"
    puts "Organizations created: #{@stats[:organizations_created]}"
    puts "  With Stripe customer: #{@stats[:stripe_customers]}"
    puts "  With Stripe subscription: #{@stats[:stripe_subscriptions]}"
    puts "Skipped: #{@stats[:skipped]}"

    return unless @stats[:errors].any?

    puts "\nErrors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  - #{err}" }
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'customer/customer_transformed.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'organization'),
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/ then options[:input_file] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/ then options[:output_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/ then options[:redis_url]   = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/ then options[:temp_db]      = Regexp.last_match(1).to_i
    when '--dry-run' then options[:dry_run]              = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Generates Organization records from Customer transformed data.
        Organizations are NEW in V2 - one is created per Customer.

        Options:
          --input-file=FILE   Input JSONL (default: data/upgrades/v0.24.0/customer/customer_transformed.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/organization)
          --redis-url=URL     Redis URL for temp operations (env: VALKEY_URL or REDIS_URL)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Parse and count without writing output
          --help              Show this help

        Output files:
          organization_transformed.jsonl       - V2 organization records with DUMP data
          customer_objid_to_org_objid.json   - customer_objid -> org_objid mapping
          email_to_org_objid.json            - email -> org_objid (for customdomain)

        Run this BEFORE create_indexes.rb to establish org_objid values.
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

  generator = OrganizationGenerator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )
  generator.run
end
