#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates customer indexes from dump file.
# Reads JSONL dump, decodes Redis DUMP data via temporary restore, extracts fields,
# and outputs index commands as JSONL.
#
# Usage:
#   ruby scripts/migrations/jan24/create_indexes_customer.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: results/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: results/customer)
#   --redis-url=URL     Redis URL for temporary restore (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temporary database for restore operations (default: 15)
#   --dry-run           Parse and count without writing output
#
# Output: customer_indexes.jsonl with Redis commands for:
#   - customer:instances (ZADD) - sorted set by created timestamp
#   - customer:email_index (HSET) - email -> "objid"
#   - customer:extid_lookup (HSET) - extid -> "objid"
#   - customer:objid_lookup (HSET) - objid -> "objid"
#   - customer:role_index:{role} (SADD) - sets by role
#   - customer:secrets_created (INCRBY) - counter
#   - customer:secrets_shared (INCRBY) - counter
#   - customer:secrets_burned (INCRBY) - counter
#   - customer:emails_sent (INCRBY) - counter

require 'redis'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'

class CustomerIndexCreator
  TEMP_KEY_PREFIX = '_migrate_tmp_'
  COUNTER_FIELDS  = %w[secrets_created secrets_shared secrets_burned emails_sent].freeze
  VALID_ROLES     = %w[colonel customer anonymous].freeze

  def initialize(input_file:, output_dir:, redis_url:, temp_db:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @redis_url  = redis_url
    @temp_db    = temp_db
    @dry_run    = dry_run
    @redis      = nil

    @stats = {
      records_read: 0,
      objects_processed: 0,
      instance_index_source: nil,  # 'existing' or 'generated'
      instance_entries: 0,
      email_lookups: 0,
      extid_lookups: 0,
      objid_lookups: 0,
      role_entries: Hash.new(0),
      counters: Hash.new(0),
      skipped: 0,
      errors: [],
    }
  end

  def run
    validate_input_file
    connect_redis unless @dry_run

    commands                  = []
    instance_index_record     = nil
    customer_object_records   = []
    @email_to_objid           = {}  # Built during object processing for instance index conversion
    @objid_to_created         = {} # For backfilling missing instance entries
    @objids_in_instance_index = Set.new # Track which objids were added from existing index

    # First pass: collect records and detect if onetime:customer exists
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line, symbolize_names: true)

      case record[:key]
      when 'onetime:customer'
        # Store for later processing after we have email->objid mapping
        instance_index_record = record
        @stats[:instance_index_source] = 'existing'
      when /:object$/
        # Collect for processing
        customer_object_records << record
      else
        @stats[:skipped] += 1
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: "JSON parse error: #{ex.message}" }
    end

    # Set source to 'generated' if no existing index found
    @stats[:instance_index_source] ||= 'generated'

    # Second pass: process customer objects (builds email->objid mapping)
    customer_object_records.each do |record|
      commands.concat(process_customer_object(record))
    end

    # Process instance index now that we have email->objid mapping
    if instance_index_record
      commands.concat(process_instance_index(instance_index_record))
      # Backfill any customers missing from the v1 index (fixes data inconsistency)
      commands.concat(backfill_missing_instance_entries)
    end
    # When no instance index exists, entries were added during object processing

    # Add counter commands (aggregate totals)
    commands.concat(generate_counter_commands)

    # Write output
    write_output(commands) unless @dry_run

    print_summary
    @stats
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
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
    # Verify connection and that temp db is usable
    @redis.ping
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

  def process_instance_index(record)
    # The onetime:customer sorted set exists - convert it to customer:instances.
    #
    # v1 used email addresses as zset members; v2 uses objid.
    # We preserve the original scores (created timestamps) but replace
    # email members with their corresponding objid from the mapping
    # built during process_customer_object.
    @stats[:instance_index_source] = 'existing'

    commands = []

    if @dry_run
      # Can't decode without Redis, just note it exists
      @stats[:instance_entries] = 'unknown (dry-run)'
      return commands
    end

    # Restore to temp key, read members, generate ZADD commands with objid
    temp_key  = "#{TEMP_KEY_PREFIX}instance_index"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      members_with_scores = @redis.zrange(temp_key, 0, -1, with_scores: true)

      members_with_scores.each do |email, score|
        # Convert v1 email member to v2 objid member
        objid = @email_to_objid[email]

        unless objid
          @stats[:errors] << { key: record[:key], error: "No objid mapping for email: #{email}" }
          next
        end

        commands << {
          command: 'ZADD',
          key: 'customer:instances',
          args: [score.to_i, objid],
        }
        @objids_in_instance_index << objid
        @stats[:instance_entries] += 1
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

  def backfill_missing_instance_entries
    # Add instance entries for customers that exist but were missing from
    # the v1 onetime:customer index. This fixes data inconsistency in source.
    commands = []

    all_objids     = Set.new(@email_to_objid.values)
    missing_objids = all_objids - @objids_in_instance_index

    missing_objids.each do |objid|
      created_ts = @objid_to_created[objid] || Time.now.to_i
      created_ts = Time.now.to_i if created_ts.zero?

      commands << {
        command: 'ZADD',
        key: 'customer:instances',
        args: [created_ts, objid],
      }
      @stats[:instance_entries]    += 1
      @stats[:backfilled_entries] ||= 0
      @stats[:backfilled_entries]  += 1
    end

    commands
  end

  def process_customer_object(record)
    commands                    = []
    @stats[:objects_processed] += 1

    return commands if @dry_run

    key_parts = record[:key].split(':')
    return commands if key_parts.size < 3

    # Extract v1 custid (email) from key for instance index mapping
    v1_custid = key_parts[1]

    # Use enriched objid/extid from JSONL record, fall back to hash fields
    objid = record[:objid]
    extid = record[:extid]

    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      fields = @redis.hgetall(temp_key)

      objid, extid = resolve_identifiers(objid, extid, fields)
      return commands if objid.nil? || objid.empty?

      # Build email->objid mapping for instance index conversion.
      # v1 used email as custid; we need to map those to objid.
      # NOTE: This intentionally duplicates the email_index logic below. Both
      # read from source material (the key and hash fields) independently,
      # avoiding a mistake in one codepath from affecting another.
      @email_to_objid[v1_custid] = objid

      # Track objid->created for backfilling missing instance entries
      created                  = record[:created] || fields['created']
      @objid_to_created[objid] = created.to_i if created

      build_customer_index_commands(commands, record, fields, objid, extid)
      accumulate_counters(fields)
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

  def resolve_identifiers(objid, extid, fields)
    objid ||= fields['objid']
    objid   = fields['custid'] if objid.nil? || objid.empty?
    extid ||= fields['extid']

    if objid.nil? || objid.empty?
      @stats[:skipped] += 1
    end

    [objid, extid]
  end

  def build_customer_index_commands(commands, record, fields, objid, extid)
    created = record[:created] || fields['created']

    # Instance index entry (if not using existing index)
    if @stats[:instance_index_source] != 'existing'
      created_ts = created.to_i
      created_ts = Time.now.to_i if created_ts.zero?

      commands << { command: 'ZADD', key: 'customer:instances', args: [created_ts.to_i, objid] }
      @stats[:instance_entries] += 1
    end

    # Email lookup
    # NOTE: Values are JSON-encoded (e.g., "\"uuid\"") to match Familia's
    # HashKey storage format which preserves type information via JSON serialization.
    email = fields['email']
    if email && !email.empty?
      commands << { command: 'HSET', key: 'customer:email_index', args: [email, objid.to_json] }
      @stats[:email_lookups] += 1
    end

    # ExtID lookup (JSON-encoded value for Familia HashKey compatibility)
    if extid && !extid.empty?
      commands << { command: 'HSET', key: 'customer:extid_lookup', args: [extid, objid.to_json] }
      @stats[:extid_lookups] += 1
    end

    # ObjID lookup (JSON-encoded value for Familia HashKey compatibility)
    commands << { command: 'HSET', key: 'customer:objid_lookup', args: [objid, objid.to_json] }
    @stats[:objid_lookups] += 1

    # Role index
    role = fields['role']
    if role && VALID_ROLES.include?(role)
      commands << { command: 'SADD', key: "customer:role_index:#{role}", args: [objid] }
      @stats[:role_entries][role] += 1
    end
  end

  def accumulate_counters(fields)
    COUNTER_FIELDS.each do |field|
      value                     = fields[field].to_i
      @stats[:counters][field] += value if value > 0
    end
  end

  def generate_counter_commands
    commands = []

    COUNTER_FIELDS.each do |field|
      total = @stats[:counters][field]
      next if total.zero?

      commands << {
        command: 'INCRBY',
        key: "customer:#{field}",
        args: [total.to_s],
      }
    end

    commands
  end

  def write_output(commands)
    FileUtils.mkdir_p(@output_dir)
    output_file = File.join(@output_dir, 'customer_indexes.jsonl')

    File.open(output_file, 'w') do |f|
      commands.each do |cmd|
        f.puts(JSON.generate(cmd))
      end
    end

    @stats[:indexes_written] = commands.size
    @stats[:lookups_written] = @email_to_objid.size

    # Write email->objid lookup for use by receipt index creation
    lookup_file = File.join(@output_dir, 'email_to_objid.json')
    File.write(lookup_file, JSON.pretty_generate(@email_to_objid))
  end

  def print_summary
    puts "\n=== Customer Index Creation Summary ==="
    puts "Input:  #{@input_file}"
    puts "Output: #{File.join(@output_dir, 'customer_indexes.jsonl')}"
    puts "Lookup: #{File.join(@output_dir, 'email_to_objid.json')}"
    puts
    puts "Records read: #{@stats[:records_read]}"
    puts "Objects processed: #{@stats[:objects_processed]}"
    puts "Skipped records: #{@stats[:skipped]}"
    puts

    puts 'Instance Index:'
    puts "  Source: #{@stats[:instance_index_source] || 'none'}"
    puts "  Entries: #{@stats[:instance_entries]}"
    puts "  Backfilled: #{@stats[:backfilled_entries] || 0}" if @stats[:instance_index_source] == 'existing'
    puts

    puts 'Lookup Indexes:'
    puts "  Email lookups: #{@stats[:email_lookups]}"
    puts "  ExtID lookups: #{@stats[:extid_lookups]}"
    puts "  ObjID lookups: #{@stats[:objid_lookups]}"
    puts

    puts 'Role Index:'
    @stats[:role_entries].each do |role, count|
      puts "  #{role}: #{count}"
    end
    puts '  (no role entries)' if @stats[:role_entries].empty?
    puts

    puts 'Class Counters:'
    COUNTER_FIELDS.each do |field|
      puts "  #{field}: #{@stats[:counters][field]}"
    end
    puts

    puts 'Written:'
    puts "  Index commands: #{@stats[:indexes_written]}"
    puts "  Email->objid mappings: #{@stats[:lookups_written]}"
    puts

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
    input_file: 'results/customer/customer_dump.jsonl',
    output_dir: 'results/customer',
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/
      options[:input_file] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/create_indexes_customer.rb [OPTIONS]

        Creates customer indexes from dump file.

        Options:
          --input-file=FILE   Input JSONL dump (default: results/customer/customer_dump.jsonl)
          --output-dir=DIR    Output directory (default: results/customer)
          --redis-url=URL     Redis URL for temp restore (default: redis://127.0.0.1:6379)
          --temp-db=N         Temp database number (default: 15)
          --dry-run           Parse without writing output
          --help              Show this help

        Output file: customer_indexes.jsonl

        Index commands generated:
          ZADD customer:instances <score> <objid>
          HSET customer:email_index <email> "<objid>"
          HSET customer:extid_lookup <extid> "<objid>"
          HSET customer:objid_lookup <objid> "<objid>"
          SADD customer:role_index:{role} <objid>
          INCRBY customer:secrets_created <total>
          INCRBY customer:secrets_shared <total>
          INCRBY customer:secrets_burned <total>
          INCRBY customer:emails_sent <total>
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

  creator = CustomerIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
    dry_run: options[:dry_run],
  )

  creator.run
end
