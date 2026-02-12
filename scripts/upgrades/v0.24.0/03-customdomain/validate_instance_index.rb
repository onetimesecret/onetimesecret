#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that custom_domain:instances zset is consistent with the v1
# customdomain:values set, and that the ownership has been correctly
# migrated from a customer to an organization.
#
# This script cross-references:
# 1. customdomain_dump.jsonl - V1 customdomain:values set (Redis DUMP blob)
# 2. customdomain_transformed.jsonl - V2 custom_domain objects with org_id
# 3. customdomain_indexes.jsonl - ZADD commands for custom_domain:instances
# 4. organization_indexes.jsonl - HSET commands for organization:contact_email_index
#
# Validations:
# 1. V2 index member count matches V1 set member count
# 2. Each domain in the index has a corresponding custom_domain object (bidirectional)
# 3. Index scores match object created timestamps
# 4. org_id is present and valid (exists in org email index) for each domain
# 5. Key fields (objid, extid, org_id, created) are present
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/03-customdomain/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --dump-file=FILE         V1 dump JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_dump.jsonl)
#   --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_transformed.jsonl)
#   --indexes-file=FILE      Domain indexes JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_indexes.jsonl)
#   --org-indexes-file=FILE  Org indexes JSONL (default: data/upgrades/v0.24.0/organization/organization_indexes.jsonl)
#   --redis-url=URL          Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
#   --temp-db=N              Temp database number (default: 15)

require 'redis'
require 'json'
require 'base64'
require 'set'
require 'uri'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class CustomDomainInstanceIndexValidator
  TEMP_KEY_PREFIX = '_validate_tmp_'
  KEY_FIELDS = %w[objid extid org_id created].freeze

  def initialize(dump_file:, transformed_file:, indexes_file:, org_indexes_file:, redis_url:, temp_db:)
    @dump_file        = dump_file
    @transformed_file = transformed_file
    @indexes_file     = indexes_file
    @org_indexes_file = org_indexes_file
    @redis_url        = redis_url
    @temp_db          = temp_db
    @redis            = nil

    @stats = {
      v1_members: 0,
      index_members: 0,
      transformed_objects: 0,
      org_index_entries: 0,
      matches: 0,
      in_index_not_in_objects: [],
      in_objects_not_in_index: [],
      timestamp_mismatches: [],
      count_mismatch: 0,
      missing_from_v1: [],
      org_id_missing: [],
      org_id_invalid: [],
      field_checks: Hash.new { |h, k| h[k] = { present: 0, missing: 0, missing_objids: [] } },
      errors: [],
    }
  end

  def run
    validate_input_files
    connect_redis

    # 1. Extract V1 domain set from dump (needs Redis RESTORE)
    v1_domain_ids = extract_v1_domain_set
    puts "Found #{v1_domain_ids.size} members in customdomain:values (v1)"

    # 2. Extract V2 index members from ZADD commands
    index_members = extract_index_members
    puts "Found #{index_members.size} members in custom_domain:instances index"

    # 3. Extract domain objects from transformed file
    domain_objects = extract_transformed_objects
    puts "Found #{domain_objects.size} custom_domain objects in transformed file"

    # 4. Extract org email index from HSET commands
    org_email_to_objid = extract_org_email_index
    puts "Found #{org_email_to_objid.size} entries in organization:contact_email_index"
    puts

    # 5. Cross-reference: index vs objects (bidirectional)
    cross_reference(index_members, domain_objects)

    # 6. Validate count: V2 index vs V1 set
    validate_v1_count(index_members, v1_domain_ids)

    # 7. Check V1 membership
    check_v1_membership(index_members, v1_domain_ids)

    # 8. Validate timestamps
    validate_timestamps(index_members, domain_objects)

    # 9. Validate org ownership
    validate_org_ownership(domain_objects, org_email_to_objid)

    # 10. Spot-check key fields
    spot_check_fields(domain_objects)

    # 11. Report
    print_report

    success?
  ensure
    cleanup_redis
  end

  private

  def validate_input_files
    raise ArgumentError, "Dump file not found: #{@dump_file}" unless File.exist?(@dump_file)
    unless File.exist?(@transformed_file)
      raise ArgumentError, "Transformed file not found: #{@transformed_file}\nRun transform.rb first."
    end
    unless File.exist?(@indexes_file)
      raise ArgumentError, "Indexes file not found: #{@indexes_file}\nRun create_indexes.rb first."
    end
    unless File.exist?(@org_indexes_file)
      raise ArgumentError, "Org indexes file not found: #{@org_indexes_file}\nRun organization create_indexes.rb first."
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

  # Read V1 customdomain:values set from dump file (DUMP blob, needs Redis)
  def extract_v1_domain_set
    v1_record = nil

    File.foreach(@dump_file) do |line|
      record = JSON.parse(line, symbolize_names: true)
      if record[:key] == 'customdomain:values'
        v1_record = record
        break
      end
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'dump', error: "JSON parse error: #{ex.message}" }
    end

    unless v1_record
      puts 'WARNING: customdomain:values (v1 index) not found in dump file'
      return Set.new
    end

    temp_key  = "#{TEMP_KEY_PREFIX}v1_domain_set"
    dump_data = Base64.strict_decode64(v1_record[:dump])
    begin
      @redis.restore(temp_key, 0, dump_data, replace: true)
      members = Set.new(@redis.smembers(temp_key))
      @stats[:v1_members] = members.size
      members
    ensure
      @redis.del(temp_key) if @redis
    end
  end

  # Read V2 ZADD commands from indexes file
  def extract_index_members
    members = {}

    File.foreach(@indexes_file) do |line|
      record = JSON.parse(line)
      next unless record['command'] == 'ZADD' && record['key'] == 'custom_domain:instances'

      # args: [score, objid]
      score = record['args'][0]
      objid = record['args'][1]
      members[objid] = score.to_i if objid
      @stats[:index_members] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'indexes', error: "JSON parse error: #{ex.message}" }
    end

    members
  end

  # Read domain objects from transformed file (has org_id, created at JSONL level)
  def extract_transformed_objects
    objects = {}

    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line, symbolize_names: true)
      next unless record[:key]&.match?(/^custom_domain:[^:]+:object$/)

      objid = record[:objid]
      objects[objid] = record if objid
      @stats[:transformed_objects] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end

    objects
  end

  # Read organization:contact_email_index HSET commands from org indexes file
  def extract_org_email_index
    email_to_objid = {}

    File.foreach(@org_indexes_file) do |line|
      record = JSON.parse(line)
      next unless record['command'] == 'HSET' && record['key'] == 'organization:contact_email_index'

      # args: [email, json_quoted_org_objid]
      email     = record['args'][0]
      org_objid = record['args'][1]

      # Org objid may be JSON-quoted (e.g., "\"abc123\"")
      begin
        org_objid = JSON.parse(org_objid) if org_objid&.start_with?('"')
      rescue JSON::ParserError
        # Use as-is
      end

      email_to_objid[email] = org_objid if email
      @stats[:org_index_entries] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'org_indexes', error: "JSON parse error: #{ex.message}" }
    end

    email_to_objid
  end

  def cross_reference(index_members, domain_objects)
    index_set  = Set.new(index_members.keys)
    object_set = Set.new(domain_objects.keys)

    (index_set - object_set).each do |objid|
      @stats[:in_index_not_in_objects] << { objid: objid, score: index_members[objid] }
    end

    (object_set - index_set).each do |objid|
      @stats[:in_objects_not_in_index] << { objid: objid }
    end

    @stats[:matches] = (index_set & object_set).size
  end

  def validate_v1_count(index_members, v1_domain_ids)
    @stats[:count_mismatch] = v1_domain_ids.size - index_members.size
  end

  def check_v1_membership(index_members, v1_domain_ids)
    return if v1_domain_ids.empty?

    index_members.each_key do |objid|
      @stats[:missing_from_v1] << objid unless v1_domain_ids.include?(objid)
    end
  end

  def validate_timestamps(index_members, domain_objects)
    index_members.each do |objid, score|
      obj = domain_objects[objid]
      next unless obj

      created = obj[:created].to_i
      next if score == created

      @stats[:timestamp_mismatches] << {
        objid: objid,
        index_score: score,
        object_created: created,
      }
    end
  end

  # Verify org_id is present and maps to a known organization
  def validate_org_ownership(domain_objects, org_email_to_objid)
    valid_org_ids = Set.new(org_email_to_objid.values)

    domain_objects.each do |objid, record|
      org_id = record[:org_id]

      if org_id.nil? || org_id.to_s.empty?
        @stats[:org_id_missing] << objid
      elsif !valid_org_ids.include?(org_id)
        @stats[:org_id_invalid] << { objid: objid, org_id: org_id }
      end
    end
  end

  def spot_check_fields(domain_objects)
    domain_objects.each do |objid, record|
      KEY_FIELDS.each do |field|
        value = record[field.to_sym]
        if value && !value.to_s.empty?
          @stats[:field_checks][field][:present] += 1
        else
          @stats[:field_checks][field][:missing] += 1
          @stats[:field_checks][field][:missing_objids] << objid if @stats[:field_checks][field][:missing_objids].size < 5
        end
      end
    end
  end

  def print_report
    puts '=== Validation Results ==='
    puts "V1 set members (customdomain:values): #{@stats[:v1_members]}"
    puts "V2 index members (custom_domain:instances): #{@stats[:index_members]}"
    puts "Transformed objects: #{@stats[:transformed_objects]}"
    puts "Count match (v1 vs v2 index): #{@stats[:count_mismatch].zero? ? 'OK' : "FAIL (difference: #{@stats[:count_mismatch]})"}"
    puts "Bidirectional match: #{@stats[:matches]}"
    puts "In index but missing object: #{@stats[:in_index_not_in_objects].size}"
    puts "Object exists but not indexed: #{@stats[:in_objects_not_in_index].size}"
    puts "Missing from V1 index: #{@stats[:missing_from_v1].size}"
    puts "Timestamp mismatches: #{@stats[:timestamp_mismatches].size}"
    puts "Missing org_id: #{@stats[:org_id_missing].size}"
    puts "Invalid org_id: #{@stats[:org_id_invalid].size}"
    puts

    if @stats[:in_index_not_in_objects].any?
      puts '=== In Index But Missing Object (first 10) ==='
      @stats[:in_index_not_in_objects].first(10).each do |entry|
        puts "  #{entry[:objid]} (score: #{entry[:score]})"
      end
      puts
    end

    if @stats[:in_objects_not_in_index].any?
      puts '=== Object Exists But Not Indexed (first 10) ==='
      @stats[:in_objects_not_in_index].first(10).each do |entry|
        puts "  #{entry[:objid]}"
      end
      puts
    end

    if @stats[:org_id_missing].any?
      puts '=== Missing org_id (first 10) ==='
      @stats[:org_id_missing].first(10).each do |objid|
        puts "  #{objid}"
      end
      puts
    end

    if @stats[:org_id_invalid].any?
      puts '=== Invalid org_id (first 5) ==='
      @stats[:org_id_invalid].first(5).each do |entry|
        puts "  Domain #{entry[:objid]}: org_id=#{entry[:org_id]} (not in org email index)"
      end
      puts
    end

    if @stats[:timestamp_mismatches].any?
      puts '=== Timestamp Mismatches (first 10) ==='
      @stats[:timestamp_mismatches].first(10).each do |m|
        puts "  Domain #{m[:objid]}: index_score=#{m[:index_score]}, object_created=#{m[:object_created]}"
      end
      puts
    end

    puts '=== Key Field Coverage ==='
    KEY_FIELDS.each do |field|
      checks = @stats[:field_checks][field]
      total  = checks[:present] + checks[:missing]
      pct    = total.positive? ? (checks[:present] * 100.0 / total).round(1) : 0
      status = checks[:missing].zero? ? 'OK' : "#{checks[:missing]} missing"
      puts "  #{field}: #{pct}% (#{status})"
    end
    puts

    return unless @stats[:errors].any?

    puts "=== Errors (#{@stats[:errors].size}) ==="
    @stats[:errors].first(10).each do |err|
      puts "  #{err}"
    end
    puts
  end

  def success?
    @stats[:in_index_not_in_objects].empty? &&
      @stats[:in_objects_not_in_index].empty? &&
      @stats[:org_id_missing].empty?
  end
end

def parse_args(args)
  options = {
    dump_file: File.join(DEFAULT_DATA_DIR, 'customdomain/customdomain_dump.jsonl'),
    transformed_file: File.join(DEFAULT_DATA_DIR, 'customdomain/customdomain_transformed.jsonl'),
    indexes_file: File.join(DEFAULT_DATA_DIR, 'customdomain/customdomain_indexes.jsonl'),
    org_indexes_file: File.join(DEFAULT_DATA_DIR, 'organization/organization_indexes.jsonl'),
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    temp_db: 15,
  }

  args.each do |arg|
    case arg
    when /^--dump-file=(.+)$/
      options[:dump_file] = Regexp.last_match(1)
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when /^--indexes-file=(.+)$/
      options[:indexes_file] = Regexp.last_match(1)
    when /^--org-indexes-file=(.+)$/
      options[:org_indexes_file] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--temp-db=(\d+)$/
      options[:temp_db] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/03-customdomain/validate_instance_index.rb [OPTIONS]

        Validates custom_domain:instances index, ownership migration, and V1 consistency.

        Options:
          --dump-file=FILE         V1 dump JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_dump.jsonl)
          --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_transformed.jsonl)
          --indexes-file=FILE      Domain indexes JSONL (default: data/upgrades/v0.24.0/customdomain/customdomain_indexes.jsonl)
          --org-indexes-file=FILE  Org indexes JSONL (default: data/upgrades/v0.24.0/organization/organization_indexes.jsonl)
          --redis-url=URL          Redis URL for temp restore (env: VALKEY_URL or REDIS_URL)
          --temp-db=N              Temp database number (default: 15)
          --help                   Show this help

        Validates:
          - V2 domain count matches V1 count
          - Each domain has a corresponding object (bidirectional)
          - Index scores match object created timestamps
          - org_id is present and valid for each domain
          - Key fields (objid, extid, org_id, created) are present
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
    dump_file: options[:dump_file],
    transformed_file: options[:transformed_file],
    indexes_file: options[:indexes_file],
    org_indexes_file: options[:org_indexes_file],
    redis_url: options[:redis_url],
    temp_db: options[:temp_db],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
