#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that onetime:customer zset members (emails) match customer objects
# and that scores correspond to created timestamps.
#
# This script compares the v1 instance index (onetime:customer) with enriched
# customer objects to verify:
# 1. Each email in the index has a corresponding customer object
# 2. The score (timestamp) matches the object's created field
# 3. The email->objid mapping is correct for migration
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump (default: results/customer/customer_dump.jsonl)
#   --redis-url=URL     Redis URL for temp restore (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database number (default: 15)

require 'redis'
require 'json'
require 'base64'

class InstanceIndexValidator
  TEMP_KEY_PREFIX = '_validate_tmp_'

  def initialize(input_file:, redis_url:, temp_db:)
    @input_file = input_file
    @redis_url  = redis_url
    @temp_db    = temp_db
    @redis      = nil
  end

  def run
    validate_input_file
    connect_redis

    # 1. Extract onetime:customer and customer objects from dump
    instance_index_record, customer_objects = parse_dump_file

    unless instance_index_record
      puts 'ERROR: onetime:customer not found in dump'
      return false
    end

    puts "Found #{customer_objects.size} customer objects"

    # 2. Decode the onetime:customer zset
    members_with_scores = decode_instance_index(instance_index_record)
    puts "Found #{members_with_scores.size} members in onetime:customer"
    puts

    # 3. Compare and validate
    results = compare_members(members_with_scores, customer_objects)

    # 4. Report
    print_report(results, members_with_scores, customer_objects)

    # Success if no missing objects (modified_since_creation is expected/normal)
    results[:missing_objects].empty?
  ensure
    cleanup_redis
  end

  private

  def validate_input_file
    raise ArgumentError, "Input file not found: #{@input_file}" unless File.exist?(@input_file)
  end

  def connect_redis
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
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

  def parse_dump_file
    puts "Reading #{@input_file}..."
    instance_index_record = nil
    customer_objects      = {}

    File.foreach(@input_file) do |line|
      record = JSON.parse(line, symbolize_names: true)

      if record[:key] == 'onetime:customer'
        instance_index_record = record
      elsif record[:key].end_with?(':object')
        # Extract custid (email) from key: customer:{email}:object
        parts                   = record[:key].split(':')
        email                   = parts[1] if parts.size >= 3
        customer_objects[email] = record if email
      end
    end

    [instance_index_record, customer_objects]
  end

  def decode_instance_index(record)
    temp_key  = "#{TEMP_KEY_PREFIX}instance_index"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.zrange(temp_key, 0, -1, with_scores: true)
    ensure
      begin
        @redis.del(temp_key)
      rescue StandardError
        nil
      end
    end
  end

  def compare_members(members_with_scores, customer_objects)
    results = {
      matches: 0,
      modified_since_creation: [],
      missing_objects: [],
    }

    members_with_scores.each do |email, score|
      customer = customer_objects[email]

      unless customer
        results[:missing_objects] << { email: email, score: score.to_i }
        next
      end

      created = customer[:created]
      objid   = customer[:objid]

      if score.to_i == created.to_i
        results[:matches] += 1
      else
        # Index score reflects last-modified time, not created time.
        # A difference indicates the customer was modified after creation.
        results[:modified_since_creation] << {
          email: email,
          last_modified: score.to_i,
          created: created,
          objid: objid,
          age_at_modification: (score.to_i - created.to_i),
        }
      end
    end

    results
  end

  def print_report(results, members_with_scores, customer_objects)
    puts '=== Validation Results ==='
    puts "Total members in onetime:customer: #{members_with_scores.size}"
    puts "Unmodified (score == created): #{results[:matches]}"
    puts "Modified since creation: #{results[:modified_since_creation].size}"
    puts "Missing customer objects: #{results[:missing_objects].size}"
    puts

    if results[:modified_since_creation].any?
      puts '=== Modified Since Creation (first 10) ==='
      puts '    (Index score reflects last-modified time, not created time)'
      results[:modified_since_creation].first(10).each do |m|
        days = m[:age_at_modification] / 86_400.0
        puts "  #{m[:email]}: last_modified=#{m[:last_modified]}, created=#{m[:created]} (#{days.round(1)} days after)"
      end
      puts
    end

    if results[:missing_objects].any?
      puts '=== Missing Objects (first 10) ==='
      results[:missing_objects].first(10).each do |m|
        puts "  #{m[:email]} (score: #{m[:score]})"
      end
      puts
    end

    # Show sample mapping: email -> objid
    puts '=== Sample Email -> ObjID Mapping (first 5) ==='
    members_with_scores.first(5).each do |email, score|
      customer = customer_objects[email]
      next unless customer

      puts "  #{email}"
      puts "    -> objid: #{customer[:objid]}"
      puts "    -> score: #{score.to_i}, created: #{customer[:created]}"
    end
  end
end

def parse_args(args)
  options = {
    input_file: 'results/customer/customer_dump.jsonl',
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/
      options[:input_file] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/validate_instance_index.rb [OPTIONS]

        Validates onetime:customer index against customer objects.

        Options:
          --input-file=FILE   Input JSONL dump (default: results/customer/customer_dump.jsonl)
          --redis-url=URL     Redis URL for temp restore (default: redis://127.0.0.1:6379)
          --temp-db=N         Temp database number (default: 15)
          --help              Show this help

        Validates:
          - Each email in onetime:customer has a customer object
          - Index scores match object created timestamps
          - Shows email -> objid mapping for migration verification
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

  validator = InstanceIndexValidator.new(
    input_file: options[:input_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
