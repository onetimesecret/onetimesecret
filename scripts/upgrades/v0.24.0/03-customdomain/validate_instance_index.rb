#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that custom_domain:instances zset is consistent with the v1
# customdomain:values set, and that the ownership has been correctly
# migrated from a customer to an organization.
#
# This script verifies:
# 1. The number of domains in the new index matches the old one.
# 2. Each domain in the new index has a corresponding custom_domain object.
# 3. The score (timestamp) matches the object's created field.
# 4. The org_id correctly maps back to the original customer's email.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/03-customdomain/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump (default: results/customdomain/customdomain_dump.jsonl)
#   --redis-url=URL     Redis URL for temp restore (default: redis://127.0.0.1:6379)
#   --temp-db=N         Temp database number (default: 15)

require 'redis'
require 'json'
require 'base64'

class CustomDomainInstanceIndexValidator
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

    # 1. Extract data from dump
    v1_index, v2_index, domain_objects, org_lookup = parse_dump_file

    unless v1_index
      puts 'ERROR: customdomain:values (v1 index) not found in dump'
      return false
    end
    unless v2_index
      puts 'ERROR: custom_domain:instances (v2 index) not found in dump'
      return false
    end
    unless org_lookup
      puts 'ERROR: organization:contact_email_index not found in dump'
      return false
    end

    # 2. Decode the data
    v1_domain_ids          = decode_set_index(v1_index, 'v1_domain_index')
    v2_domains_with_scores = decode_zset_index(v2_index, 'v2_domain_index')
    org_email_to_objid_map = decode_hash(org_lookup, 'org_email_lookup')

    puts "Found #{v1_domain_ids.size} members in customdomain:values"
    puts "Found #{v2_domains_with_scores.size} members in custom_domain:instances"
    puts "Found #{org_email_to_objid_map.size} entries in organization:contact_email_index"
    puts

    # 3. Compare and validate
    results = compare_and_validate(v1_domain_ids, v2_domains_with_scores, domain_objects, org_email_to_objid_map)

    # 4. Report
    print_report(results)

    results[:count_mismatch].zero? && results[:missing_objects].empty? && results[:relationship_errors].empty?
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
    v1_index       = nil
    v2_index       = nil
    domain_objects = {}
    org_lookup     = nil

    File.foreach(@input_file) do |line|
      record = JSON.parse(line, symbolize_names: true)

      case record[:key]
      when 'customdomain:values'
        v1_index = record
      when 'custom_domain:instances'
        v2_index = record
      when 'organization:contact_email_index'
        org_lookup = record
      when /^custom_domain:([a-zA-Z0-9-]+):object$/
        objid                 = Regexp.last_match(1)
        domain_objects[objid] = record
      end
    end

    [v1_index, v2_index, domain_objects, org_lookup]
  end

  def decode_set_index(record, name)
    temp_key  = "#{TEMP_KEY_PREFIX}#{name}"
    dump_data = Base64.strict_decode64(record[:dump])
    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      Set.new(@redis.smembers(temp_key))
    ensure
      @redis.del(temp_key) if @redis
    end
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

  def decode_hash(record, name)
    temp_key  = "#{TEMP_KEY_PREFIX}#{name}"
    dump_data = Base64.strict_decode64(record[:dump])
    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      @redis.hgetall(temp_key)
    ensure
      @redis.del(temp_key) if @redis
    end
  end

  def compare_and_validate(v1_ids, v2_with_scores, objects, org_map)
    results = {
      matches: 0,
      timestamp_mismatches: [],
      missing_objects: [],
      relationship_errors: [],
      count_mismatch: v1_ids.size - v2_with_scores.size,
      missing_from_v1: [],
    }

    v2_with_scores.each do |objid, score|
      unless v1_ids.include?(objid)
        results[:missing_from_v1] << objid
      end

      domain = objects[objid]

      unless domain
        results[:missing_objects] << { objid: objid, score: score.to_i }
        next
      end

      # Check created timestamp
      if score.to_i == domain[:created].to_i
        results[:matches] += 1
      else
        results[:timestamp_mismatches] << { objid: objid, index_score: score.to_i, object_created: domain[:created] }
      end

      # Check ownership relationship
      v1_custid            = domain[:v1_custid]
      org_id               = domain[:org_id]
      expected_org_id_json = org_map[v1_custid]

      if expected_org_id_json.nil?
        results[:relationship_errors] << { objid: objid, v1_custid: v1_custid, reason: 'Original customer email not in org lookup index' }
      else
        expected_org_id = JSON.parse(expected_org_id_json)
        unless org_id == expected_org_id
          results[:relationship_errors] << { objid: objid, v1_custid: v1_custid, expected: expected_org_id, actual: org_id, reason: 'org_id mismatch' }
        end
      end
    end

    results
  end

  def print_report(results)
    puts '=== Validation Results ==='
    puts "Count Match (v1 vs v2 index): #{results[:count_mismatch].zero? ? 'OK' : "FAIL (Difference: #{results[:count_mismatch]})"}"
    puts "Verified (objid exists, score ok): #{results[:matches]}"
    puts "Missing from v1 index: #{results[:missing_from_v1].size}"
    puts "Missing custom_domain objects: #{results[:missing_objects].size}"
    puts "Timestamp mismatches: #{results[:timestamp_mismatches].size}"
    puts "Ownership relationship errors: #{results[:relationship_errors].size}"
    puts

    return unless results[:relationship_errors].any?

    puts '=== Ownership Relationship Errors (first 5) ==='
    results[:relationship_errors].first(5).each do |err|
      puts "  Domain #{err[:objid]} (owner: #{err[:v1_custid]}): #{err[:reason]}"
      puts "    Expected org_id: #{err[:expected]}, Got: #{err[:actual]}" if err[:reason] == 'org_id mismatch'
    end
    puts

    # Add other report sections if needed
  end
end

def parse_args(args)
  options = {
    input_file: 'results/customdomain/customdomain_dump.jsonl',
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
        Usage: ruby scripts/upgrades/v0.24.0/03-customdomain/validate_instance_index.rb [OPTIONS]

        Validates custom_domain:instances index and ownership migration.

        Options:
          --input-file=FILE   Input JSONL dump (default: results/customdomain/customdomain_dump.jsonl)
          --redis-url=URL     Redis URL for temp restore (default: redis://127.0.0.1:6379)
          --temp-db=N         Temp database number (default: 15)
          --help              Show this help

        Validates:
          - The count of domains in v2 index matches v1.
          - Each domain has a corresponding object.
          - Index scores match object created timestamps.
          - Ownership (org_id) correctly maps from the original customer.
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

  validator = CustomDomainInstanceIndexValidator.new(
    input_file: options[:input_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
