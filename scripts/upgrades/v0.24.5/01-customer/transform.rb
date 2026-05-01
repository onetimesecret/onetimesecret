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
#   ruby scripts/upgrades/v0.24.5/01-customer/transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: data/upgrades/v0.24.5/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.5/customer)
#   --redis-url=URL     Redis URL for temporary operations (env: VALKEY_URL or REDIS_URL)
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
require 'uri'

require_relative '../lib/progress'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.5/01-customer/transform.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'

class CustomerTransformer
  TEMP_KEY_PREFIX = '_migrate_tmp_transform_'

  # Counter fields that become standalone Redis String keys in v2 (Familia class_counter)
  COUNTER_FIELDS = %w[secrets_created secrets_burned secrets_shared emails_sent].freeze

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
    'migration_comment' => :string,
    'migrated_at' => :timestamp,
    # _original_record removed: v1 data now stored as _original_object hashkey via RESTORE
  }.freeze

  # Sentinel returned by parse_to_ruby_type when a field has no FIELD_TYPES
  # mapping. Caller drops the field from the v2 hash and records the field name
  # in a migration_comment instead of failing the entire customer record.
  UNKNOWN_FIELD = :__unknown_field__

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
      externalized_counters: 0,
      renamed_related: Hash.new(0),
      skipped_customers: 0,
      skipped_non_customer_keys: [],  # Keys that don't match customer:{id}:{suffix} pattern
      global_record_found: false,
      global_counters: {},            # Counter values from GLOBAL record
      tallied_counters: Hash.new(0),  # Tallied from individual customers
      errors: {
        schema_gaps: [],          # unknown fields encountered (recorded in migration_comment)
        orphans: [],              # custid/email present in index but no :object record
        data_corruption: [],      # malformed records, JSON parse errors, restore failures
        processing_failures: [],  # everything else (rescue StandardError)
      },
    }
  end

  def run
    validate_input_file
    connect_redis unless @dry_run

    # 1. Group records by customer ID from the dump file
    records_by_customer = group_records_by_customer

    # 2. Process each customer group to generate V2 records
    v2_records = []
    process_progress = Upgrade::ProgressReporter.new('customers transformed')
    records_by_customer.each do |custid, records|
      process_progress.tick
      v2_records.concat(process_customer(custid, records))
    rescue StandardError => ex
      # Schema gaps are now soft-failed inside serialize_for_v2; reaching this
      # rescue with an "Unknown field" message would indicate a regression.
      bucket = ex.message.start_with?('Unknown field') ? :schema_gaps : :processing_failures
      @stats[:errors][bucket] << { customer: redact_email(custid), error: "Processing failed: #{ex.message}" }
    end
    process_progress.finish

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
    uri      = URI.parse(@redis_url)
    uri.path = "/#{@temp_db}"
    @redis   = Redis.new(url: uri.to_s)
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

  # Pipelining is opt-in via OTS_MIGRATION_PIPELINE. Any truthy value enables
  # within-customer pipelining of RESTORE+HGETALL, HMSET+DUMP, and the
  # counter SET+DUMP fan-out. DEL stays in `ensure` blocks unchanged so temp
  # keys are cleaned up on every path. Memoized; ENV is read once.
  def pipeline_enabled?
    return @pipeline_enabled if defined?(@pipeline_enabled)
    raw = ENV['OTS_MIGRATION_PIPELINE'].to_s.strip.downcase
    @pipeline_enabled = !(raw.empty? || %w[0 false no off].include?(raw))
  end

  def group_records_by_customer
    puts "Reading and grouping records from #{@input_file}..."
    groups   = Hash.new { |h, k| h[k] = [] }
    progress = Upgrade::ProgressReporter.new('records read')

    File.foreach(@input_file) do |line|
      progress.tick
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
      @stats[:errors][:data_corruption] << { line: @stats[:v1_records_read], error: "JSON parse error: #{ex.message}" }
    end
    progress.finish
    puts "Found #{@stats[:v1_records_read]} records for #{groups.size} distinct customers."
    groups
  end

  def process_customer(custid, records)
    # Handle GLOBAL singleton: rename and pass through without customer transformation
    if custid == 'GLOBAL'
      return process_global_record(records)
    end

    object_record = records.find { |r| r[:key].end_with?(':object') }
    unless object_record
      @stats[:skipped_customers] += 1
      @stats[:errors][:orphans] << { customer: redact_email(custid), error: 'No :object record found.' }
      return []
    end

    return [] if @dry_run # Stop here for dry run after counting

    v1_fields    = restore_and_read_hash(object_record)
    objid, extid = resolve_identifiers(object_record, v1_fields)

    unless objid && !objid.empty?
      @stats[:skipped_customers] += 1
      # After Fix 4 (enricher synthesizes missing `created`), this bucket should
      # mostly stay empty; remaining hits indicate dump corruption.
      @stats[:errors][:data_corruption] << { customer: redact_email(custid), error: 'Could not resolve objid.' }
      return []
    end

    # Tally counter fields before removing them from the hash
    tally_counters(v1_fields)

    # Transform the main object (counters externalized, not included in v2 hash)
    v2_object_record = transform_customer_object(object_record, v1_fields, objid, extid)

    # Externalize counter fields as standalone JSONL records
    counter_records = externalize_counters(v1_fields, objid, object_record)

    # Rename related records
    related_records    = records.reject { |r| r[:key].end_with?(':object') }
    v2_related_records = rename_related_records(related_records, objid)

    @stats[:customers_processed] += 1
    [v2_object_record].concat(counter_records).concat(v2_related_records)
  end

  # Process the GLOBAL singleton record: rename key, decode counters for summary,
  # and write through with new key name (preserving the original dump data).
  def process_global_record(records)
    object_record = records.find { |r| r[:key].end_with?(':object') }
    unless object_record
      @stats[:errors][:orphans] << { customer: 'GLOBAL', error: 'No :object record found.' }
      return []
    end

    @stats[:global_record_found] = true

    return [] if @dry_run

    # Decode GLOBAL hash to extract counter values for summary comparison
    begin
      global_fields = restore_and_read_hash(object_record)
      COUNTER_FIELDS.each do |field|
        @stats[:global_counters][field] = global_fields[field].to_i
      end
    rescue StandardError => ex
      @stats[:errors][:data_corruption] << { customer: 'GLOBAL', error: "Failed to decode counters: #{ex.message}" }
    end

    # Write through with renamed key, preserving original dump data
    renamed_record = object_record.dup
    renamed_record[:key] = 'onetime:GLOBAL_STATS:object'

    [renamed_record]
  end

  # Tally counter fields from an individual customer for summary comparison
  def tally_counters(v1_fields)
    COUNTER_FIELDS.each do |field|
      value = v1_fields[field].to_i
      @stats[:tallied_counters][field] += value if value > 0
    end
  end

  # Extract counter fields from customer hash and emit as standalone JSONL records.
  # In v2, Familia class_counter fields are Redis String keys, not hash fields.
  def externalize_counters(v1_fields, objid, original_record)
    pending = []
    COUNTER_FIELDS.each do |field|
      value = v1_fields[field].to_i
      next if value.zero?

      pending << [field, value, "#{TEMP_KEY_PREFIX}ctr_#{SecureRandom.hex(4)}"]
    end
    return [] if pending.empty?

    if pipeline_enabled?
      # Pipeline all SET+DUMP pairs for this customer's counters in one RTT,
      # then DEL the temp keys in one RTT. For a customer with N non-zero
      # counters this collapses 3N round trips into 2. The DEL pipeline lives
      # in `ensure` so a transient failure mid-SET+DUMP does not leak temp keys
      # for `cleanup_redis` to mop up later.
      begin
        results = @redis.pipelined do |pipe|
          pending.each do |_field, value, temp_key|
            pipe.set(temp_key, value)
            pipe.dump(temp_key)
          end
        end
        pending.each_with_index.map do |(field, value, _temp_key), i|
          dump_data = results[(i * 2) + 1]
          @stats[:externalized_counters] += 1
          {
            key: "customer:#{objid}:#{field}",
            type: 'string',
            ttl_ms: -1,
            db: original_record[:db],
            dump: Base64.strict_encode64(dump_data),
            # Plain-integer counter value for create_indexes.rb's
            # accumulate_externalized_counters tally. load_keys.rb only reads
            # :key/:dump/:ttl_ms (see prepare_record), so this extra key is
            # invisible to the loader.
            value: value,
          }
        end
      ensure
        @redis.pipelined { |pipe| pending.each { |_, _, tk| pipe.del(tk) } }
      end
    else
      pending.map do |field, value, temp_key|
        dump_b64 = begin
          @redis.set(temp_key, value)
          dump_data = @redis.dump(temp_key)
          Base64.strict_encode64(dump_data)
        ensure
          @redis.del(temp_key)
        end

        @stats[:externalized_counters] += 1
        {
          key: "customer:#{objid}:#{field}",
          type: 'string',
          ttl_ms: -1,
          db: original_record[:db],
          dump: dump_b64,
          # Plain-integer counter value for create_indexes.rb's
          # accumulate_externalized_counters tally. load_keys.rb only reads
          # :key/:dump/:ttl_ms (see prepare_record), so this extra key is
          # invisible to the loader.
          value: value,
        }
      end
    end
  end

  def transform_customer_object(v1_record, v1_fields, objid, extid)
    v2_fields = v1_fields.dup

    # Remove counter fields — they are externalized as standalone Redis String keys
    COUNTER_FIELDS.each { |f| v2_fields.delete(f) }

    # Ensure the canonical identifiers are set in the hash
    v2_fields['objid'] = objid
    v2_fields['extid'] = extid if extid && !extid.empty?

    # custid (email) -> custid (objid), preserving original
    if v2_fields['custid'] != objid
      v2_fields['v1_custid'] = v2_fields['custid']
    end
    v2_fields['custid'] = objid

    # Add migration tracking fields.
    # NOTE: v1 original data is restored as _original_object hashkey by enrich_with_original_record.rb
    v2_fields['v1_identifier'] = v1_record[:key]
    v2_fields['migrated_at']   = Time.now.to_f.to_s

    # migration_status precedence: enricher-supplied value (e.g.,
    # 'created_synthesized' from enrich_with_identifiers.rb) wins; otherwise
    # default to 'completed'. The enriched value rides on the JSONL record's
    # top-level keys, not inside the binary dump, so we read v1_record here.
    enricher_status = v1_record[:migration_status]
    v2_fields['migration_status'] = if enricher_status && !enricher_status.to_s.empty?
                                      enricher_status.to_s
                                    else
                                      'completed'
                                    end

    # migration_comment seed from the enricher (e.g., 'created_synthesized').
    # serialize_for_v2 will append any dropped-field notes and JSON-encode once.
    enricher_comment = v1_record[:migration_comment]
    seed_comment     = enricher_comment.to_s.empty? ? nil : enricher_comment.to_s

    # Create new dump for the transformed hash with Familia v2 JSON serialization
    temp_key    = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    v2_dump_b64 = begin
      # Serialize field values to JSON for Familia v2 compatibility.
      # Unknown fields are dropped and recorded in migration_comment rather
      # than failing the whole record.
      v2_serialized = serialize_for_v2(v2_fields, seed_comment: seed_comment)
      # NOTE: hmset is deprecated, but redis-rb gem maps it to HMSET for older redis-server versions
      # For modern Redis, this would be `hset(temp_key, v2_serialized)`
      hmset_args = v2_serialized.to_a.flatten
      dump_data =
        if pipeline_enabled?
          _hmset_result, dumped = @redis.pipelined do |pipe|
            pipe.hmset(temp_key, hmset_args)
            pipe.dump(temp_key)
          end
          dumped
        else
          @redis.hmset(temp_key, hmset_args)
          @redis.dump(temp_key)
        end
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
      created: v1_record[:created] || v1_fields['created']&.to_i,
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
      if pipeline_enabled?
        # RESTORE then HGETALL on the same key in a single round trip; Redis
        # processes pipelined commands in order, so HGETALL sees the just-
        # restored hash. Saves one RTT per customer object decode.
        _restore_result, fields = @redis.pipelined do |pipe|
          pipe.restore(temp_key, 0, dump_data, replace: true)
          pipe.hgetall(temp_key)
        end
        fields
      else
        @redis.restore(temp_key, 0, dump_data, replace: true)
        @redis.hgetall(temp_key)
      end
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

  # Serialize hash fields to JSON format for Familia v2 compatibility.
  #
  # Unknown fields (not declared in FIELD_TYPES) are dropped from the v2 hash
  # AND recorded in `migration_comment` so the customer record is preserved
  # while the schema-drift signal is captured. This downgrades a previously
  # fatal error into a soft-fail that the operator can audit post-migration.
  #
  # @param fields [Hash<String, String>] v1 hash field values (string=>string)
  # @param seed_comment [String, nil] Existing migration_comment (e.g.,
  #   'created_synthesized' from the enricher) to preserve and extend.
  # @return [Hash<String, String>] serialized fields ready for HMSET
  def serialize_for_v2(fields, seed_comment: nil)
    dropped = []
    result  = {}

    fields.each do |key, value|
      if value == ''
        result[key] = 'null'
        next
      end

      ruby_val = parse_to_ruby_type(key, value)
      if ruby_val == UNKNOWN_FIELD
        dropped << key.to_s
        # Bucket per-record (one stat entry per dropped field name) so the
        # summary can show the schema-gap surface area.
        @stats[:errors][:schema_gaps] << { field: key.to_s }
        next
      end

      result[key] = Familia::JsonSerializer.dump(ruby_val)
    end

    # Compose final migration_comment: pre-existing v1 comment + enricher seed
    # + dropped-field note, joined with ';'. All are optional. Encode once at
    # the end so we don't double-encode any pre-existing comment value already
    # in `fields` (the loop above wrote the encoded form into result, which we
    # now overwrite with the composed value below).
    #
    # We protect against re-runs over already-migrated data by preserving any
    # comment present in v1; we also avoid duplicating seed_comment if it has
    # already been appended on a prior pass.
    existing = fields['migration_comment'].to_s
    parts    = []
    parts << existing if !existing.empty? && existing != seed_comment.to_s
    parts << seed_comment if seed_comment && !existing.split(';').include?(seed_comment)
    parts << "dropped_fields=#{dropped.join(',')}" if dropped.any?

    if parts.any?
      result['migration_comment'] = Familia::JsonSerializer.dump(parts.join(';'))
    end

    result
  end

  # Convert string value to appropriate Ruby type based on FIELD_TYPES mapping.
  # Returns UNKNOWN_FIELD sentinel for fields without a declared type so the
  # caller can drop the field rather than fail the entire customer record.
  def parse_to_ruby_type(key, value)
    field_type = FIELD_TYPES[key.to_s]
    return UNKNOWN_FIELD unless field_type

    case field_type
    when :string then value
    when :integer then value.to_i
    when :float, :timestamp then value.to_f
    when :boolean then value == 'true'
    else
      raise ArgumentError, "Unknown field type '#{field_type}' for field '#{key}'"
    end
  end

  def redact_email(email)
    return '***' unless email.is_a?(String) && email.include?('@')

    local, domain = email.split('@', 2)
    "#{local[0..2]}***@#{domain.sub(/\A[^.]+/, '***')}"
  end

  def write_output(records)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'customer_transformed.jsonl')
    temp_file   = "#{output_file}.tmp"

    begin
      File.open(temp_file, 'w') do |f|
        records.each do |record|
          f.puts(JSON.generate(record))
          @stats[:v2_records_written] += 1
        end
      end
      FileUtils.mv(temp_file, output_file)
    rescue StandardError
      # Ensure no partial output is promoted to the final filename.
      # Any prior successful run's output remains at output_file.
      FileUtils.rm_f(temp_file)
      raise
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
    puts "  Externalized counters: #{@stats[:externalized_counters]}"
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

    # GLOBAL vs tallied counter comparison
    if @stats[:global_record_found]
      puts 'GLOBAL vs Tallied Counter Comparison:'
      puts '  (GLOBAL = value from customer:GLOBAL:object, Tallied = sum of individual customers)'
      COUNTER_FIELDS.each do |field|
        global_val  = @stats[:global_counters][field] || 0
        tallied_val = @stats[:tallied_counters][field] || 0
        match       = global_val == tallied_val ? 'OK' : 'MISMATCH'
        puts "  #{field}: GLOBAL=#{global_val}, Tallied=#{tallied_val} [#{match}]"
      end
    else
      puts 'GLOBAL record: not found in input'
    end
    puts

    print_error_summary
  end

  def print_error_summary
    buckets = @stats[:errors]
    total   = buckets.values.sum(&:size)
    return if total.zero?

    puts "Errors (#{total}):"
    puts "  Schema gaps:     #{buckets[:schema_gaps].size} (unknown fields encountered, see migration_comment on records)"
    puts "  Orphans:         #{buckets[:orphans].size} (benign - index entries without :object records)"
    puts "  Data corruption: #{buckets[:data_corruption].size}"
    puts "  Processing:      #{buckets[:processing_failures].size}"

    # Show a small sample per non-empty bucket for triage.
    buckets.each do |name, list|
      next if list.empty?

      puts "  [#{name}] sample:"
      list.first(5).each { |err| puts "    - #{err}" }
      puts "    ... and #{list.size - 5} more" if list.size > 5
    end
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'customer/customer_dump.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'customer'),
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

        Transforms customer data from V1 dump to V2 format.

        Options:
          --input-file=FILE   Input JSONL dump (default: data/upgrades/v0.24.5/customer/customer_dump.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.5/customer)
          --redis-url=URL     Redis URL for temp operations (env: VALKEY_URL or REDIS_URL)
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
