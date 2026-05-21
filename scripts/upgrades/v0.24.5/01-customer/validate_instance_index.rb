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
#   ruby scripts/upgrades/v0.24.5/validate_instance_index.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump (default: data/upgrades/v0.24.5/customer/customer_dump.jsonl)

require 'json'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.5/01-customer/validate_instance_index.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'

class InstanceIndexValidator
  def initialize(input_file:)
    @input_file = input_file
  end

  def run
    validate_input_file

    # 1. Extract onetime:customer and customer objects from dump
    instance_index_record, customer_objects = parse_dump_file

    unless instance_index_record
      puts 'ERROR: onetime:customer not found in dump'
      return false
    end

    puts "Found #{customer_objects.size} customer objects"

    # 2. Read members directly from the typed payload (no Redis required)
    members_with_scores = decode_instance_index(instance_index_record)
    puts "Found #{members_with_scores.size} members in onetime:customer"
    puts

    # 3. Compare and validate
    results = compare_members(members_with_scores, customer_objects)

    # 4. Report
    print_report(results, members_with_scores, customer_objects)

    # Success if no missing objects (modified_since_creation is expected/normal)
    results[:missing_objects].empty?
  end

  private

  def validate_input_file
    raise ArgumentError, "Input file not found: #{@input_file}" unless File.exist?(@input_file)
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

  # Read zset members directly from the typed payload (zmembers).
  # zmembers is [[member, score], ...] as emitted by dump_keys.rb.
  def decode_instance_index(record)
    (record[:zmembers] || []).map { |member, score| [member, score.to_f] }
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

  def redact_email(email)
    return '***' unless email.is_a?(String) && email.include?('@')

    local, domain = email.split('@', 2)
    "#{local[0..2]}***@#{domain.sub(/\A[^.]+/, '***')}"
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
        puts "  #{redact_email(m[:email])}: last_modified=#{m[:last_modified]}, created=#{m[:created]} (#{days.round(1)} days after)"
      end
      puts
    end

    if results[:missing_objects].any?
      puts "=== Orphaned Index Entries: #{results[:missing_objects].size} (not migrated) ==="
      puts '    (email exists in onetime:customer zset but no customer:*:object key found)'
      results[:missing_objects].first(10).each do |m|
        label = m[:email] == 'GLOBAL' ? ' (stats singleton)' : ' (deleted account)'
        puts "  #{redact_email(m[:email])}#{label} (score: #{m[:score]})"
      end
      puts "  ... and #{results[:missing_objects].size - 10} more" if results[:missing_objects].size > 10
      puts
    end

    # Show sample mapping: email -> objid
    puts '=== Sample Email -> ObjID Mapping (first 5) ==='
    members_with_scores.first(5).each do |email, score|
      customer = customer_objects[email]
      next unless customer

      puts "  #{redact_email(email)}"
      puts "    -> objid: #{customer[:objid]}"
      puts "    -> score: #{score.to_i}, created: #{customer[:created]}"
    end
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'customer/customer_dump.jsonl'),
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/
      options[:input_file] = Regexp.last_match(1)
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.5/validate_instance_index.rb [OPTIONS]

        Validates onetime:customer index against customer objects.

        Options:
          --input-file=FILE   Input JSONL dump (default: data/upgrades/v0.24.5/customer/customer_dump.jsonl)
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
  )

  success = validator.run
  exit(success ? 0 : 1)
end
