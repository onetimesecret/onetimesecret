#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates Organization indexes from Customer dump records.
# Organizations are NEW in V2 - one is created per Customer.
#
# Usage:
#   ruby scripts/migrations/jan24/create_indexes_organization.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: exports/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports/organization)
#   --dry-run           Show what would be created without writing
#
# Input: exports/customer/customer_dump.jsonl (hash records with DUMP data)
# Output:
#   - exports/organization/organization_indexes.jsonl (Redis commands)
#   - exports/organization/customer_to_org_lookup.json (customer_objid -> org_objid)

require 'json'
require 'base64'
require 'digest'
require 'fileutils'
require 'securerandom'
require 'redis'

class OrganizationIndexCreator
  # Temporary Redis for RESTORE operations to decode DUMP data
  DECODE_DB = 15

  def initialize(input_file:, output_dir:, dry_run: false, redis_url: 'redis://127.0.0.1:6379')
    @input_file = input_file
    @output_dir = output_dir
    @dry_run    = dry_run
    @redis_url  = redis_url

    @stats = {
      total_records: 0,
      hash_records: 0,
      object_records: 0,
      organizations_created: 0,
      indexes_written: 0,
      stripe_customer_indexes: 0,
      stripe_subscription_indexes: 0,
      skipped: 0,
      errors: [],
    }

    @customer_to_org = {}  # customer_objid -> org_objid
    @commands        = []         # Redis commands for indexes
  end

  def run
    validate_input

    puts "Processing: #{@input_file}"
    puts "Output: #{@output_dir}"
    puts 'Mode: DRY RUN' if @dry_run

    # Connect to Redis for DUMP decoding
    @redis = Redis.new(url: "#{@redis_url}/#{DECODE_DB}")

    process_input_file
    write_outputs unless @dry_run

    print_summary
    @stats
  end

  private

  def validate_input
    unless File.exist?(@input_file)
      abort "Error: Input file not found: #{@input_file}"
    end
  end

  def process_input_file
    File.foreach(@input_file) do |line|
      @stats[:total_records] += 1
      process_record(JSON.parse(line))
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:total_records], error: ex.message }
    end
  ensure
    # Clean up decode DB
    @redis&.flushdb
  end

  def process_record(record)
    return unless record['type'] == 'hash'

    @stats[:hash_records] += 1

    key = record['key']
    return unless key.end_with?(':object')

    @stats[:object_records] += 1

    # Extract customer data by restoring DUMP temporarily
    customer_data = decode_dump(record)
    return unless customer_data

    # Generate organization
    create_organization_indexes(customer_data, record)
  end

  def decode_dump(record)
    dump_data = Base64.strict_decode64(record['dump'])
    temp_key  = "decode:#{SecureRandom.hex(8)}"

    begin
      # RESTORE the dump to read its contents
      @redis.restore(temp_key, 0, dump_data, replace: true)
      data = @redis.hgetall(temp_key)
      @redis.del(temp_key)
      data
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record['key'], error: "RESTORE failed: #{ex.message}" }
      nil
    end
  end

  def create_organization_indexes(customer_data, record)
    customer_objid = extract_customer_objid(record['key'], customer_data)
    unless customer_objid
      @stats[:skipped] += 1
      return
    end

    # Generate deterministic org_objid from customer_objid
    org_objid = generate_org_objid(customer_objid)
    extid     = "on#{org_objid[0..7]}"

    # Use 'created' from JSONL record or customer data
    created = record['created'] || customer_data['created']&.to_i || Time.now.to_i

    email                  = customer_data['email'] || customer_data['custid']
    stripe_customer_id     = customer_data['stripe_customer_id']
    stripe_subscription_id = customer_data['stripe_subscription_id']

    # Track mapping
    @customer_to_org[customer_objid] = org_objid
    @stats[:organizations_created]  += 1

    # Instance index: organization:instances (sorted set)
    add_command('ZADD', 'organization:instances', [created.to_s, org_objid])

    # Lookup indexes (Hash type, JSON-quoted values)
    if email && !email.empty?
      add_command('HSET', 'organization:contact_email_index', [email, json_quote(org_objid)])
    end

    add_command('HSET', 'organization:extid_lookup', [extid, json_quote(org_objid)])
    add_command('HSET', 'organization:objid_lookup', [org_objid, json_quote(org_objid)])

    # Stripe indexes (only if valid)
    if stripe_customer_id && stripe_customer_id.start_with?('cus_')
      add_command(
        'HSET',
        'organization:stripe_customer_id_index',
        [stripe_customer_id, json_quote(org_objid)],
      )
      @stats[:stripe_customer_indexes] += 1
    end

    if stripe_subscription_id && stripe_subscription_id.start_with?('sub_')
      add_command(
        'HSET',
        'organization:stripe_subscription_id_index',
        [stripe_subscription_id, json_quote(org_objid)],
      )
      @stats[:stripe_subscription_indexes] += 1
    end

    # Members relationship: organization:{org_objid}:members
    # Owner is first member, score = created timestamp
    add_command('ZADD', "organization:#{org_objid}:members", [created.to_s, customer_objid])
  end

  def extract_customer_objid(key, customer_data)
    # Key format: customer:{identifier}:object
    # The identifier could be email (v1) or objid
    # For v1, we need the objid from the customer data hash
    #
    # Look for objid field in customer data first
    return customer_data['objid'] if customer_data['objid'] && !customer_data['objid'].empty?

    # Fallback: extract from key if it looks like an objid (20 hex chars)
    parts      = key.split(':')
    identifier = parts[1]

    if identifier && identifier.match?(/\A[0-9a-f]{20}\z/i)
      return identifier
    end

    # V1 customers keyed by email need objid from data
    # If no objid in data, generate deterministically from email
    email = customer_data['email'] || customer_data['custid'] || identifier
    generate_customer_objid_from_email(email)
  end

  def generate_customer_objid_from_email(email)
    return nil unless email

    # Generate deterministic 20-char hex objid from email
    # Using SHA256 and taking first 20 chars
    Digest::SHA256.hexdigest("customer:#{email}")[0..19]
  end

  def generate_org_objid(customer_objid)
    # Generate deterministic org_objid from customer_objid
    # Using SHA256 to ensure consistent mapping
    Digest::SHA256.hexdigest("organization:#{customer_objid}")[0..19]
  end

  def json_quote(value)
    # JSON-quoted string value for hash index entries
    value.to_json
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

    # Write JSONL commands
    indexes_file = File.join(@output_dir, 'organization_indexes.jsonl')
    File.open(indexes_file, 'w') do |f|
      @commands.each do |cmd|
        f.puts(JSON.generate(cmd))
      end
    end
    puts "Wrote #{@commands.size} commands to #{indexes_file}"

    # Write customer->org lookup
    lookup_file = File.join(@output_dir, 'customer_to_org_lookup.json')
    File.write(lookup_file, JSON.pretty_generate(@customer_to_org))
    puts "Wrote #{@customer_to_org.size} mappings to #{lookup_file}"
  end

  def print_summary
    puts "\n=== Summary ==="
    puts "Total records processed: #{@stats[:total_records]}"
    puts "Hash records: #{@stats[:hash_records]}"
    puts "Object records: #{@stats[:object_records]}"
    puts "Organizations created: #{@stats[:organizations_created]}"
    puts "Index commands generated: #{@stats[:indexes_written]}"
    puts "  - Stripe customer indexes: #{@stats[:stripe_customer_indexes]}"
    puts "  - Stripe subscription indexes: #{@stats[:stripe_subscription_indexes]}"
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
    input_file: 'exports/customer/customer_dump.jsonl',
    output_dir: 'exports/organization',
    dry_run: false,
    redis_url: 'redis://127.0.0.1:6379',
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/
      options[:input_file] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/create_indexes_organization.rb [OPTIONS]

        Creates Organization indexes from Customer dump records.
        Organizations are NEW in V2 - one is created per Customer.

        Options:
          --input-file=FILE   Input JSONL file (default: exports/customer/customer_dump.jsonl)
          --output-dir=DIR    Output directory (default: exports/organization)
          --redis-url=URL     Redis URL for DUMP decoding (default: redis://127.0.0.1:6379)
          --dry-run           Show what would be created without writing
          --help              Show this help

        Output files:
          exports/organization/organization_indexes.jsonl - Redis commands
          exports/organization/customer_to_org_lookup.json - customer_objid -> org_objid mapping

        Index types created:
          - organization:instances (sorted set: score=created, member=org_objid)
          - organization:contact_email_index (hash: email -> "org_objid")
          - organization:extid_lookup (hash: extid -> "org_objid")
          - organization:objid_lookup (hash: org_objid -> "org_objid")
          - organization:stripe_customer_id_index (hash: cus_xxx -> "org_objid")
          - organization:stripe_subscription_id_index (hash: sub_xxx -> "org_objid")
          - organization:{org_objid}:members (sorted set: score=created, member=customer_objid)
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  creator = OrganizationIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
    redis_url: options[:redis_url],
  )

  creator.run
end
