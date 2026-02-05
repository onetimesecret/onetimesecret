#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates Organization indexes from generated organization records.
# Reads the output of generate.rb and produces index commands.
#
# Run AFTER generate.rb which creates organization_transformed.jsonl
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/02-organization/create_indexes.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: data/upgrades/v0.24.0/organization/organization_transformed.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/organization)
#   --redis-url=URL     Redis URL for DUMP decoding (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N         Temp database for restore operations (default: 15)
#   --dry-run           Show what would be created without writing
#
# Input: data/upgrades/v0.24.0/organization/organization_transformed.jsonl (from generate.rb)
# Output: data/upgrades/v0.24.0/organization/organization_indexes.jsonl (Redis commands)

require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'redis'
require 'familia'
require 'uri'

# Calculate project root from script location
PROJECT_ROOT     = File.expand_path('../../../..', __dir__)
DEFAULT_DATA_DIR = File.join(PROJECT_ROOT, 'data/upgrades/v0.24.0')

class OrganizationIndexCreator
  TEMP_KEY_PREFIX = '_migrate_tmp_idx_'

  def initialize(input_file:, output_dir:, redis_url:, temp_db:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @redis_url  = redis_url
    @temp_db    = temp_db
    @dry_run    = dry_run
    @redis      = nil

    @stats = {
      total_records: 0,
      object_records: 0,
      indexes_written: 0,
      stripe_customer_indexes: 0,
      stripe_subscription_indexes: 0,
      stripe_checkout_email_indexes: 0,
      billing_email_indexes: 0,
      member_entries: 0,
      skipped: 0,
      errors: [],
    }

    @commands = []
  end

  def run
    validate_input

    puts "Processing: #{@input_file}"
    puts "Output: #{@output_dir}"
    puts 'Mode: DRY RUN' if @dry_run

    connect_redis unless @dry_run
    process_input_file
    write_outputs unless @dry_run

    print_summary
    @stats
  ensure
    cleanup_redis
  end

  private

  def validate_input
    unless File.exist?(@input_file)
      abort "Error: Input file not found: #{@input_file}\n" \
            'Run generate.rb first to create organization records.'
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

  def process_input_file
    File.foreach(@input_file) do |line|
      @stats[:total_records] += 1
      record                  = JSON.parse(line, symbolize_names: true)

      next unless record[:key]&.end_with?(':object')

      @stats[:object_records] += 1

      process_organization_record(record)
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:total_records], error: ex.message }
    end
  end

  def process_organization_record(record)
    # Extract identifiers from JSONL record metadata
    org_objid    = record[:objid]
    org_extid    = record[:extid]
    owner_id     = record[:owner_id]
    created      = record[:created]

    unless org_objid && !org_objid.empty?
      @stats[:skipped] += 1
      @stats[:errors] << { key: record[:key], error: 'Missing org objid' }
      return
    end

    # For additional fields, decode the DUMP if not in dry-run mode
    org_fields = if @dry_run
                   # Use metadata from JSONL record for dry-run
                   { 'objid' => org_objid, 'extid' => org_extid, 'owner_id' => owner_id }
                 else
                   decode_dump(record) || {}
                 end

    # Extract fields (prefer JSONL metadata, fall back to decoded fields)
    contact_email          = org_fields['contact_email']
    stripe_customer_id     = org_fields['stripe_customer_id']
    stripe_subscription_id = org_fields['stripe_subscription_id']
    stripe_checkout_email  = org_fields['stripe_checkout_email']
    billing_email          = org_fields['billing_email']

    created = created || org_fields['created']&.to_i || Time.now.to_i

    # Instance index: organization:instances (sorted set)
    add_command('ZADD', 'organization:instances', [created.to_i, org_objid])

    # Lookup indexes (Hash type, JSON-quoted values for Familia compatibility)
    if contact_email && !contact_email.empty?
      add_command('HSET', 'organization:contact_email_index', [contact_email, org_objid.to_json])
    end

    if billing_email && !billing_email.empty?
      add_command('HSET', 'organization:billing_email_index', [billing_email, org_objid.to_json])
      @stats[:billing_email_indexes] += 1
    end

    add_command('HSET', 'organization:extid_lookup', [org_extid, org_objid.to_json])
    add_command('HSET', 'organization:objid_lookup', [org_objid, org_objid.to_json])

    # Stripe indexes (only if valid)
    if stripe_customer_id && stripe_customer_id.start_with?('cus_')
      add_command(
        'HSET',
        'organization:stripe_customer_id_index',
        [stripe_customer_id, org_objid.to_json],
      )
      @stats[:stripe_customer_indexes] += 1
    end

    if stripe_subscription_id && stripe_subscription_id.start_with?('sub_')
      add_command(
        'HSET',
        'organization:stripe_subscription_id_index',
        [stripe_subscription_id, org_objid.to_json],
      )
      @stats[:stripe_subscription_indexes] += 1
    end

    if stripe_checkout_email && !stripe_checkout_email.empty?
      add_command(
        'HSET',
        'organization:stripe_checkout_email_index',
        [stripe_checkout_email, org_objid.to_json],
      )
      @stats[:stripe_checkout_email_indexes] += 1
    end

    # Members relationship: organization:{org_objid}:members
    # Owner is first member, score = created timestamp
    return unless owner_id && !owner_id.empty?

    add_command('ZADD', "organization:#{org_objid}:members", [created.to_i, owner_id])
    @stats[:member_entries] += 1

    # Customer participation: customer:{owner_id}:participations
    # Tracks which org member sets this customer belongs to
    add_command(
      'SADD',
      "customer:#{owner_id}:participations",
      ["organization:#{org_objid}:members"],
    )
  end

  def decode_dump(record)
    return nil unless record[:dump]

    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      raw_fields = @redis.hgetall(temp_key)
      # Deserialize v2 JSON-encoded values written by generate.rb
      deserialize_v2_fields(raw_fields)
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record[:key], error: "RESTORE failed: #{ex.message}" }
      nil
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end
  end

  # Deserialize a single v2 JSON-encoded value back to Ruby type
  # Values written by generate.rb are JSON-serialized (e.g., "cus_xxx" -> "\"cus_xxx\"")
  def deserialize_v2_value(raw_value)
    return nil if raw_value.nil? || raw_value == 'null'
    return raw_value if raw_value.empty?

    Familia::JsonSerializer.parse(raw_value)
  rescue Familia::SerializerError
    raw_value # Fallback for non-JSON values
  end

  # Deserialize all fields in a hash from v2 JSON format
  def deserialize_v2_fields(fields)
    return {} if fields.nil?

    fields.transform_values { |v| deserialize_v2_value(v) }
  end

  def add_command(cmd, key, args)
    @commands << {
      command: cmd,
      key: key,
      args: args,
    }
    @stats[:indexes_written] += 1
  end

  def write_outputs
    FileUtils.mkdir_p(@output_dir)

    indexes_file = File.join(@output_dir, 'organization_indexes.jsonl')
    File.open(indexes_file, 'w') do |f|
      @commands.each do |cmd|
        f.puts(JSON.generate(cmd))
      end
    end
    puts "Wrote #{@commands.size} commands to #{indexes_file}"
  end

  def print_summary
    puts "\n=== Organization Index Creation Summary ==="
    puts "Input file: #{@input_file}"
    puts "Total records: #{@stats[:total_records]}"
    puts "Object records: #{@stats[:object_records]}"
    puts "Index commands generated: #{@stats[:indexes_written]}"
    puts
    puts 'Lookup Indexes:'
    puts "  Stripe customer indexes: #{@stats[:stripe_customer_indexes]}"
    puts "  Stripe subscription indexes: #{@stats[:stripe_subscription_indexes]}"
    puts "  Stripe checkout email indexes: #{@stats[:stripe_checkout_email_indexes]}"
    puts "  Billing email indexes: #{@stats[:billing_email_indexes]}"
    puts
    puts 'Participation Indexes:'
    puts "  Member entries: #{@stats[:member_entries]}"
    puts
    puts "Skipped: #{@stats[:skipped]}"

    return unless @stats[:errors].any?

    puts "\nErrors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each do |err|
      puts "  #{err}"
    end
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'organization/organization_transformed.jsonl'),
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

        Creates Organization indexes from generated organization records.
        Run AFTER generate.rb which creates organization_transformed.jsonl.

        Options:
          --input-file=FILE   Input JSONL (default: data/upgrades/v0.24.0/organization/organization_transformed.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.0/organization)
          --redis-url=URL     Redis URL for DUMP decoding (env: VALKEY_URL or REDIS_URL)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Show what would be created without writing
          --help              Show this help

        Output file: organization_indexes.jsonl

        Index types created:
          - organization:instances (sorted set: score=created, member=org_objid)
          - organization:contact_email_index (hash: email -> "org_objid")
          - organization:extid_lookup (hash: extid -> "org_objid")
          - organization:objid_lookup (hash: org_objid -> "org_objid")
          - organization:stripe_customer_id_index (hash: cus_xxx -> "org_objid")
          - organization:stripe_subscription_id_index (hash: sub_xxx -> "org_objid")
          - organization:stripe_checkout_email_index (hash: email -> "org_objid")
          - organization:{org_objid}:members (sorted set: score=created, member=customer_objid)
          - customer:{owner_id}:participations (set: organization:{org_objid}:members)
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

  creator = OrganizationIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )

  creator.run
end
