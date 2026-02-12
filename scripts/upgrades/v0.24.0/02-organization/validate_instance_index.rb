#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that organization:instances index members match organization objects
# and verifies 1-to-1 correspondence with v1 customer records.
#
# This script cross-references:
# 1. organization_indexes.jsonl - ZADD commands for organization:instances (objid members)
# 2. organization_transformed.jsonl - generated organization objects with V2 keys
# 3. customer_transformed.jsonl - V2 customer objects (for count cross-reference)
#
# Validations:
# 1. Each objid in organization:instances has a matching organization:{objid}:object record
# 2. Each organization:{objid}:object record has an entry in organization:instances
# 3. Index scores match object created timestamps
# 4. Organization count matches customer count (1-to-1 invariant)
# 5. Key fields (objid, extid, owner_id, contact_email, created) are present
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/02-organization/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/organization/organization_transformed.jsonl)
#   --indexes-file=FILE      Indexes JSONL (default: data/upgrades/v0.24.0/organization/organization_indexes.jsonl)
#   --customer-file=FILE     Customer transformed JSONL (default: data/upgrades/v0.24.0/customer/customer_transformed.jsonl)
#   --help                   Show this help

require 'json'
require 'set'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class OrganizationInstanceIndexValidator
  KEY_FIELDS = %w[objid extid owner_id contact_email created].freeze

  def initialize(transformed_file:, indexes_file:, customer_file:)
    @transformed_file = transformed_file
    @indexes_file     = indexes_file
    @customer_file    = customer_file

    @stats = {
      index_members: 0,
      transformed_objects: 0,
      customer_objects: 0,
      matches: 0,
      in_index_not_in_objects: [],
      in_objects_not_in_index: [],
      timestamp_mismatches: [],
      count_mismatch: 0,
      field_checks: Hash.new { |h, k| h[k] = { present: 0, missing: 0, missing_objids: [] } },
      errors: [],
    }
  end

  def run
    validate_input_files

    # 1. Extract index members from ZADD commands
    index_members = extract_index_members
    puts "Found #{index_members.size} members in organization:instances index"

    # 2. Extract organization objects from transformed file
    org_objects = extract_transformed_objects
    puts "Found #{org_objects.size} organization objects in transformed file"

    # 3. Count customer objects for cross-reference
    customer_count = count_customer_objects
    puts "Found #{customer_count} customer objects in customer file"
    puts

    # 4. Cross-reference: index vs objects (bidirectional)
    cross_reference(index_members, org_objects)

    # 5. Validate timestamps: index score == object created
    validate_timestamps(index_members, org_objects)

    # 6. Validate 1-to-1 count: orgs == customers
    validate_customer_count(index_members, customer_count)

    # 7. Spot-check key fields
    spot_check_fields(org_objects)

    # 8. Report
    print_report

    success?
  end

  private

  def validate_input_files
    unless File.exist?(@transformed_file)
      raise ArgumentError, "Transformed file not found: #{@transformed_file}\nRun generate.rb first."
    end
    unless File.exist?(@indexes_file)
      raise ArgumentError, "Indexes file not found: #{@indexes_file}\nRun create_indexes.rb first."
    end
    unless File.exist?(@customer_file)
      raise ArgumentError, "Customer file not found: #{@customer_file}\nRun customer transform first."
    end
  end

  def extract_index_members
    members = {}

    File.foreach(@indexes_file) do |line|
      record = JSON.parse(line)

      # Only look at ZADD commands for organization:instances
      next unless record['command'] == 'ZADD' && record['key'] == 'organization:instances'

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

  def extract_transformed_objects
    objects = {}

    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line)

      # Only process object records
      next unless record['key']&.match?(/^organization:[^:]+:object$/)

      objid = record['objid']
      objects[objid] = record if objid
      @stats[:transformed_objects] += 1
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse error: #{ex.message}" }
    end

    objects
  end

  def count_customer_objects
    count = 0

    File.foreach(@customer_file) do |line|
      record = JSON.parse(line)
      next unless record['key']&.match?(/^customer:[^:]+:object$/)

      count += 1
    rescue JSON::ParserError
      # Skip unparseable lines
    end

    @stats[:customer_objects] = count
    count
  end

  def cross_reference(index_members, org_objects)
    index_set  = Set.new(index_members.keys)
    object_set = Set.new(org_objects.keys)

    (index_set - object_set).each do |objid|
      @stats[:in_index_not_in_objects] << { objid: objid, score: index_members[objid] }
    end

    (object_set - index_set).each do |objid|
      @stats[:in_objects_not_in_index] << { objid: objid }
    end

    @stats[:matches] = (index_set & object_set).size
  end

  def validate_timestamps(index_members, org_objects)
    index_members.each do |objid, score|
      obj = org_objects[objid]
      next unless obj # Skip if missing (already caught by cross_reference)

      created = obj['created'].to_i
      next if score == created

      @stats[:timestamp_mismatches] << {
        objid: objid,
        index_score: score,
        object_created: created,
      }
    end
  end

  def validate_customer_count(index_members, customer_count)
    @stats[:count_mismatch] = index_members.size - customer_count
  end

  def spot_check_fields(org_objects)
    org_objects.each do |objid, record|
      KEY_FIELDS.each do |field|
        value = record[field]
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
    puts "Index members (organization:instances): #{@stats[:index_members]}"
    puts "Transformed objects: #{@stats[:transformed_objects]}"
    puts "Bidirectional match: #{@stats[:matches]}"
    puts "In index but missing object: #{@stats[:in_index_not_in_objects].size}"
    puts "Object exists but not indexed: #{@stats[:in_objects_not_in_index].size}"
    puts "Timestamp mismatches: #{@stats[:timestamp_mismatches].size}"
    puts "Count match (orgs vs customers): #{@stats[:count_mismatch].zero? ? 'OK' : "FAIL (difference: #{@stats[:count_mismatch]})"}"
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

    if @stats[:timestamp_mismatches].any?
      puts '=== Timestamp Mismatches (first 10) ==='
      @stats[:timestamp_mismatches].first(10).each do |m|
        puts "  Org #{m[:objid]}: index_score=#{m[:index_score]}, object_created=#{m[:object_created]}"
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
      @stats[:in_objects_not_in_index].empty?
  end
end

def parse_args(args)
  options = {
    transformed_file: File.join(DEFAULT_DATA_DIR, 'organization/organization_transformed.jsonl'),
    indexes_file: File.join(DEFAULT_DATA_DIR, 'organization/organization_indexes.jsonl'),
    customer_file: File.join(DEFAULT_DATA_DIR, 'customer/customer_transformed.jsonl'),
  }

  args.each do |arg|
    case arg
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when /^--indexes-file=(.+)$/
      options[:indexes_file] = Regexp.last_match(1)
    when /^--customer-file=(.+)$/
      options[:customer_file] = Regexp.last_match(1)
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/02-organization/validate_instance_index.rb [OPTIONS]

        Validates organization:instances index against transformed organization objects
        and verifies 1-to-1 correspondence with customer records.

        Options:
          --transformed-file=FILE  Transformed JSONL (default: data/upgrades/v0.24.0/organization/organization_transformed.jsonl)
          --indexes-file=FILE      Indexes JSONL (default: data/upgrades/v0.24.0/organization/organization_indexes.jsonl)
          --customer-file=FILE     Customer transformed JSONL (default: data/upgrades/v0.24.0/customer/customer_transformed.jsonl)
          --help                   Show this help

        Validates:
          - Each objid in organization:instances has a matching organization:{objid}:object
          - Each transformed organization object has an entry in organization:instances
          - Index scores match object created timestamps
          - Organization count matches customer count (1-to-1 invariant)
          - Key fields (objid, extid, owner_id, contact_email, created) are present
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
    transformed_file: options[:transformed_file],
    indexes_file: options[:indexes_file],
    customer_file: options[:customer_file],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
