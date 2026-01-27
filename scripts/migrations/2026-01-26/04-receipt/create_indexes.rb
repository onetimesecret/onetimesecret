#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates V2 index commands for Receipt (formerly Metadata) from dump data.
# Reads metadata_dump.jsonl and outputs receipt_indexes.jsonl with Redis commands.
#
# Usage:
#   ruby scripts/migrations/jan24/create_indexes_receipt.rb [OPTIONS]
#
# Options:
#   --input-file=PATH      Input JSONL file (default: exports/metadata/metadata_dump.jsonl)
#   --output-dir=DIR       Output directory (default: exports/receipt)
#   --customer-lookup=PATH Path to customer email→objid JSON map
#   --org-lookup=PATH      Path to customer objid→org objid JSON map
#   --domain-lookup=PATH   Path to domain fqdn→domainid JSON map
#   --dry-run              Show what would be created without writing
#   --help                 Show this help
#
# Input format (each line):
#   {"key": "metadata:abc123:object", "type": "hash", "ttl_ms": -1, "db": 7, "dump": "<base64>", "created": 1234567890}
#
# Output format (JSONL with Redis commands):
#   {"command": "ZADD", "key": "receipt:instances", "args": ["1234567890", "objid123"]}

require 'redis'
require 'json'
require 'base64'
require 'fileutils'

class ReceiptIndexCreator
  DEFAULT_INPUT      = 'exports/metadata/metadata_dump.jsonl'
  DEFAULT_OUTPUT_DIR = 'exports/receipt'
  OUTPUT_FILENAME    = 'receipt_indexes.jsonl'

  def initialize(input_file:, output_dir:, customer_lookup_path:, org_lookup_path:, domain_lookup_path:, dry_run: false)
    @input_file           = input_file
    @output_dir           = output_dir
    @customer_lookup_path = customer_lookup_path
    @org_lookup_path      = org_lookup_path
    @domain_lookup_path   = domain_lookup_path
    @dry_run              = dry_run

    @customer_lookup = load_lookup(@customer_lookup_path, 'customer')
    @org_lookup      = load_lookup(@org_lookup_path, 'org')
    @domain_lookup   = load_lookup(@domain_lookup_path, 'domain')

    @stats = {
      records_read: 0,
      records_processed: 0,
      records_skipped: 0,
      indexes_created: 0,
      instance_indexes: 0,
      expiration_indexes: 0,
      lookup_indexes: 0,
      customer_indexes: 0,
      org_indexes: 0,
      domain_indexes: 0,
      errors: [],
      missing_customer_lookups: 0,
      missing_org_lookups: 0,
      missing_domain_lookups: 0,
      anonymous_receipts: 0,
    }
  end

  def run
    validate_input_file
    return print_dry_run_summary if @dry_run

    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, OUTPUT_FILENAME)

    File.open(output_file, 'w') do |out|
      process_input_file(out)
    end

    print_summary(output_file)
    @stats
  end

  private

  def load_lookup(path, name)
    return {} if path.nil? || path.empty?

    unless File.exist?(path)
      warn "Warning: #{name} lookup file not found: #{path}"
      return {}
    end

    data = JSON.parse(File.read(path))
    puts "Loaded #{data.size} entries from #{name} lookup"
    data
  rescue JSON::ParserError => ex
    warn "Error parsing #{name} lookup file: #{ex.message}"
    {}
  end

  def validate_input_file
    raise "Input file not found: #{@input_file}" unless File.exist?(@input_file)
  end

  def print_dry_run_summary
    puts "DRY RUN: Would process #{@input_file}"
    puts "         Output to: #{File.join(@output_dir, OUTPUT_FILENAME)}"
    puts "         Customer lookup: #{@customer_lookup.size} entries"
    puts "         Org lookup: #{@org_lookup.size} entries"
    puts "         Domain lookup: #{@domain_lookup.size} entries"

    # Count records
    count                              = 0
    File.foreach(@input_file) { count += 1 }
    puts "         Input records: #{count}"
  end

  def process_input_file(out)
    # Connect to Redis temp DB for decode operations (DB 15 for safety)
    redis = Redis.new(url: 'redis://127.0.0.1:6379/15')

    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      process_record(line.strip, out, redis)
    end
  rescue StandardError => ex
    @stats[:errors] << { error: ex.message, backtrace: ex.backtrace.first(3) }
  ensure
    redis&.close
  end

  def process_record(line, out, redis)
    return if line.empty?

    record = JSON.parse(line)

    # Only process :object keys (skip indexes, etc.)
    key = record['key']
    return unless key&.end_with?(':object')

    # Extract objid from key pattern: metadata:{objid}:object
    objid = extract_objid(key)
    return unless objid

    # Decode the dump to get field values
    fields = decode_dump(record['dump'], redis)
    return if fields.nil?

    # Use 'created' from the dump record (extracted during dump_keys.rb)
    # or fall back to decoded fields
    created = record['created'] || fields['created']&.to_i
    return unless created

    # Generate index commands
    commands = generate_index_commands(objid, fields, created)

    commands.each do |cmd|
      out.puts(JSON.generate(cmd))
      @stats[:indexes_created] += 1
    end

    @stats[:records_processed] += 1
  rescue JSON::ParserError => ex
    @stats[:records_skipped] += 1
    @stats[:errors] << { line: @stats[:records_read], error: "JSON parse error: #{ex.message}" }
  rescue StandardError => ex
    @stats[:records_skipped] += 1
    @stats[:errors] << { line: @stats[:records_read], error: ex.message }
  end

  def extract_objid(key)
    # Pattern: metadata:{objid}:object
    match = key.match(/^metadata:([^:]+):object$/)
    match ? match[1] : nil
  end

  def decode_dump(dump_base64, redis)
    return nil if dump_base64.nil? || dump_base64.empty?

    # Use a temporary key to restore and read the dump
    temp_key  = "temp:decode:#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(dump_base64)

    # RESTORE the dump to a temporary key (0 = no TTL)
    redis.restore(temp_key, 0, dump_data)

    # Read all hash fields
    fields = redis.hgetall(temp_key)

    # Clean up
    redis.del(temp_key)

    fields
  rescue StandardError => ex
    @stats[:errors] << { error: "Decode error: #{ex.message}" }
    nil
  end

  def generate_index_commands(objid, fields, created)
    commands = []

    # 1. Instance Index: receipt:instances
    commands << {
      command: 'ZADD',
      key: 'receipt:instances',
      args: [created.to_i, objid],
    }
    @stats[:instance_indexes] += 1

    # 2. Expiration Timeline: receipt:expiration_timeline
    secret_ttl = fields['secret_ttl']&.to_i
    if secret_ttl && secret_ttl > 0 && created
      expires_at                   = created + secret_ttl
      commands << {
        command: 'ZADD',
        key: 'receipt:expiration_timeline',
        args: [expires_at.to_i, objid],
      }
      @stats[:expiration_indexes] += 1
    end

    # 3. Lookup Index: receipt:objid_lookup
    commands << {
      command: 'HSET',
      key: 'receipt:objid_lookup',
      args: [objid, objid.to_json],
    }
    @stats[:lookup_indexes] += 1

    # 4. Transform custid -> owner_id and create relationship indexes
    custid   = fields['custid']
    owner_id = resolve_owner_id(custid)

    # Customer receipts (if not anonymous)
    if owner_id && owner_id != 'anon'
      commands << {
        command: 'ZADD',
        key: "customer:#{owner_id}:receipts",
        args: [created.to_i, objid],
      }
      @stats[:customer_indexes] += 1

      # Organization receipts (derive org_id from owner_id)
      org_id = resolve_org_id(owner_id)
      if org_id
        commands << {
          command: 'ZADD',
          key: "organization:#{org_id}:receipts",
          args: [created.to_i, objid],
        }
        @stats[:org_indexes] += 1
      end
    else
      @stats[:anonymous_receipts] += 1
    end

    # 5. Domain participation (if share_domain set)
    share_domain = fields['share_domain']
    if share_domain && !share_domain.empty?
      domain_id = resolve_domain_id(share_domain)
      if domain_id
        commands << {
          command: 'ZADD',
          key: "customdomain:#{domain_id}:receipts",
          args: [created.to_i, objid],
        }
        @stats[:domain_indexes] += 1
      end
    end

    commands
  end

  def resolve_owner_id(custid)
    return 'anon' if custid.nil? || custid.empty? || custid == 'anon'

    # Look up email -> objid
    owner_id = @customer_lookup[custid]
    if owner_id.nil?
      @stats[:missing_customer_lookups] += 1
      # Return nil to skip customer index, but continue processing
      return nil
    end

    owner_id
  end

  def resolve_org_id(owner_id)
    return nil if owner_id.nil? || owner_id.empty?

    org_id = @org_lookup[owner_id]
    if org_id.nil?
      @stats[:missing_org_lookups] += 1
    end

    org_id
  end

  def resolve_domain_id(fqdn)
    return nil if fqdn.nil? || fqdn.empty?

    domain_id = @domain_lookup[fqdn]
    if domain_id.nil?
      @stats[:missing_domain_lookups] += 1
    end

    domain_id
  end

  def print_summary(output_file)
    puts "\n=== Receipt Index Creation Summary ==="
    puts "Input:  #{@input_file}"
    puts "Output: #{output_file}"
    puts
    puts 'Records:'
    puts "  Read:      #{@stats[:records_read]}"
    puts "  Processed: #{@stats[:records_processed]}"
    puts "  Skipped:   #{@stats[:records_skipped]}"
    puts
    puts "Indexes created: #{@stats[:indexes_created]}"
    puts "  Instance (receipt:instances):           #{@stats[:instance_indexes]}"
    puts "  Expiration (receipt:expiration_timeline): #{@stats[:expiration_indexes]}"
    puts "  Lookup (receipt:objid_lookup):          #{@stats[:lookup_indexes]}"
    puts "  Customer (customer:{id}:receipts):      #{@stats[:customer_indexes]}"
    puts "  Org (organization:{id}:receipts):       #{@stats[:org_indexes]}"
    puts "  Domain (customdomain:{id}:receipts):    #{@stats[:domain_indexes]}"
    puts
    puts 'Ownership:'
    puts "  Anonymous receipts: #{@stats[:anonymous_receipts]}"
    puts "  Missing customer lookups: #{@stats[:missing_customer_lookups]}"
    puts "  Missing org lookups: #{@stats[:missing_org_lookups]}"
    puts "  Missing domain lookups: #{@stats[:missing_domain_lookups]}"

    return unless @stats[:errors].any?

    puts
    puts 'Errors (first 10):'
    @stats[:errors].first(10).each do |err|
      puts "  #{err}"
    end
  end
end

def parse_args(args)
  options = {
    input_file: ReceiptIndexCreator::DEFAULT_INPUT,
    output_dir: ReceiptIndexCreator::DEFAULT_OUTPUT_DIR,
    customer_lookup: nil,
    org_lookup: nil,
    domain_lookup: nil,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/
      options[:input_file] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when /^--customer-lookup=(.+)$/
      options[:customer_lookup] = Regexp.last_match(1)
    when /^--org-lookup=(.+)$/
      options[:org_lookup] = Regexp.last_match(1)
    when /^--domain-lookup=(.+)$/
      options[:domain_lookup] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/create_indexes_receipt.rb [OPTIONS]

        Creates V2 index commands for Receipt model from V1 metadata dump.

        Options:
          --input-file=PATH      Input JSONL (default: exports/metadata/metadata_dump.jsonl)
          --output-dir=DIR       Output directory (default: exports/receipt)
          --customer-lookup=PATH JSON file mapping email -> customer objid
          --org-lookup=PATH      JSON file mapping customer objid -> org objid
          --domain-lookup=PATH   JSON file mapping fqdn -> domain id
          --dry-run              Show what would be created
          --help                 Show this help

        Lookup file formats:
          customer-lookup: {"user@example.com": "objid123", ...}
          org-lookup:      {"customer_objid": "org_objid", ...}
          domain-lookup:   {"secrets.example.com": "domainid456", ...}

        Output: JSONL with Redis commands (ZADD, HSET)

        Indexes created:
          - receipt:instances (sorted set: score=created, member=objid)
          - receipt:expiration_timeline (sorted set: score=expires_at, member=objid)
          - receipt:objid_lookup (hash: objid -> "objid" JSON)
          - customer:{owner_id}:receipts (sorted set, if not anonymous)
          - organization:{org_id}:receipts (sorted set, if owner has org)
          - customdomain:{domain_id}:receipts (sorted set, if share_domain set)
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

  creator = ReceiptIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    customer_lookup_path: options[:customer_lookup],
    org_lookup_path: options[:org_lookup],
    domain_lookup_path: options[:domain_lookup],
    dry_run: options[:dry_run],
  )

  creator.run
end
