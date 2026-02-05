#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that organization:instances zset is a 1-to-1 match with v1
# customer records, ensuring every customer resulted in a new organization.
#
# This script compares the v2 organization instance index (organization:instances)
# with the v1 customer instance index (onetime:customer) and enriched
# organization objects to verify:
# 1. The number of organizations matches the number of v1 customers.
# 2. Each objid in the index has a corresponding organization object.
# 3. The score (timestamp) matches the object's created field.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/02-organization/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --org-input-file=FILE       Input org JSONL dump (default: results/organization/organization_transformed.jsonl)
#   --customer-input-file=FILE  Input customer JSONL dump (default: results/customer/customer_dump.jsonl)
#   --redis-url=URL             Redis URL for temp restore (default: redis://127.0.0.1:6379)
#   --temp-db=N                 Temp database number (default: 15)

require 'redis'
require 'json'
require 'base64'

class OrganizationInstanceIndexValidator
  TEMP_KEY_PREFIX = '_validate_tmp_'

  def initialize(org_input_file:, customer_input_file:, redis_url:, temp_db:)
    @org_input_file      = org_input_file
    @customer_input_file = customer_input_file
    @redis_url           = redis_url
    @temp_db             = temp_db
    @redis               = nil
  end

  def run
    validate_input_files
    connect_redis

    # 1. Extract indexes and organization objects from dump
    v1_customer_index, v2_org_index, org_objects = parse_dump_files

    unless v1_customer_index
      puts "ERROR: onetime:customer (v1 customer index) not found in #{@customer_input_file}"
      return false
    end

    unless v2_org_index
      puts "ERROR: organization:instances (v2 org index) not found in #{@org_input_file}"
      return false
    end

    puts "Found #{org_objects.size} organization objects"

    # 2. Decode the indexes
    v1_customer_members        = decode_zset_index(v1_customer_index, 'v1_customer_index')
    v2_org_members_with_scores = decode_zset_index(v2_org_index, 'v2_org_index')

    puts "Found #{v1_customer_members.size} members in onetime:customer"
    puts "Found #{v2_org_members_with_scores.size} members in organization:instances"
    puts

    # 3. Compare and validate
    results = compare_and_validate(v1_customer_members, v2_org_members_with_scores, org_objects)

    # 4. Report
    print_report(results)

    # Success if counts match and no missing objects
    results[:count_mismatch].zero? && results[:missing_objects].empty?
  ensure
    cleanup_redis
  end

  private

  def validate_input_files
    raise ArgumentError, "Organization input file not found: #{@org_input_file}" unless File.exist?(@org_input_file)
    raise ArgumentError, "Customer input file not found: #{@customer_input_file}" unless File.exist?(@customer_input_file)
  end

  def connect_redis
    @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
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

  def parse_dump_files
    puts "Reading org data from #{@org_input_file}..."
    v2_org_index = nil
    org_objects  = {}

    File.foreach(@org_input_file) do |line|
      record = JSON.parse(line, symbolize_names: true)

      case record[:key]
      when 'organization:instances'
        v2_org_index = record
      when /^organization:([a-zA-Z0-9-]+):object$/
        objid              = Regexp.last_match(1)
        org_objects[objid] = record
      end
    end

    puts "Reading customer index from #{@customer_input_file}..."
    v1_customer_index = nil
    File.foreach(@customer_input_file) do |line|
      record = JSON.parse(line, symbolize_names: true)
      if record[:key] == 'onetime:customer'
        v1_customer_index = record
        break # Found what we need
      end
    end

    [v1_customer_index, v2_org_index, org_objects]
  end

  def decode_zset_index(record, name)
    temp_key  = "#{TEMP_KEY_PREFIX}#{name}"
    dump_data = Base64.strict_decode64(record[:dump])

    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.zrange(temp_key, 0, -1, with_scores: true)
    ensure
      @redis.del(temp_key) if @redis
    end
  end

  def compare_and_validate(v1_customer_members, v2_org_members_with_scores, org_objects)
    results = {
      matches: 0,
      timestamp_mismatches: [],
      missing_objects: [],
      count_mismatch: v1_customer_members.size - v2_org_members_with_scores.size,
    }

    v2_org_members_with_scores.each do |objid, score|
      org = org_objects[objid]

      unless org
        results[:missing_objects] << { objid: objid, score: score.to_i }
        next
      end

      created = org[:created]

      if score.to_i == created.to_i
        results[:matches] += 1
      else
        results[:timestamp_mismatches] << {
          objid: objid,
          index_score: score.to_i,
          object_created: created,
        }
      end
    end

    results
  end

  def print_report(results)
    puts '=== Validation Results ==='
    puts "1-to-1 Count Match: #{results[:count_mismatch].zero? ? 'OK' : "FAIL (Difference: #{results[:count_mismatch]})"}"
    puts "Verified (objid exists and score == created): #{results[:matches]}"
    puts "Timestamp mismatches: #{results[:timestamp_mismatches].size}"
    puts "Missing organization objects: #{results[:missing_objects].size}"
    puts

    if results[:timestamp_mismatches].any?
      puts '=== Timestamp Mismatches (first 10) ==='
      results[:timestamp_mismatches].first(10).each do |m|
        puts "  Org #{m[:objid]}: index_score=#{m[:index_score]}, object_created=#{m[:object_created]}"
      end
      puts
    end

    return unless results[:missing_objects].any?

    puts '=== Missing Objects (first 10) ==='
    results[:missing_objects].first(10).each do |m|
      puts "  #{m[:objid]} (score: #{m[:score]})"
    end
    puts
  end
end

def parse_args(args)
  options = {
    org_input_file: 'results/organization/organization_transformed.jsonl',
    customer_input_file: 'results/customer/customer_dump.jsonl',
    redis_url: 'redis://127.0.0.1:6379',
    temp_db: 15,
  }

  args.each do |arg|
    case arg
    when /^--org-input-file=(.+)$/
      options[:org_input_file] = Regexp.last_match(1)
    when /^--customer-input-file=(.+)$/
      options[:customer_input_file] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/02-organization/validate_instance_index.rb [OPTIONS]

        Validates organization:instances index against v1 customer records and v2 organization objects.

        Options:
          --org-input-file=FILE       Input org JSONL dump (default: results/organization/organization_transformed.jsonl)
          --customer-input-file=FILE  Input customer JSONL dump (default: results/customer/customer_dump.jsonl)
          --redis-url=URL             Redis URL for temp restore (default: redis://127.0.0.1:6379)
          --temp-db=N                 Temp database number (default: 15)
          --help                      Show this help

        Validates:
          - That the count of organizations matches the count of v1 customers.
          - Each objid in organization:instances has a corresponding organization object.
          - Index scores match object created timestamps.
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

  validator = OrganizationInstanceIndexValidator.new(
    org_input_file: options[:org_input_file],
    customer_input_file: options[:customer_input_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
