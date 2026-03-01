#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates the has_passphrase boolean field on receipt records after v1->v2
# migration.
#
# In v2, receipts no longer store the raw passphrase string. Instead, the
# transform derives a boolean `has_passphrase` field from whether the v1
# passphrase was non-empty, and explicitly drops the raw `passphrase` field.
#
# This script checks:
# 1. Every receipt has a `has_passphrase` field with a valid boolean value
#    ("true" or "false" after JSON unwrapping)
# 2. No receipt has a `passphrase` field (raw passphrase leak = migration error)
# 3. Cross-reference with linked secret: if has_passphrase is true, the
#    corresponding secret should also have a hashed passphrase
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/04-receipt/validate_passphrase_fields.rb [OPTIONS]
#
# Options:
#   --transformed-file=FILE         Receipt transformed JSONL
#   --secret-transformed-file=FILE  Secret transformed JSONL (for cross-ref)
#   --redis-url=URL                 Redis URL for dump blob decoding
#   --temp-db=N                     Temp database number (default: 15)
#   --help                          Show this help

require 'json'
require 'base64'
require 'redis'
require 'securerandom'
require 'uri'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class ReceiptPassphraseValidator
  TEMP_KEY_PREFIX = '_validate_rcpt_pp_'

  def initialize(transformed_file:, secret_transformed_file:, redis_url:, temp_db: 15)
    @transformed_file        = transformed_file
    @secret_transformed_file = secret_transformed_file
    @redis_url               = redis_url
    @temp_db                 = temp_db
    @redis                   = nil

    @stats = {
      total_receipts: 0,
      has_passphrase_true: 0,
      has_passphrase_false: 0,
      missing_has_passphrase: [],    # receipt missing the has_passphrase field entirely
      invalid_has_passphrase: [],    # has_passphrase present but not a valid boolean
      raw_passphrase_leak: [],       # receipt still has a raw passphrase field (migration error)
      cross_ref_checked: 0,
      cross_ref_mismatches: [],      # has_passphrase true but secret has no passphrase
      cross_ref_secret_missing: [],  # receipt references a secret not found in transformed file
      errors: [],
    }
  end

  def run
    validate_input_files
    connect_redis

    # 1. Load secret passphrase map for cross-referencing
    secret_passphrases = load_secret_passphrases
    puts "Loaded #{secret_passphrases.size} secret records for cross-reference"

    # 2. Scan receipt records and validate has_passphrase field
    validate_receipts(secret_passphrases)

    # 3. Report
    print_report

    success?
  ensure
    cleanup_redis
  end

  def success?
    @stats[:missing_has_passphrase].empty? &&
      @stats[:invalid_has_passphrase].empty? &&
      @stats[:raw_passphrase_leak].empty?
  end

  private

  def validate_input_files
    unless File.exist?(@transformed_file)
      raise ArgumentError, "Transformed file not found: #{@transformed_file}\nRun transform.rb first."
    end
    unless File.exist?(@secret_transformed_file)
      raise ArgumentError, "Secret transformed file not found: #{@secret_transformed_file}\nRun secret transform.rb first."
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

  # Unwrap Familia v2 JSON-encoded string values.
  # A string "hello" is stored as "\"hello\"", null as "null".
  def unwrap_json_value(raw)
    return nil if raw.nil?
    return nil if raw == 'null'
    return nil if raw.empty?

    parsed = JSON.parse(raw)
    return nil if parsed.nil?

    parsed.to_s
  rescue JSON::ParserError
    raw
  end

  # Build a map of secret_shortid -> has_passphrase from the secret transformed file
  def load_secret_passphrases
    secrets = {} # objid -> true/false (has passphrase)

    File.foreach(@secret_transformed_file) do |line|
      record = JSON.parse(line, symbolize_names: false)
      key = record['key']
      next unless key&.match?(/^secret:[^:]+:object$/)

      objid = record['objid']
      next unless objid

      hash_fields = decode_hash_fields(record)
      passphrase_raw = hash_fields['passphrase']
      passphrase = unwrap_json_value(passphrase_raw)

      secrets[objid] = !passphrase.nil? && !passphrase.empty?
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'secret_transformed', error: "JSON parse error: #{ex.message}" }
    end

    secrets
  end

  def validate_receipts(secret_passphrases)
    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line, symbolize_names: false)
      key = record['key']
      next unless key&.match?(/^receipt:[^:]+:object$/)

      objid = record['objid']
      next unless objid

      @stats[:total_receipts] += 1

      hash_fields = decode_hash_fields(record)

      # CHECK 1: passphrase field must NOT exist on any receipt
      if hash_fields.key?('passphrase')
        passphrase_raw = hash_fields['passphrase']
        # Only flag if the value is meaningful (not JSON null / empty)
        passphrase_val = unwrap_json_value(passphrase_raw)
        if passphrase_val && !passphrase_val.empty?
          @stats[:raw_passphrase_leak] << {
            objid: objid,
            raw_preview: passphrase_raw.to_s[0..20],
          } if @stats[:raw_passphrase_leak].size < 20
        end
      end

      # CHECK 2: has_passphrase field must exist with a valid boolean value
      has_passphrase_raw = hash_fields['has_passphrase']

      if has_passphrase_raw.nil?
        @stats[:missing_has_passphrase] << objid if @stats[:missing_has_passphrase].size < 20
        next
      end

      # Unwrap the JSON-encoded boolean: Familia v2 stores true as "true" in Redis.
      # unwrap_json_value parses it to Ruby true, then .to_s gives "true".
      has_passphrase_str = unwrap_json_value(has_passphrase_raw)

      unless %w[true false].include?(has_passphrase_str)
        @stats[:invalid_has_passphrase] << {
          objid: objid,
          raw_value: has_passphrase_raw.to_s[0..60],
        } if @stats[:invalid_has_passphrase].size < 20
        next
      end

      if has_passphrase_str == 'true'
        @stats[:has_passphrase_true] += 1
      else
        @stats[:has_passphrase_false] += 1
      end

      # CHECK 3: Cross-reference with linked secret (only when has_passphrase is true)
      next unless has_passphrase_str == 'true'

      secret_shortid = unwrap_json_value(hash_fields['secret_shortid'])
      next unless secret_shortid && !secret_shortid.empty?

      @stats[:cross_ref_checked] += 1

      if secret_passphrases.key?(secret_shortid)
        unless secret_passphrases[secret_shortid]
          @stats[:cross_ref_mismatches] << {
            receipt_objid: objid,
            secret_shortid: secret_shortid,
            issue: 'has_passphrase is true but secret has no passphrase',
          } if @stats[:cross_ref_mismatches].size < 20
        end
      else
        @stats[:cross_ref_secret_missing] << {
          receipt_objid: objid,
          secret_shortid: secret_shortid,
        } if @stats[:cross_ref_secret_missing].size < 20
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end
  end

  def print_report
    puts
    puts '=== Receipt has_passphrase Field Validation ==='
    puts "Total receipts scanned: #{@stats[:total_receipts]}"
    puts "  has_passphrase=true: #{@stats[:has_passphrase_true]}"
    puts "  has_passphrase=false: #{@stats[:has_passphrase_false]}"
    puts

    # Raw passphrase leak check (FAIL)
    count = @stats[:raw_passphrase_leak].size
    status = count.zero? ? 'OK' : 'FAIL'
    puts "Raw passphrase field present on receipts: #{count} [#{status}]"
    if count > 0
      puts '  These receipts still have a raw passphrase value (should have been dropped by transform):'
      @stats[:raw_passphrase_leak].first(10).each do |entry|
        puts "    - #{entry[:objid]}: raw=#{entry[:raw_preview]}..."
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Missing has_passphrase check (FAIL)
    count = @stats[:missing_has_passphrase].size
    status = count.zero? ? 'OK' : 'FAIL'
    puts "Missing has_passphrase field: #{count} [#{status}]"
    if count > 0
      puts '  These receipts have no has_passphrase field:'
      @stats[:missing_has_passphrase].first(10).each { |id| puts "    - #{id}" }
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Invalid has_passphrase value check (FAIL)
    count = @stats[:invalid_has_passphrase].size
    status = count.zero? ? 'OK' : 'FAIL'
    puts "Invalid has_passphrase values: #{count} [#{status}]"
    if count > 0
      puts '  These receipts have has_passphrase with a non-boolean value:'
      @stats[:invalid_has_passphrase].first(10).each do |entry|
        puts "    - #{entry[:objid]}: raw=#{entry[:raw_value]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Cross-reference results
    puts '=== Cross-Reference: Receipt <-> Secret ==='
    puts "Receipt-secret pairs checked: #{@stats[:cross_ref_checked]}"

    count = @stats[:cross_ref_mismatches].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Passphrase mismatches (has_passphrase=true, secret lacks passphrase): #{count} [#{status}]"
    if count > 0
      @stats[:cross_ref_mismatches].first(10).each do |entry|
        puts "    - receipt=#{entry[:receipt_objid]} secret=#{entry[:secret_shortid]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end

    count = @stats[:cross_ref_secret_missing].size
    status = count.zero? ? 'OK' : 'INFO'
    puts "Secret not found in transformed file: #{count} [#{status}]"
    if count > 0
      @stats[:cross_ref_secret_missing].first(5).each do |entry|
        puts "    - receipt=#{entry[:receipt_objid]} secret_shortid=#{entry[:secret_shortid]}"
      end
      puts "    ... and #{count - 5} more" if count > 5
    end
    puts

    if success?
      puts 'OK: All receipt has_passphrase fields are valid and no raw passphrases leaked.'
    else
      puts 'FAIL: Receipt passphrase field validation errors detected.'
    end
    puts

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  - #{err}" }
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    transformed_file: File.join(DEFAULT_DATA_DIR, 'metadata/receipt_transformed.jsonl'),
    secret_transformed_file: File.join(DEFAULT_DATA_DIR, 'secret/secret_transformed.jsonl'),
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
  }

  args.each do |arg|
    case arg
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when /^--secret-transformed-file=(.+)$/
      options[:secret_transformed_file] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/04-receipt/validate_passphrase_fields.rb [OPTIONS]

        Validates the has_passphrase boolean field on receipt records after v1->v2
        migration. In v2, the raw passphrase is dropped from receipts and replaced
        with a boolean has_passphrase field.

        Decodes dump blobs via Redis RESTORE + HGETALL to inspect hash fields.

        Options:
          --transformed-file=FILE         Receipt transformed JSONL
                                          (default: data/upgrades/v0.24.0/metadata/receipt_transformed.jsonl)
          --secret-transformed-file=FILE  Secret transformed JSONL for cross-reference
                                          (default: data/upgrades/v0.24.0/secret/secret_transformed.jsonl)
          --redis-url=URL                 Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
          --temp-db=N                     Temp database number (default: 15)
          --help                          Show this help

        Validates:
          - FAIL if any receipt has a raw passphrase field (should have been dropped)
          - FAIL if any receipt is missing has_passphrase or has an invalid value
          - WARN if has_passphrase=true but linked secret has no passphrase
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

  validator = ReceiptPassphraseValidator.new(
    transformed_file: options[:transformed_file],
    secret_transformed_file: options[:secret_transformed_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
