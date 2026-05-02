#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates passphrase and encryption data on secret records after v1->v2 migration.
#
# Secrets store HASHED passphrases (bcrypt $2a$/$2b$ from v1, argon2id from v2).
# The v1->v2 transform copies passphrase, passphrase_encryption, value_encryption,
# and ciphertext verbatim via DIRECT_COPY_FIELDS. Empty v1 fields become JSON "null"
# via serialize_for_v2.
#
# This script checks:
# 1. Secrets WITH passphrases: hash format is recognizable (bcrypt or argon2id)
# 2. passphrase_encryption version tag consistency with hash format
# 3. Secrets WITHOUT passphrases: field is clean (absent, empty, or JSON "null")
# 4. Hash algorithm distribution statistics
#
# Reads fields directly from the typed payload (record['fields_b64']) emitted
# by the transform. No Redis dependency.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/05-secret/validate_passphrase_fields.rb [OPTIONS]
#
# Options:
#   --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.5/secret/secret_transformed.jsonl)
#   --help                   Show this help

require 'json'
require 'base64'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'

class SecretPassphraseValidator
  # Known bcrypt prefixes
  BCRYPT_PREFIXES = %w[$2a$ $2b$ $2y$].freeze
  ARGON2_PREFIX = '$argon2id$'

  def initialize(transformed_file:)
    @transformed_file = transformed_file

    @stats = {
      total_secrets: 0,
      with_passphrase: 0,
      without_passphrase: 0,
      # Hash algorithm counts
      bcrypt_count: 0,
      argon2_count: 0,
      unknown_hash_format: [],         # unrecognized hash prefix
      # passphrase_encryption consistency
      encryption_version_mismatches: [], # hash format doesn't match version tag
      # Empty-passphrase field hygiene
      corrupted_empty_passphrase: [],   # no passphrase but unexpected raw value
      bad_encryption_on_empty: [],      # no passphrase but encryption version set
      # Literal "null" string that parsed as a real passphrase
      literal_null_passphrases: [],
      errors: [],
    }
  end

  def run
    validate_input_files
    validate_secrets
    print_report
    success?
  end

  def success?
    @stats[:unknown_hash_format].empty? &&
      @stats[:encryption_version_mismatches].empty? &&
      @stats[:corrupted_empty_passphrase].empty? &&
      @stats[:literal_null_passphrases].empty?
  end

  private

  def validate_input_files
    return if File.exist?(@transformed_file)

    raise ArgumentError, "Transformed file not found: #{@transformed_file}\nRun transform.rb first."
  end

  # Decode hash fields from the typed payload. Returns {} if absent.
  def decode_hash_fields(record)
    fields_b64 = record['fields_b64']
    return {} unless fields_b64.is_a?(Hash)

    fields_b64.each_with_object({}) do |(field, b64), acc|
      acc[field.to_s] = Base64.strict_decode64(b64.to_s)
    end
  rescue ArgumentError => ex
    @stats[:errors] << { key: record['key'], error: "Base64 decode failed: #{ex.message}" }
    {}
  end

  # Unwrap Familia v2 JSON-encoded string values.
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

  def classify_hash(passphrase)
    if passphrase.start_with?(ARGON2_PREFIX)
      :argon2
    elsif BCRYPT_PREFIXES.any? { |prefix| passphrase.start_with?(prefix) }
      :bcrypt
    else
      :unknown
    end
  end

  def validate_secrets
    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line, symbolize_names: false)
      key = record['key']
      next unless key&.match?(/^secret:[^:]+:object$/)

      objid = record['objid']
      next unless objid

      @stats[:total_secrets] += 1

      hash_fields = decode_hash_fields(record)
      passphrase_raw = hash_fields['passphrase']
      passphrase = unwrap_json_value(passphrase_raw)
      encryption_raw = hash_fields['passphrase_encryption']
      encryption = unwrap_json_value(encryption_raw)

      if passphrase && !passphrase.empty?
        validate_with_passphrase(objid, passphrase, encryption)
      else
        validate_without_passphrase(objid, passphrase_raw, encryption_raw, encryption)
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end
  end

  def validate_with_passphrase(objid, passphrase, encryption)
    @stats[:with_passphrase] += 1

    # Check for literal "null" that survived as a passphrase string
    if passphrase == 'null'
      @stats[:literal_null_passphrases] << objid if @stats[:literal_null_passphrases].size < 20
      return
    end

    # Classify hash algorithm
    algo = classify_hash(passphrase)

    case algo
    when :bcrypt
      @stats[:bcrypt_count] += 1
      # bcrypt -> passphrase_encryption should be "1" or absent (very old secrets)
      if encryption && !encryption.empty? && encryption != '1'
        @stats[:encryption_version_mismatches] << {
          objid: objid,
          algo: 'bcrypt',
          passphrase_encryption: encryption,
          expected: '1 or absent',
        } if @stats[:encryption_version_mismatches].size < 20
      end

    when :argon2
      @stats[:argon2_count] += 1
      # argon2 -> passphrase_encryption should be "2"
      if encryption != '2'
        @stats[:encryption_version_mismatches] << {
          objid: objid,
          algo: 'argon2',
          passphrase_encryption: encryption,
          expected: '2',
        } if @stats[:encryption_version_mismatches].size < 20
      end

    when :unknown
      @stats[:unknown_hash_format] << {
        objid: objid,
        prefix: passphrase[0..15],
        passphrase_encryption: encryption,
      } if @stats[:unknown_hash_format].size < 20
    end
  end

  def validate_without_passphrase(objid, passphrase_raw, encryption_raw, encryption)
    @stats[:without_passphrase] += 1

    # Verify the raw passphrase value is clean
    if passphrase_raw && passphrase_raw != 'null' && passphrase_raw != '' && passphrase_raw != '""'
      @stats[:corrupted_empty_passphrase] << {
        objid: objid,
        raw_value: passphrase_raw.to_s[0..60],
      } if @stats[:corrupted_empty_passphrase].size < 20
    end

    # Verify passphrase_encryption is absent, empty, "null", "-1", or "0"
    # for secrets without a passphrase
    if encryption && !encryption.empty?
      unless %w[-1 0].include?(encryption)
        @stats[:bad_encryption_on_empty] << {
          objid: objid,
          passphrase_encryption: encryption,
        } if @stats[:bad_encryption_on_empty].size < 20
      end
    end
  end

  def print_report
    puts
    puts '=== Secret Passphrase Field Validation ==='
    puts "Total secrets scanned: #{@stats[:total_secrets]}"
    puts "  With passphrase: #{@stats[:with_passphrase]}"
    puts "  Without passphrase: #{@stats[:without_passphrase]}"
    puts

    # Hash algorithm distribution
    puts '=== Hash Algorithm Distribution ==='
    puts "  bcrypt ($2a$/$2b$/$2y$): #{@stats[:bcrypt_count]}"
    puts "  argon2id: #{@stats[:argon2_count]}"

    count = @stats[:unknown_hash_format].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "  Unknown format: #{count} [#{status}]"
    if count > 0
      @stats[:unknown_hash_format].first(10).each do |entry|
        puts "    - #{entry[:objid]}: prefix=#{entry[:prefix]}... encryption=#{entry[:passphrase_encryption]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Encryption version consistency
    count = @stats[:encryption_version_mismatches].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Encryption version mismatches: #{count} [#{status}]"
    if count > 0
      puts '  Hash algorithm does not match passphrase_encryption version:'
      @stats[:encryption_version_mismatches].first(10).each do |entry|
        puts "    - #{entry[:objid]}: algo=#{entry[:algo]} encryption=#{entry[:passphrase_encryption]} expected=#{entry[:expected]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Literal "null" passphrases
    count = @stats[:literal_null_passphrases].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Literal 'null' string passphrases: #{count} [#{status}]"
    if count > 0
      @stats[:literal_null_passphrases].first(10).each { |id| puts "    - #{id}" }
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Corrupted empty-passphrase values
    count = @stats[:corrupted_empty_passphrase].size
    status = count.zero? ? 'OK' : 'WARN'
    puts "Corrupted empty-passphrase raw values: #{count} [#{status}]"
    if count > 0
      @stats[:corrupted_empty_passphrase].first(10).each do |entry|
        puts "    - #{entry[:objid]}: raw=#{entry[:raw_value]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    # Bad encryption version on empty passphrase
    count = @stats[:bad_encryption_on_empty].size
    status = count.zero? ? 'OK' : 'INFO'
    puts "Unexpected encryption version on empty passphrase: #{count} [#{status}]"
    if count > 0
      @stats[:bad_encryption_on_empty].first(10).each do |entry|
        puts "    - #{entry[:objid]}: passphrase_encryption=#{entry[:passphrase_encryption]}"
      end
      puts "    ... and #{count - 10} more" if count > 10
    end
    puts

    if success?
      puts 'OK: All secret passphrase fields are consistent.'
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
    transformed_file: File.join(DEFAULT_DATA_DIR, 'secret/secret_transformed.jsonl'),
  }

  args.each do |arg|
    case arg
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.5/05-secret/validate_passphrase_fields.rb [OPTIONS]

        Validates passphrase and encryption data on secret records after v1->v2 migration.
        Reads hash fields directly from the typed payload (fields_b64) emitted by the
        transform; no Redis dependency.

        Options:
          --transformed-file=FILE  Transformed JSONL
                                   (default: data/upgrades/v0.24.5/secret/secret_transformed.jsonl)
          --help                   Show this help

        Validates:
          - Passphrase hash format is bcrypt ($2a$/$2b$/$2y$) or argon2id
          - passphrase_encryption version tag matches hash algorithm
          - Empty-passphrase secrets have clean field values
          - No literal "null" strings stored as passphrases
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

  validator = SecretPassphraseValidator.new(
    transformed_file: options[:transformed_file],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
