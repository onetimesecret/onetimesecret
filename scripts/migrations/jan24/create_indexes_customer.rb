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
#   --input-file=FILE   Input JSONL dump file (default: exports/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports/customer)
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

    commands = []

    # Process the dump file
    File.foreach(@input_file) do |line|
      @stats[:records_read] += 1
      record                 = JSON.parse(line, symbolize_names: true)

      case record[:key]
      when 'onetime:customer'
        # Existing instance index - rename it
        commands.concat(process_instance_index(record))
      when /:object$/
        # Customer object hash - extract fields for indexes
        commands.concat(process_customer_object(record))
      else
        @stats[:skipped] += 1
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { line: @stats[:records_read], error: "JSON parse error: #{ex.message}" }
    end

    # If no instance index was found, generate from objects
    if @stats[:instance_index_source].nil?
      @stats[:instance_index_source] = 'generated'
      # Instance entries already added during object processing
    end

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
    # The onetime:customer sorted set exists - we'll rename it
    @stats[:instance_index_source] = 'existing'

    commands = []

    if @dry_run
      # Can't decode without Redis, just note it exists
      @stats[:instance_entries] = 'unknown (dry-run)'
      return commands
    end

    # Restore to temp key, read members, generate ZADD commands
    temp_key  = "#{TEMP_KEY_PREFIX}instance_index"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      members_with_scores = @redis.zrange(temp_key, 0, -1, with_scores: true)

      members_with_scores.each do |member, score|
        commands << {
          command: 'ZADD',
          key: 'customer:instances',
          args: [score.to_i, member],
        }
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

  def process_customer_object(record)
    commands                    = []
    @stats[:objects_processed] += 1

    if @dry_run
      # Can't decode without Redis
      return commands
    end

    # Extract identifier from key (customer:{id}:object)
    key_parts = record[:key].split(':')
    return commands if key_parts.size < 3

    # Restore hash to temp key and read fields
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      fields = @redis.hgetall(temp_key)

      # Extract identifier - V2 uses objid, V1 uses custid (which equals email)
      identifier = fields['objid']
      identifier = fields['custid'] if identifier.nil? || identifier.empty?

      email   = fields['email']
      extid   = fields['extid']
      role    = fields['role']
      created = fields['created'] || record[:created]

      # Skip if no identifier found
      if identifier.nil? || identifier.empty?
        @stats[:skipped] += 1
        return commands
      end

      # Instance index entry (if not using existing index)
      if @stats[:instance_index_source] != 'existing'
        created_ts = created.to_i
        created_ts = Time.now.to_i if created_ts.zero?

        commands << {
          command: 'ZADD',
          key: 'customer:instances',
          args: [created_ts.to_i, identifier],
        }
        @stats[:instance_entries] += 1
      end

      # Email lookup
      if email && !email.empty?
        commands << {
          command: 'HSET',
          key: 'customer:email_index',
          args: [email, identifier.to_json],
        }
        @stats[:email_lookups] += 1
      end

      # ExtID lookup (may not exist in V1 data)
      if extid && !extid.empty?
        commands << {
          command: 'HSET',
          key: 'customer:extid_lookup',
          args: [extid, identifier.to_json],
        }
        @stats[:extid_lookups] += 1
      end

      # ObjID lookup (self-reference for consistency)
      commands << {
        command: 'HSET',
        key: 'customer:objid_lookup',
        args: [identifier, identifier.to_json],
      }
      @stats[:objid_lookups] += 1

      # Role index
      if role && VALID_ROLES.include?(role)
        commands << {
          command: 'SADD',
          key: "customer:role_index:#{role}",
          args: [identifier],
        }
        @stats[:role_entries][role] += 1
      end

      # Accumulate counters
      COUNTER_FIELDS.each do |field|
        value                     = fields[field].to_i
        @stats[:counters][field] += value if value > 0
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

    puts "Wrote #{commands.size} commands to #{output_file}"
  end

  def print_summary
    puts "\n=== Customer Index Creation Summary ==="
    puts "Input file: #{@input_file}"
    puts "Records read: #{@stats[:records_read]}"
    puts "Objects processed: #{@stats[:objects_processed]}"
    puts "Skipped records: #{@stats[:skipped]}"
    puts

    puts 'Instance Index:'
    puts "  Source: #{@stats[:instance_index_source] || 'none'}"
    puts "  Entries: #{@stats[:instance_entries]}"
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
    input_file: 'exports/customer/customer_dump.jsonl',
    output_dir: 'exports/customer',
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
          --input-file=FILE   Input JSONL dump (default: exports/customer/customer_dump.jsonl)
          --output-dir=DIR    Output directory (default: exports/customer)
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
  require 'securerandom'

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
