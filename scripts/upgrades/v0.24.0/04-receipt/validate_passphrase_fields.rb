#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates passphrase data on receipt records after v1->v2 migration.
#
# Receipts store PLAINTEXT passphrases (not hashed). The v1->v2 transform
# copies the passphrase field verbatim via DIRECT_COPY_FIELDS. Empty v1
# passphrases ("") become the JSON string "null" via serialize_for_v2.
#
# This script checks:
# 1. Receipts WITH passphrases: value is a non-empty, non-"null" string
# 2. Receipts WITHOUT passphrases: field is absent, empty, or JSON "null"
#    (not a corrupted/partial value)
# 3. Cross-reference with linked secret: if receipt has a passphrase,
#    the corresponding secret should also have a hashed passphrase
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
      with_passphrase: 0,
      without_passphrase: 0,
      literal_null_string: [],       # passphrase is the literal string "null" (bad serialization)
      corrupted_values: [],          # non-empty but suspicious values on no-passphrase receipts
      cross_ref_checked: 0,
      cross_ref_mismatches: [],      # receipt has passphrase but secret does not
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

    # 2. Scan receipt records and validate passphrase fields
    validate_receipts(secret_passphrases)

    # 3. Report
    print_report

    success?
  ensure
    cleanup_redis
  end

  def success?
    @stats[:literal_null_string].empty? &&
      @stats[:corrupted_values].empty? &&
      @stats[:cross_ref_mismatches].empty?
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
      passphrase_raw = hash_fields['passphrase']
      passphrase = unwrap_json_value(passphrase_raw)

      if passphrase && !passphrase.empty?
        # Receipt HAS a passphrase
        @stats[:with_passphrase] += 1

        # Check for literal "null" string (bad serialization artifact)
        if passphrase == 'null'
          @stats[:literal_null_string] << objid if @stats[:literal_null_string].size < 20
        end

        # Cross-reference with linked secret
        secret_shortid = unwrap_json_value(hash_fields['secret_shortid'])
        if secret_shortid && !secret_shortid.empty?
          @stats[:cross_ref_checked] += 1

          if secret_passphrases.key?(secret_shortid)
            unless secret_passphrases[secret_shortid]
              @stats[:cross_ref_mismatches] << {
                receipt_objid: objid,
                secret_shortid: secret_shortid,
                issue: 'receipt has passphrase but secret does not',
              } if @stats[:cross_ref_mismatches].size < 20
            end
          else
            @stats[:cross_ref_secret_missing] << {
              receipt_objid: objid,
              secret_shortid: secret_shortid,
            } if @stats[:cross_ref_secret_missing].size < 20
          end
        end
      else
        # Receipt does NOT have a passphrase
        @stats[:without_passphrase] += 1

        # Verify the raw value is clean (absent, empty, or JSON "null")
        # Anything else is suspicious
        if passphrase_raw && passphrase_raw != 'null' && passphrase_raw != '' && passphrase_raw != '""'
          @stats[:corrupted_values] << {
            objid: objid,
            raw_value: passphrase_raw.to_s[0..60],
          } if @stats[:corrupted_values].size < 20
        end
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end
  end

  def print_report
    puts
    puts '=== Receipt Passphrase Field Validation ==='
    puts "Total receipts scanned: #{@stats[:total_receipts]}"
    puts "  With passphrase: #{@stats[:with_passphrase]}"
    puts "  Without passphrase: #{@stats[:without_passphrase]}"
    puts

    # Literal "null" string check
    count = @stats[:literal_null_string].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Literal 'null' string passphrases: #{count} [#{status}]"
    if count > 0
      puts '  These receipts have the string "null" as passphrase (bad serialization):'
      @stats[:literal_null_string].first(10).each { |id| puts "    - #{id}" }
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Corrupted values check
    count = @stats[:corrupted_values].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Corrupted/unexpected empty-passphrase values: #{count} [#{status}]"
    if count > 0
      puts '  Receipts without passphrase but with unexpected raw value:'
      @stats[:corrupted_values].first(10).each do |entry|
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
    puts "Passphrase mismatches (receipt has, secret doesn't): #{count} [#{status}]"
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
      puts 'OK: All receipt passphrase fields are consistent.'
    else
      puts 'FAIL: Passphrase field inconsistencies detected.'
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

        Validates passphrase data on receipt records after v1->v2 migration.
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
          - Receipts with passphrases have non-null, non-empty string values
          - Receipts without passphrases have clean absent/null/empty fields
          - Receipt-secret passphrase consistency (both have or both lack)
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
