#!/usr/bin/env ruby
# frozen_string_literal: true

# Creates Organization indexes from generated organization records.
# Reads the output of generate.rb and produces index commands.
#
# Run AFTER generate.rb which creates organization_transformed.jsonl
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/02-organization/create_indexes.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: data/upgrades/v0.24.5/organization/organization_transformed.jsonl)
#   --output-dir=DIR    Output directory (default: data/upgrades/v0.24.5/organization)
#   --dry-run           Show what would be created without writing
#
# Input: data/upgrades/v0.24.5/organization/organization_transformed.jsonl (from generate.rb)
# Output: data/upgrades/v0.24.5/organization/organization_indexes.jsonl (Redis commands)

require 'json'
require 'base64'
require 'fileutils'
require 'familia'

require_relative '../lib/progress'

# Calculate project root from script location
# Assumes script is run from project root: ruby scripts/upgrades/v0.24.5/02-organization/create_indexes.rb
DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'

class OrganizationIndexCreator
  def initialize(input_file:, output_dir:, dry_run: false)
    @input_file = input_file
    @output_dir = output_dir
    @dry_run    = dry_run

    @stats = {
      total_records: 0,
      object_records: 0,
      membership_records: 0,
      indexes_written: 0,
      stripe_customer_indexes: 0,
      stripe_subscription_indexes: 0,
      stripe_checkout_email_indexes: 0,
      billing_email_indexes: 0,
      member_entries: 0,
      org_customer_lookups: 0,
      skipped: 0,
      errors: {
        schema_gaps: [],
        orphans: [],
        data_corruption: [],
        processing_failures: [],
      },
    }

    @commands = []
  end

  def run
    validate_input

    puts "Processing: #{@input_file}"
    puts "Output: #{@output_dir}"
    puts 'Mode: DRY RUN' if @dry_run

    process_input_file
    write_outputs unless @dry_run

    print_summary
    @stats
  end

  private

  def validate_input
    unless File.exist?(@input_file)
      abort "Error: Input file not found: #{@input_file}\n" \
            'Run generate.rb first to create organization records.'
    end
  end

  def process_input_file
    progress = Upgrade::ProgressReporter.new('org records')
    File.foreach(@input_file) do |line|
      progress.tick
      @stats[:total_records] += 1
      record                  = JSON.parse(line, symbolize_names: true)

      next unless record[:key]&.end_with?(':object')

      # Skip GLOBAL singleton records (should not be indexed as organizations)
      next if record[:key]&.include?(':GLOBAL:') || record[:key]&.include?(':GLOBAL_STATS:')

      # Owner-membership records (emitted alongside orgs by generate.rb) need
      # only the org_customer_lookup HSET. Routing is by explicit record_kind
      # marker, not key shape, to keep the consumer/producer contract obvious.
      if record[:record_kind] == 'organization_membership'
        @stats[:membership_records] += 1
        process_membership_record(record)
      else
        @stats[:object_records] += 1
        process_organization_record(record)
      end
    rescue JSON::ParserError => ex
      @stats[:errors][:data_corruption] << { line: @stats[:total_records], error: ex.message }
    end
    progress.finish
  end

  def process_membership_record(record)
    membership_objid   = record[:objid]
    organization_objid = record[:organization_objid]
    customer_objid     = record[:customer_objid]

    if [membership_objid, organization_objid, customer_objid].any? { |v| v.nil? || v.to_s.empty? }
      @stats[:skipped] += 1
      @stats[:errors][:data_corruption] << { key: record[:key], error: 'Missing membership identifiers' }
      return
    end

    # Composite key matches OrganizationMembership#org_customer_key:
    #   "#{organization_objid}:#{customer_objid}"
    # Index Redis key matches Familia class_hashkey shape:
    #   "{prefix}:#{index_name}" -> "org_membership:org_customer_lookup"
    # Value is JSON-quoted membership objid (Familia HashKey convention).
    composite_key = "#{organization_objid}:#{customer_objid}"
    add_command(
      'HSET',
      'org_membership:org_customer_lookup',
      [composite_key, membership_objid.to_json],
    )
    @stats[:org_customer_lookups] += 1
  end

  def process_organization_record(record)
    # Extract identifiers from JSONL record metadata
    org_objid    = record[:objid]
    org_extid    = record[:extid]
    owner_id     = record[:owner_id]
    created      = record[:created]

    unless org_objid && !org_objid.empty?
      @stats[:skipped] += 1
      @stats[:errors][:data_corruption] << { key: record[:key], error: 'Missing org objid' }
      return
    end

    # For additional fields, decode the typed payload if not in dry-run mode
    org_fields = if @dry_run
                   # Use metadata from JSONL record for dry-run
                   { 'objid' => org_objid, 'extid' => org_extid, 'owner_id' => owner_id }
                 else
                   decode_fields(record) || {}
                 end

    # Extract fields (prefer JSONL metadata, fall back to decoded fields)
    contact_email          = org_fields['contact_email']
    stripe_customer_id     = org_fields['stripe_customer_id']
    stripe_subscription_id = org_fields['stripe_subscription_id']
    stripe_checkout_email  = org_fields['stripe_checkout_email']
    billing_email          = org_fields['billing_email']

    created = created || org_fields['created']&.to_i || Time.now.to_i

    # Instance index: organization:instances (sorted set, raw identifier for
    # Familia SortedSet compatibility — not JSON-encoded unlike HashKey values)
    add_command('ZADD', 'organization:instances', [created.to_i, org_objid])

    # Lookup indexes (Hash type, JSON-quoted values for Familia compatibility)
    if contact_email && !contact_email.empty?
      add_command('HSET', 'organization:contact_email_index', [contact_email, org_objid.to_json])
    end

    if billing_email && !billing_email.empty?
      add_command('HSET', 'organization:billing_email_index', [billing_email, org_objid.to_json])
      @stats[:billing_email_indexes] += 1
    end

    add_command('HSET', 'organization:extid_lookup', [org_extid, org_objid.to_json])
    add_command('HSET', 'organization:objid_lookup', [org_objid, org_objid.to_json])

    # Stripe indexes (only if valid)
    if stripe_customer_id && stripe_customer_id.start_with?('cus_')
      add_command(
        'HSET',
        'organization:stripe_customer_id_index',
        [stripe_customer_id, org_objid.to_json],
      )
      @stats[:stripe_customer_indexes] += 1
    end

    if stripe_subscription_id && stripe_subscription_id.start_with?('sub_')
      add_command(
        'HSET',
        'organization:stripe_subscription_id_index',
        [stripe_subscription_id, org_objid.to_json],
      )
      @stats[:stripe_subscription_indexes] += 1
    end

    if stripe_checkout_email && !stripe_checkout_email.empty?
      add_command(
        'HSET',
        'organization:stripe_checkout_email_index',
        [stripe_checkout_email, org_objid.to_json],
      )
      @stats[:stripe_checkout_email_indexes] += 1
    end

    # Members relationship: organization:{org_objid}:members
    # Owner is first member, score = created timestamp.
    # Raw identifier for Familia SortedSet compatibility (not JSON-encoded).
    return unless owner_id && !owner_id.empty?

    add_command('ZADD', "organization:#{org_objid}:members", [created.to_i, owner_id])
    @stats[:member_entries] += 1

    # Customer participation: customer:{owner_id}:participations
    # Tracks which org member sets this customer belongs to.
    # Raw key reference for Familia Set compatibility (not JSON-encoded).
    add_command(
      'SADD',
      "customer:#{owner_id}:participations",
      ["organization:#{org_objid}:members"],
    )
  end

  # Decode v2 JSON-encoded hash fields from the typed payload (fields_b64).
  # Each value in fields_b64 is base64-encoded; the underlying string is the
  # JSON-serialized v2 value written by generate.rb.
  def decode_fields(record)
    fields_b64 = record[:fields_b64]
    return nil unless fields_b64

    raw_fields = fields_b64.each_with_object({}) do |(field, b64), acc|
      acc[field.to_s] = Base64.strict_decode64(b64.to_s)
    end
    deserialize_v2_fields(raw_fields)
  rescue ArgumentError => ex
    @stats[:errors][:data_corruption] << { key: record[:key], error: "fields_b64 decode failed: #{ex.message}" }
    nil
  end

  # Deserialize a single v2 JSON-encoded value back to Ruby type
  # Values written by generate.rb are JSON-serialized (e.g., "cus_xxx" -> "\"cus_xxx\"")
  def deserialize_v2_value(raw_value)
    return nil if raw_value.nil? || raw_value == 'null'
    return raw_value if raw_value.empty?

    Familia::JsonSerializer.parse(raw_value)
  rescue Familia::SerializerError
    raw_value # Fallback for non-JSON values
  end

  # Deserialize all fields in a hash from v2 JSON format
  def deserialize_v2_fields(fields)
    return {} if fields.nil?

    fields.transform_values { |v| deserialize_v2_value(v) }
  end

  def add_command(cmd, key, args)
    @commands << {
      command: cmd,
      key: key,
      args: args,
    }
    @stats[:indexes_written] += 1
  end

  def write_outputs
    FileUtils.mkdir_p(@output_dir)

    indexes_file = File.join(@output_dir, 'organization_indexes.jsonl')
    File.open(indexes_file, 'w') do |f|
      @commands.each do |cmd|
        f.puts(JSON.generate(cmd))
      end
    end
    puts "Wrote #{@commands.size} commands to #{indexes_file}"
  end

  def print_summary
    puts "\n=== Organization Index Creation Summary ==="
    puts "Input file: #{@input_file}"
    puts "Total records: #{@stats[:total_records]}"
    puts "Object records: #{@stats[:object_records]}"
    puts "Membership records: #{@stats[:membership_records]}"
    puts "Index commands generated: #{@stats[:indexes_written]}"
    puts
    puts 'Lookup Indexes:'
    puts "  Stripe customer indexes: #{@stats[:stripe_customer_indexes]}"
    puts "  Stripe subscription indexes: #{@stats[:stripe_subscription_indexes]}"
    puts "  Stripe checkout email indexes: #{@stats[:stripe_checkout_email_indexes]}"
    puts "  Billing email indexes: #{@stats[:billing_email_indexes]}"
    puts "  Membership org_customer lookups: #{@stats[:org_customer_lookups]}"
    puts
    puts 'Participation Indexes:'
    puts "  Member entries: #{@stats[:member_entries]}"
    puts
    puts "Skipped: #{@stats[:skipped]}"

    print_error_summary
  end

  def print_error_summary
    buckets = @stats[:errors]
    total   = buckets.values.sum(&:size)
    return if total.zero?

    puts "\nErrors (#{total}):"
    puts "  Schema gaps:     #{buckets[:schema_gaps].size}"
    puts "  Orphans:         #{buckets[:orphans].size}"
    puts "  Data corruption: #{buckets[:data_corruption].size}"
    puts "  Processing:      #{buckets[:processing_failures].size}"

    buckets.each do |name, list|
      next if list.empty?

      puts "  [#{name}] sample:"
      list.first(5).each { |err| puts "    #{err}" }
      puts "    ... and #{list.size - 5} more" if list.size > 5
    end
  end
end

def parse_args(args)
  options = {
    input_file: File.join(DEFAULT_DATA_DIR, 'organization/organization_transformed.jsonl'),
    output_dir: File.join(DEFAULT_DATA_DIR, 'organization'),
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-file=(.+)$/ then options[:input_file] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/ then options[:output_dir] = Regexp.last_match(1)
    when '--dry-run' then options[:dry_run]              = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Creates Organization indexes from generated organization records.
        Run AFTER generate.rb which creates organization_transformed.jsonl.

        Options:
          --input-file=FILE   Input JSONL (default: data/upgrades/v0.24.5/organization/organization_transformed.jsonl)
          --output-dir=DIR    Output directory (default: data/upgrades/v0.24.5/organization)
          --dry-run           Show what would be created without writing
          --help              Show this help

        Output file: organization_indexes.jsonl

        Index types created:
          - organization:instances (sorted set: score=created, member=org_objid)
          - organization:contact_email_index (hash: email -> "org_objid")
          - organization:extid_lookup (hash: extid -> "org_objid")
          - organization:objid_lookup (hash: org_objid -> "org_objid")
          - organization:stripe_customer_id_index (hash: cus_xxx -> "org_objid")
          - organization:stripe_subscription_id_index (hash: sub_xxx -> "org_objid")
          - organization:stripe_checkout_email_index (hash: email -> "org_objid")
          - organization:{org_objid}:members (sorted set: score=created, member=customer_objid)
          - customer:{owner_id}:participations (set: organization:{org_objid}:members)
          - org_membership:org_customer_lookup (hash: "org:cust" -> "membership_objid")
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

  creator = OrganizationIndexCreator.new(
    input_file: options[:input_file],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  creator.run
end
