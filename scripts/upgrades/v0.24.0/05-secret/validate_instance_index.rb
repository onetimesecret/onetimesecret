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
# 3. Key fields (owner_id, state, receipt_identifier, receipt_shortid,
#    created, lifespan, migration_status) are non-nil inside the
#    transformed Redis hash (decoded via RESTORE + HGETALL)
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
  KEY_FIELDS = %w[owner_id state receipt_identifier receipt_shortid created lifespan migration_status].freeze

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
      field_checks: Hash.new { |h, k| h[k] = { present: 0, missing: 0, missing_objids: [] } },
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

    # 4. Spot-check key fields by decoding dump blobs
    spot_check_fields(transformed_objects)

    # 5. Report
    print_report

    # Success if no orphaned entries
    @stats[:in_index_not_in_objects].empty? && @stats[:in_objects_not_in_index].empty?
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

  def spot_check_fields(transformed_objects)
    transformed_objects.each do |objid, record|
      hash_fields = decode_hash_fields(record)

      KEY_FIELDS.each do |field|
        value = hash_fields[field]
        check = @stats[:field_checks][field]

        if value && !value.to_s.empty?
          check[:present] += 1
        else
          check[:missing] += 1
          check[:missing_objids] << objid if check[:missing_objids].size < 20
        end
      end
    end
  end

  def print_report
    puts '=== Secret Instance Index Validation ==='
    puts "Index members (secret:instances): #{@stats[:index_members]}"
    puts "Transformed objects: #{@stats[:transformed_objects]}"
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

    puts '=== Key Field Checks ==='
    KEY_FIELDS.each do |field|
      check = @stats[:field_checks][field]
      total = check[:present] + check[:missing]
      pct   = total > 0 ? (check[:present] * 100.0 / total).round(1) : 0
      status = check[:missing] > 0 ? 'WARN' : 'OK'
      puts "  #{field}: #{check[:present]}/#{total} present (#{pct}%) [#{status}]"

      next unless check[:missing] > 0 && check[:missing_objids].any?

      puts "    Missing in: #{check[:missing_objids].first(5).join(', ')}"
      puts "    ... and #{check[:missing_objids].size - 5} more" if check[:missing_objids].size > 5
    end
    puts

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
          - Each objid in secret:instances has a matching secret:{objid}:object
          - Each transformed secret object has an entry in secret:instances
          - Key fields (owner_id, state, receipt_identifier, receipt_shortid,
            created, lifespan, migration_status) are non-nil in decoded Redis hash
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
