#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates CustomDomain indexes from dump file.
# Reads JSONL dump, decodes Redis DUMP data, extracts fields,
# and outputs index commands as JSONL.
#
# Usage:
#   ruby scripts/migrations/jan24/create_indexes_customdomain.rb [OPTIONS]
#
# Options:
#   --input-file=FILE       Input JSONL dump file (default: data/upgrades/v0.24.0/customdomain/customdomain_dump.jsonl)
#   --output-dir=DIR        Output directory (default: data/upgrades/v0.24.0/customdomain)
#   --customer-lookup=FILE  Email->org_objid JSON map (default: data/upgrades/v0.24.0/organization/email_to_org_objid.json)
#   --redis-url=URL         Redis URL for temporary restore (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N             Temporary database for restore operations (default: 15)
#   --dry-run               Parse and count without writing output
#
# Output: customdomain_indexes.jsonl with Redis commands for:
#   - custom_domain:instances (ZADD) - sorted set by created timestamp
#   - custom_domain:display_domain_index (HSET) - fqdn -> "domainid"
#   - custom_domain:display_domains (HSET) - fqdn -> "domainid" (compat)
#   - custom_domain:extid_lookup (HSET) - extid -> "domainid"
#   - custom_domain:objid_lookup (HSET) - domainid -> "domainid"
#   - custom_domain:owners (HSET) - domainid -> "org_id"
#   - organization:{org_id}:domains (ZADD) - org participation

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'uri'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.0/03-customdomain/create_indexes.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class CustomDomainIndexCreator
  TEMP_KEY_PREFIX = '_migrate_tmp_'

  def initialize(input_file:, output_dir:, customer_lookup_file:, redis_url:, temp_db:, dry_run: false)
    @input_file           = input_file
    @output_dir           = output_dir
    @customer_lookup_file = customer_lookup_file
    @redis_url            = redis_url
    @temp_db              = temp_db
    @dry_run              = dry_run
    @redis                = nil

    @customer_to_org = load_customer_lookup

    @stats = {
      records_read: 0,
      objects_processed: 0,
      instance_index_source: nil,
      instance_entries: 0,
      display_domain_lookups: 0,
      extid_lookups: 0,
      objid_lookups: 0,
      owner_mappings: 0,
      org_participation: 0,
      skipped: 0,
      missing_org_lookup: 0,
      missing_org_details: [],  # Details of domains missing org lookup
      errors: [],
    }
  end

  def run
    validate_input_file
    connect_redis unless @dry_run

    commands = []

    # Process the dump file
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line, symbolize_names: true)

      # Skip GLOBAL singleton records (should not be indexed as custom domains)
      if record[:key]&.include?(':GLOBAL:') || record[:key]&.include?(':GLOBAL_STATS:')
        @stats[:skipped] += 1
        next
      end

      case record[:key]
      when 'customdomain:values'
        # Existing instance index - rename it
        commands.concat(process_instance_index(record))
      when /:object$/
        # CustomDomain object hash - extract fields for indexes
        commands.concat(process_customdomain_object(record))
      else
        @stats[:skipped] += 1
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: "JSON parse error: #{ex.message}" }
    end

    # Instance index is always generated from V2 objects (V1 hex IDs != V2 UUIDs)
    @stats[:instance_index_source] = 'generated'

    # Write output
    write_output(commands) unless @dry_run

    print_summary
    @stats
  ensure
    cleanup_redis
  end

  private

  def load_customer_lookup
    if @customer_lookup_file.nil? || @customer_lookup_file.empty?
      raise ArgumentError, 'Customer lookup file is required (--customer-lookup or default)'
    end

    unless File.exist?(@customer_lookup_file)
      raise ArgumentError, "Customer lookup file not found: #{@customer_lookup_file}"
    end

    data = JSON.parse(File.read(@customer_lookup_file))
    puts "Loaded #{data.size} email->org mappings from #{@customer_lookup_file}"
    data
  end

  def validate_input_file
    unless File.exist?(@input_file)
      raise ArgumentError, "Input file not found: #{@input_file}"
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

  # Read V1 ZSET for validation/reporting only. Members are V1 hex IDs which
  # don't match V2 UUIDs, so the actual instance index must be generated from
  # transformed objects (the "generated" path in process_customdomain_object).
  def process_instance_index(record)
    return [] if @dry_run

    temp_key  = "#{TEMP_KEY_PREFIX}instance_index"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      members_with_scores = @redis.zrange(temp_key, 0, -1, with_scores: true)
      @stats[:v1_instance_members] = members_with_scores.size
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record[:key], error: "Restore failed: #{ex.message}" }
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end

    [] # No commands — V2 index is generated from objects
  end

  def process_customdomain_object(record)
    commands                    = []
    @stats[:objects_processed] += 1

    if @dry_run
      return commands
    end

    # Use enriched objid/extid from JSONL record (set by enrich_with_identifiers.rb)
    objid = record[:objid]
    extid = record[:extid]

    # Extract identifier from key (custom_domain:{id}:object)
    key_parts = record[:key].split(':')
    return commands if key_parts.size < 3

    # Restore hash to temp key and read fields
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      fields = @redis.hgetall(temp_key)

      # Use enriched objid, or fall back to domainid from hash/key
      domainid = objid || fields['domainid'] || key_parts[1]

      # Use enriched extid, or fall back to hash field
      extid ||= fields['extid']

      display_domain = fields['display_domain']
      custid         = fields['custid']
      created        = record[:created] || fields['created']

      return commands if domainid.nil? || domainid.empty?

      # Resolve custid -> org_id
      org_id = resolve_org_id(
        custid,
        {
          domainid: domainid,
          extid: extid,
          display_domain: display_domain,
          created: created,
        },
      )

      created_ts = created.to_i
      created_ts = Time.now.to_i if created_ts.zero?

      # Instance index entry (if not using existing index)
      if @stats[:instance_index_source] != 'existing'
        commands << {
          command: 'ZADD',
          key: 'custom_domain:instances',
          args: [created_ts.to_i, domainid],
        }
        @stats[:instance_entries] += 1
      end

      # Display domain lookups
      if display_domain && !display_domain.empty?
        commands << {
          command: 'HSET',
          key: 'custom_domain:display_domain_index',
          args: [display_domain, domainid.to_json],
        }
        commands << {
          command: 'HSET',
          key: 'custom_domain:display_domains',
          args: [display_domain, domainid.to_json],
        }
        @stats[:display_domain_lookups] += 1
      end

      # ExtID lookup (only if extid available)
      if extid && !extid.empty?
        commands << {
          command: 'HSET',
          key: 'custom_domain:extid_lookup',
          args: [extid, domainid.to_json],
        }
        @stats[:extid_lookups] += 1
      end

      # ObjID lookup (domainid = objid for customdomain)
      commands << {
        command: 'HSET',
        key: 'custom_domain:objid_lookup',
        args: [domainid, domainid.to_json],
      }
      @stats[:objid_lookups] += 1

      # Owner mapping (domainid -> org_id)
      if org_id
        commands << {
          command: 'HSET',
          key: 'custom_domain:owners',
          args: [domainid, org_id.to_json],
        }
        @stats[:owner_mappings] += 1

        # Organization participation
        commands << {
          command: 'ZADD',
          key: "organization:#{org_id}:domains",
          args: [created_ts.to_i, domainid],
        }
        @stats[:org_participation] += 1
      end
    rescue Redis::CommandError => ex
      @stats[:errors] << { key: record[:key], error: "Restore failed: #{ex.message}" }
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end

    commands
  end

  def resolve_org_id(custid, domain_info = {})
    return nil if custid.nil? || custid.empty?

    # Look up custid (email) -> org_id
    org_id = @customer_to_org[custid]
    if org_id.nil?
      @stats[:missing_org_lookup] += 1
      @stats[:missing_org_details] << domain_info.merge(custid: custid)
    end

    org_id
  end

  def write_output(commands)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'customdomain_indexes.jsonl')

    File.open(output_file, 'w') do |f|
      commands.each do |cmd|
        f.puts(JSON.generate(cmd))
      end
    end

    puts "Wrote #{commands.size} commands to #{output_file}"
  end

  def print_summary
    puts "\n=== CustomDomain Index Creation Summary ==="
    puts "Input file: #{@input_file}"
    puts "Records read: #{@stats[:records_read]}"
    puts "Objects processed: #{@stats[:objects_processed]}"
    puts "Skipped records: #{@stats[:skipped]}"
    puts

    puts 'Instance Index:'
    puts "  Source: #{@stats[:instance_index_source] || 'none'}"
    puts "  Entries: #{@stats[:instance_entries]}"
    if @stats[:v1_instance_members]
      puts "  V1 ZSET members: #{@stats[:v1_instance_members]} (read-only, not used for V2 index)"
    end
    puts

    puts 'Lookup Indexes:'
    puts "  Display domain lookups: #{@stats[:display_domain_lookups]}"
    puts "  ExtID lookups: #{@stats[:extid_lookups]}"
    puts "  ObjID lookups: #{@stats[:objid_lookups]}"
    puts

    puts 'Relationships:'
    puts "  Owner mappings: #{@stats[:owner_mappings]}"
    puts "  Organization participation: #{@stats[:org_participation]}"
    puts "  Missing org lookups: #{@stats[:missing_org_lookup]}"
    puts

    # Detail missing org lookups
    if @stats[:missing_org_details].any?
      puts '=== Domains Missing Org Lookup ==='
      @stats[:missing_org_details].each do |detail|
        puts "  #{detail[:display_domain] || detail[:domainid]}"
        puts "    custid: #{detail[:custid]}"
        puts "    domainid: #{detail[:domainid]}"
        puts "    extid: #{detail[:extid]}"
      end
      puts
    end

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each do |err|
      puts "  #{err}"
    end
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'customdomain/customdomain_dump.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'customdomain'),
    customer_lookup: 'data/upgrades/v0.24.0/organization/email_to_org_objid.json',
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
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
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/create_indexes_customdomain.rb [OPTIONS]

        Creates CustomDomain indexes from dump file.

        Options:
          --input-file=FILE       Input JSONL dump (default: data/upgrades/v0.24.0/customdomain/customdomain_dump.jsonl)
          --output-dir=DIR        Output directory (default: data/upgrades/v0.24.0/customdomain)
          --customer-lookup=FILE  Email->org_objid JSON map (default: data/upgrades/v0.24.0/organization/email_to_org_objid.json)
          --redis-url=URL         Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
          --temp-db=N             Temp database number (default: 15)
          --dry-run               Parse without writing output
          --help                  Show this help

        Output file: customdomain_indexes.jsonl

        Index commands generated:
          ZADD custom_domain:instances <score> <domainid>
          HSET custom_domain:display_domain_index <fqdn> "<domainid>"
          HSET custom_domain:display_domains <fqdn> "<domainid>"
          HSET custom_domain:extid_lookup <extid> "<domainid>"
          HSET custom_domain:objid_lookup <domainid> "<domainid>"
          HSET custom_domain:owners <domainid> "<org_id>"
          ZADD organization:{org_id}:domains <score> <domainid>
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

  creator = CustomDomainIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    customer_lookup_file: options[:customer_lookup],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )

  creator.run
end
