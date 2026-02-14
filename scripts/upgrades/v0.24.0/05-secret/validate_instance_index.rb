#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that secret:instances members match secret:{objid}:object keys
# and that key fields are present in transformed records.
#
# This script cross-references:
# 1. secret_indexes.jsonl - ZADD commands for secret:instances (objid members)
# 2. secret_transformed.jsonl - transformed secret objects with V2 keys
#
# Validations:
# 1. Each objid in secret:instances has a matching secret:{objid}:object record
# 2. Each secret:{objid}:object record has an entry in secret:instances
# 3. Required fields must be present in every record (FAIL if missing)
# 4. Expected fields should be present but may be conditional (WARN if missing)
# 5. All observed fields are reported with presence rates for full visibility
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/05-secret/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/secret/secret_transformed.jsonl)
#   --indexes-file=FILE      Indexes JSONL (default: data/upgrades/v0.24.0/secret/secret_indexes.jsonl)
#   --redis-url=URL          Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N              Temp database number (default: 15)
#   --help                   Show this help

require 'json'
require 'base64'
require 'redis'
require 'securerandom'
require 'uri'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class SecretInstanceIndexValidator
  TEMP_KEY_PREFIX = '_validate_secret_'

  # Fields that MUST be present in every transformed record.
  # Missing any of these is a validation failure.
  REQUIRED_FIELDS = %w[
    objid owner_id state created migration_status migrated_at
    v1_key v1_identifier
  ].freeze

  # Fields that SHOULD be present but may be legitimately missing
  # in some records (conditional on V1 data). Missing these is a warning.
  EXPECTED_FIELDS = %w[
    receipt_identifier receipt_shortid lifespan updated
  ].freeze

  # Known deprecated/migration fields that are acceptable to see.
  # Presence is informational only (no warning or error).
  KNOWN_OPTIONAL_FIELDS = %w[
    ciphertext value value_encryption passphrase passphrase_encryption
    share_domain verification truncated secret_key metadata_key
    v1_custid v1_original_size custid key
    previewed revealed viewed received
    org_id domain_id
  ].freeze

  def initialize(transformed_file:, indexes_file:, redis_url:, temp_db: 15)
    @transformed_file = transformed_file
    @indexes_file     = indexes_file
    @redis_url        = redis_url
    @temp_db          = temp_db
    @redis            = nil

    @stats = {
      index_members: 0,
      transformed_objects: 0,
      matches: 0,
      in_index_not_in_objects: [],
      in_objects_not_in_index: [],
      # Tracks presence of every field observed across all records
      field_presence: Hash.new { |h, k| h[k] = { present: 0, missing: 0, missing_objids: [] } },
      # Set of all field names observed in any record
      all_observed_fields: Set.new,
      errors: [],
    }
  end

  def run
    validate_input_files
    connect_redis

    # 1. Extract objids from secret:instances index commands
    index_objids = extract_index_objids
    puts "Found #{index_objids.size} members in secret:instances index"

    # 2. Extract objids and fields from transformed secret objects
    transformed_objects = extract_transformed_objects
    puts "Found #{transformed_objects.size} secret objects in transformed file"
    puts

    # 3. Cross-reference: index vs objects
    cross_reference(index_objids, transformed_objects)

    # 4. Full field audit by decoding dump blobs
    audit_fields(transformed_objects)

    # 5. Report
    print_report

    # Success if no orphaned entries and no required field failures
    success = @stats[:in_index_not_in_objects].empty? &&
              @stats[:in_objects_not_in_index].empty? &&
              REQUIRED_FIELDS.none? { |f| @stats[:field_presence][f][:missing] > 0 }
    success
  ensure
    cleanup_redis
  end

  private

  def validate_input_files
    unless File.exist?(@transformed_file)
      raise ArgumentError, "Transformed file not found: #{@transformed_file}\nRun transform.rb first."
    end
    unless File.exist?(@indexes_file)
      raise ArgumentError, "Indexes file not found: #{@indexes_file}\nRun create_indexes.rb first."
    end
    raise ArgumentError, 'Redis URL required for dump blob decoding (set VALKEY_URL or REDIS_URL, or use --redis-url)' unless @redis_url
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

  def extract_index_objids
    objids = Set.new

    File.foreach(@indexes_file) do |line|
      record = JSON.parse(line)

      # Only look at ZADD commands for secret:instances
      next unless record['command'] == 'ZADD' && record['key'] == 'secret:instances'

      # args: [score, objid]
      objid = record['args'][1]
      objids.add(objid) if objid
      @stats[:index_members] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'indexes', error: "JSON parse error: #{ex.message}" }
    end

    objids
  end

  def extract_transformed_objects
    objects = {}

    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line, symbolize_names: false)
      key    = record['key']

      # Pattern: secret:{objid}:object
      next unless key&.match?(/^secret:[^:]+:object$/)

      objid = record['objid']
      next unless objid

      objects[objid] = record
      @stats[:transformed_objects] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end

    objects
  end

  def cross_reference(index_objids, transformed_objects)
    object_objids = Set.new(transformed_objects.keys)

    # Members in index but not in transformed objects
    orphaned_index = index_objids - object_objids
    @stats[:in_index_not_in_objects] = orphaned_index.to_a

    # Objects in transformed but not in index
    orphaned_objects = object_objids - index_objids
    @stats[:in_objects_not_in_index] = orphaned_objects.to_a

    # Count matches
    @stats[:matches] = (index_objids & object_objids).size
  end

  # Decode the dump blob via Redis RESTORE + HGETALL to inspect hash fields
  def decode_hash_fields(record)
    dump_b64 = record['dump']
    return {} unless dump_b64

    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(dump_b64)
    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.hgetall(temp_key)
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record['key'], error: "RESTORE failed: #{ex.message}" }
      {}
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end
  end

  # Audit all fields in every record: track presence for required/expected
  # fields and discover any fields not in the known lists.
  def audit_fields(transformed_objects)
    all_check_fields = REQUIRED_FIELDS + EXPECTED_FIELDS

    transformed_objects.each do |objid, record|
      hash_fields = decode_hash_fields(record)

      # Track every field name we see
      hash_fields.each_key { |f| @stats[:all_observed_fields].add(f) }

      # Check required + expected fields
      all_check_fields.each do |field|
        value = hash_fields[field]
        check = @stats[:field_presence][field]

        if value && !value.to_s.empty?
          check[:present] += 1
        else
          check[:missing] += 1
          check[:missing_objids] << objid if check[:missing_objids].size < 20
        end
      end

      # Also track presence for any observed field not in required/expected
      hash_fields.each do |field, value|
        next if all_check_fields.include?(field)

        check = @stats[:field_presence][field]
        if value && !value.to_s.empty?
          check[:present] += 1
        else
          check[:missing] += 1
          check[:missing_objids] << objid if check[:missing_objids].size < 20
        end
      end
    end
  end

  def format_field_line(field, check, total)
    pct = total > 0 ? (check[:present] * 100.0 / total).round(1) : 0
    "#{field}: #{check[:present]}/#{total} present (#{pct}%)"
  end

  def print_missing_details(check)
    return unless check[:missing] > 0 && check[:missing_objids].any?

    puts "    Missing in: #{check[:missing_objids].first(5).join(', ')}"
    puts "    ... and #{check[:missing_objids].size - 5} more" if check[:missing_objids].size > 5
  end

  def print_report
    total = @stats[:transformed_objects]

    puts '=== Secret Instance Index Validation ==='
    puts "Index members (secret:instances): #{@stats[:index_members]}"
    puts "Transformed objects: #{total}"
    puts "Matched: #{@stats[:matches]}"
    puts

    if @stats[:in_index_not_in_objects].any?
      count = @stats[:in_index_not_in_objects].size
      puts "WARNING: #{count} objids in index but missing from transformed objects:"
      @stats[:in_index_not_in_objects].first(10).each { |id| puts "  - #{id}" }
      puts "  ... and #{count - 10} more" if count > 10
      puts
    end

    if @stats[:in_objects_not_in_index].any?
      count = @stats[:in_objects_not_in_index].size
      puts "WARNING: #{count} objids in transformed objects but missing from index:"
      @stats[:in_objects_not_in_index].first(10).each { |id| puts "  - #{id}" }
      puts "  ... and #{count - 10} more" if count > 10
      puts
    end

    if @stats[:in_index_not_in_objects].empty? && @stats[:in_objects_not_in_index].empty?
      puts 'OK: All index members match transformed objects (1:1 correspondence).'
      puts
    end

    # --- Required fields (FAIL if any missing) ---
    puts '=== Required Field Checks ==='
    required_ok = true
    REQUIRED_FIELDS.each do |field|
      check  = @stats[:field_presence][field]
      status = check[:missing] > 0 ? 'FAIL' : 'OK'
      required_ok = false if check[:missing] > 0
      puts "  #{format_field_line(field, check, total)} [#{status}]"
      print_missing_details(check)
    end
    puts
    puts(required_ok ? '  All required fields present.' : '  FAILURES detected in required fields.')
    puts

    # --- Expected fields (WARN if missing) ---
    puts '=== Expected Field Checks ==='
    EXPECTED_FIELDS.each do |field|
      check  = @stats[:field_presence][field]
      status = check[:missing] > 0 ? 'WARN' : 'OK'
      puts "  #{format_field_line(field, check, total)} [#{status}]"
      print_missing_details(check)
    end
    puts

    # --- All other observed fields (informational) ---
    known_fields = Set.new(REQUIRED_FIELDS + EXPECTED_FIELDS + KNOWN_OPTIONAL_FIELDS)
    other_fields = @stats[:all_observed_fields].select { |f| !REQUIRED_FIELDS.include?(f) && !EXPECTED_FIELDS.include?(f) }

    if other_fields.any?
      puts '=== Additional Observed Fields ==='
      # Separate known optional from truly unexpected
      known_others   = other_fields.select { |f| KNOWN_OPTIONAL_FIELDS.include?(f) }.sort
      unknown_others = other_fields.reject { |f| KNOWN_OPTIONAL_FIELDS.include?(f) }.sort

      known_others.each do |field|
        check = @stats[:field_presence][field]
        puts "  #{format_field_line(field, check, total)} [optional]"
      end

      if unknown_others.any?
        puts
        puts '  Unexpected fields (not in any known list):'
        unknown_others.each do |field|
          check = @stats[:field_presence][field]
          puts "  #{format_field_line(field, check, total)} [UNKNOWN]"
        end
      end
      puts
    end

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  - #{err}" }
  end
end

def parse_args(args)
  options = {
    transformed_file: File.join(DEFAULT_DATA_DIR, 'secret/secret_transformed.jsonl'),
    indexes_file: File.join(DEFAULT_DATA_DIR, 'secret/secret_indexes.jsonl'),
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
  }

  args.each do |arg|
    case arg
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when /^--indexes-file=(.+)$/
      options[:indexes_file] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/05-secret/validate_instance_index.rb [OPTIONS]

        Validates secret:instances index against transformed secret objects.
        Decodes dump blobs via Redis RESTORE + HGETALL to inspect hash fields.

        Options:
          --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/secret/secret_transformed.jsonl)
          --indexes-file=FILE      Indexes JSONL (default: data/upgrades/v0.24.0/secret/secret_indexes.jsonl)
          --redis-url=URL          Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
          --temp-db=N              Temp database number (default: 15)
          --help                   Show this help

        Validates:
          Required fields (FAIL):  objid, owner_id, state, created,
            migration_status, migrated_at, v1_key, v1_identifier
          Expected fields (WARN):  receipt_identifier, receipt_shortid,
            lifespan, updated
          All other fields:        reported with presence rates for visibility
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  validator = SecretInstanceIndexValidator.new(
    transformed_file: options[:transformed_file],
    indexes_file: options[:indexes_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
