#!/usr/bin/env ruby
# frozen_string_literal: true

# Transforms and renames customer data from a V1 dump file to V2 format.
#
# Reads a JSONL dump file, groups records by customer, and applies transformations
# based on the migration spec. This includes:
# - Renaming keys from email-based custid to objid.
# - Transforming the main customer object hash.
# - Creating a new Redis DUMP for transformed objects.
# - Outputting a new JSONL file with the V2 records.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/01-customer/transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: results/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: results/customer)
#   --redis-url=URL     Redis URL for temporary operations (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temporary database for restore/dump (default: 15)
#   --dry-run           Parse and count without writing output
#
# Output: customer_transformed.jsonl with V2 records in Redis DUMP format.

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'familia'

class CustomerTransformer
  TEMP_KEY_PREFIX = '_migrate_tmp_transform_'

  # Field type mappings for Familia v2 JSON serialization
  # IMPORTANT: All fields must be declared here. Unknown fields will raise errors.
  FIELD_TYPES = {
    # Core fields (customer.rb)
    'custid' => :string,
    'email' => :string,
    'key' => :string,
    'locale' => :string,
    'planid' => :string,
    'last_password_update' => :timestamp,
    'last_login' => :timestamp,
    'notify_on_reveal' => :boolean,
    'objid' => :string,
    'extid' => :string,
    # Status fields (features/status.rb)
    'role' => :string,
    'joined' => :timestamp,
    'verified' => :boolean,
    'verified_by' => :string,
    # Deprecated fields (features/deprecated_fields.rb)
    'sessid' => :string,
    'apitoken' => :string,
    'contributor' => :string,
    'stripe_customer_id' => :string,
    'stripe_subscription_id' => :string,
    'stripe_checkout_email' => :string,
    # Counter fields (features/counter_fields.rb)
    'secrets_created' => :integer,
    'secrets_burned' => :integer,
    'secrets_shared' => :integer,
    'emails_sent' => :integer,
    # Legacy encrypted fields (features/legacy_encrypted_fields.rb)
    'passphrase' => :string,
    'passphrase_encryption' => :string,
    'value' => :string,
    'value_encryption' => :string,
    # Required fields (features/required_fields.rb)
    'created' => :timestamp,
    'updated' => :timestamp,
    # Migration fields (features/with_migration_fields.rb)
    'v1_identifier' => :string,
    'v1_custid' => :string,
    'migration_status' => :string,
    'migrated_at' => :timestamp,
    '_original_record' => :string,  # jsonkey - already JSON-serialized
  }.freeze

  def initialize(input_file:, output_dir:, redis_url:, temp_db:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @redis_url  = redis_url
    @temp_db    = temp_db
    @dry_run    = dry_run
    @redis      = nil

    @stats = {
      customers_processed: 0,
      v1_records_read: 0,
      v2_records_written: 0,
      transformed_objects: 0,
      renamed_related: Hash.new(0),
      skipped_customers: 0,
      skipped_non_customer_keys: [],  # Keys that don't match customer:{id}:{suffix} pattern
      errors: [],
    }
  end

  def run
    validate_input_file
    connect_redis unless @dry_run

    # 1. Group records by customer ID from the dump file
    records_by_customer = group_records_by_customer

    # 2. Process each customer group to generate V2 records
    v2_records = []
    records_by_customer.each do |custid, records|
      v2_records.concat(process_customer(custid, records))
    rescue StandardError => ex
      @stats[:errors] << { customer: custid, error: "Processing failed: #{ex.message}" }
    end

    # 3. Write the transformed records to the output file
    write_output(v2_records) unless @dry_run

    print_summary
  ensure
    cleanup_redis
  end

  private

  def validate_input_file
    unless File.exist?(@input_file)
      raise ArgumentError, "Input file not found: #{@input_file}"
    end
  end

  def connect_redis
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
    @redis.ping # Verify connection
  end

  def cleanup_redis
    return unless @redis

    # Clean up any temporary keys
    cursor = '0'
    loop do
      cursor, keys = @redis.scan(cursor, match: "#{TEMP_KEY_PREFIX}*", count: 100)
      @redis.del(*keys) unless keys.empty?
      break if cursor == '0'
    end
    @redis.close
  end

  def group_records_by_customer
    puts "Reading and grouping records from #{@input_file}..."
    groups = Hash.new { |h, k| h[k] = [] }

    File.foreach(@input_file) do |line|
      @stats[:v1_records_read] += 1
      record                    = JSON.parse(line, symbolize_names: true)

      key_parts = record[:key].split(':')

      # Track keys that don't match customer:{id}:{suffix} pattern
      # These are global keys (like onetime:customer) or malformed entries
      unless key_parts.first == 'customer' && key_parts.size > 2
        @stats[:skipped_non_customer_keys] << record[:key]
        next
      end

      custid = key_parts[1]
      groups[custid] << record
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:v1_records_read], error: "JSON parse error: #{ex.message}" }
    end
    puts "Found #{@stats[:v1_records_read]} records for #{groups.size} distinct customers."
    groups
  end

  def process_customer(custid, records)
    object_record = records.find { |r| r[:key].end_with?(':object') }
    unless object_record
      @stats[:skipped_customers] += 1
      @stats[:errors] << { customer: custid, error: 'No :object record found.' }
      return []
    end

    return [] if @dry_run # Stop here for dry run after counting

    v1_fields    = restore_and_read_hash(object_record)
    objid, extid = resolve_identifiers(object_record, v1_fields)

    unless objid && !objid.empty?
      @stats[:skipped_customers] += 1
      @stats[:errors] << { customer: custid, error: 'Could not resolve objid.' }
      return []
    end

    # Transform the main object
    v2_object_record = transform_customer_object(object_record, v1_fields, objid, extid)

    # Rename related records
    related_records    = records.reject { |r| r[:key].end_with?(':object') }
    v2_related_records = rename_related_records(related_records, objid)

    @stats[:customers_processed] += 1
    [v2_object_record].concat(v2_related_records)
  end

  def transform_customer_object(v1_record, v1_fields, objid, extid)
    v2_fields = v1_fields.dup

    # Ensure the canonical identifiers are set in the hash
    v2_fields['objid'] = objid
    v2_fields['extid'] = extid if extid && !extid.empty?

    # custid (email) -> custid (objid), preserving original
    if v2_fields['custid'] != objid
      v2_fields['v1_custid'] = v2_fields['custid']
    end
    v2_fields['custid'] = objid

    # Add migration tracking fields
    # NOTE: _original_record is added by enrich_with_original_record.rb
    v2_fields['v1_identifier']    = v1_record[:key]
    v2_fields['migration_status'] = 'completed'
    v2_fields['migrated_at']      = Time.now.to_f.to_s

    # Create new dump for the transformed hash with Familia v2 JSON serialization
    temp_key    = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    v2_dump_b64 = begin
      # Serialize field values to JSON for Familia v2 compatibility
      v2_serialized = serialize_for_v2(v2_fields)
      # NOTE: hmset is deprecated, but redis-rb gem maps it to HMSET for older redis-server versions
      # For modern Redis, this would be `hset(temp_key, v2_serialized)`
      @redis.hmset(temp_key, v2_serialized.to_a.flatten)
      dump_data     = @redis.dump(temp_key)
      Base64.strict_encode64(dump_data)
    ensure
      @redis.del(temp_key)
    end

    @stats[:transformed_objects] += 1

    {
      key: "customer:#{objid}:object",
      type: 'hash',
      ttl_ms: v1_record[:ttl_ms],
      db: v1_record[:db],
      dump: v2_dump_b64,
      objid: objid,
      extid: v2_fields['extid'],
    }
  end

  def rename_related_records(records, objid)
    records.map do |record|
      v2_record = record.dup
      key_parts = record[:key].split(':') # customer:{custid}:{type}
      data_type = key_parts.last

      new_key = if data_type == 'metadata'
                  @stats[:renamed_related]['receipts'] += 1
                  "customer:#{objid}:receipts"
                else
                  @stats[:renamed_related][data_type] += 1
                  "customer:#{objid}:#{data_type}"
                end

      v2_record[:key] = new_key
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
    # Prefer identifiers from the enriched JSONL record, fall back to hash fields
    objid   = record[:objid]
    objid ||= fields['objid']
    # DO NOT fall back to custid (email). The objid must be a UUIDv7
    # generated by enrich_with_identifiers.rb.

    extid   = record[:extid]
    extid ||= fields['extid']
    [objid, extid]
  end

  # Serialize hash fields to JSON format for Familia v2 compatibility
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

  # Convert string value to appropriate Ruby type based on FIELD_TYPES mapping
  def parse_to_ruby_type(key, value)
    field_type = FIELD_TYPES[key.to_s]
    raise ArgumentError, "Unknown field '#{key}' not in FIELD_TYPES - add it to the mapping" unless field_type

    case field_type
    when :string then value
    when :integer then value.to_i
    when :float, :timestamp then value.to_f
    when :boolean then value == 'true'
    else
      raise ArgumentError, "Unknown field type '#{field_type}' for field '#{key}'"
    end
  end

  def write_output(records)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'customer_transformed.jsonl')

    File.open(output_file, 'w') do |f|
      records.each do |record|
        f.puts(JSON.generate(record))
        @stats[:v2_records_written] += 1
      end
    end
    puts "Wrote #{@stats[:v2_records_written]} transformed records to #{output_file}"
  end

  def print_summary
    puts "\n=== Customer Transformation Summary ==="
    puts "Input file: #{@input_file}"
    puts "V1 records read: #{@stats[:v1_records_read]}"
    puts "Customers processed: #{@stats[:customers_processed]}"
    puts "Customers skipped: #{@stats[:skipped_customers]}"
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

    # Show keys that were skipped (don't match customer:{id}:{suffix} pattern)
    skipped_keys = @stats[:skipped_non_customer_keys]
    if skipped_keys.any?
      puts "Non-customer keys skipped: #{skipped_keys.size}"
      skipped_keys.each { |key| puts "  - #{key}" }
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
    input_file: 'results/customer/customer_dump.jsonl',
    output_dir: 'results/customer',
    redis_url: 'redis://127.0.0.1:6379',
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

        Transforms customer data from V1 dump to V2 format.

        Options:
          --input-file=FILE   Input JSONL dump (default: results/customer/customer_dump.jsonl)
          --output-dir=DIR    Output directory (default: results/customer)
          --redis-url=URL     Redis URL for temp operations (default: redis://127.0.0.1:6379)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Parse and count without writing output
          --help              Show this help

        Output file: customer_transformed.jsonl
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

  transformer = CustomerTransformer.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )
  transformer.run
end
