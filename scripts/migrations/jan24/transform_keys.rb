#!/usr/bin/env ruby
# frozen_string_literal: true

# Transform v1 Redis keys to v2 Valkey format.
#
# Reads JSONL exports from ./exports/, transforms keys/fields according
# to v1→v2 migration rules, outputs transformed JSONL ready for loading.
#
# Usage:
#   ruby scripts/migrations/jan24/transform_keys.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory (default: exports)
#   --output-dir=DIR   Output directory (default: exports/transformed)
#   --dry-run          Show what would be transformed without writing
#
# Transformations:
# - Customer: key unchanged, custid=objid, store email in email field
# - Organization: NEW records created 1:1 with each Customer
# - OrganizationMembership: NEW records linking Customer to Organization
# - CustomDomain: custid (email) → org_id (Organization objid)
# - Receipt: metadata:{id}: → receipt:{id}:, custid → owner_id
# - Secret: custid → owner_id, remove original_size

require 'json'
require 'base64'
require 'securerandom'
require 'fileutils'
require 'digest'

class KeyTransformer
  # DB mappings from analyze_keyspace.rb
  DB_CONTENT = {
    6 => %w[customer customdomain],
    7 => %w[metadata],
    8 => %w[secret],
    11 => %w[feedback],
  }.freeze

  def initialize(input_dir:, output_dir:, dry_run: false)
    @input_dir  = input_dir
    @output_dir = output_dir
    @dry_run    = dry_run
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    # Mappings built during customer processing
    @email_to_objid       = {} # email → customer objid
    @email_to_org_objid   = {} # email → organization objid
    @email_to_org_data    = {} # email → organization record (for deferred write)
    @email_to_membership  = {} # email → membership record (for deferred write)

    # Stats
    @stats = {
      customers: { scanned: 0, transformed: 0, skipped: 0 },
      organizations: { generated: 0 },
      memberships: { generated: 0 },
      custom_domains: { scanned: 0, transformed: 0, skipped: 0 },
      receipts: { scanned: 0, transformed: 0, skipped: 0 },
      secrets: { scanned: 0, transformed: 0, skipped: 0 },
      indexes: { skipped: 0 },
      other: { skipped: 0 },
    }
  end

  def transform_all
    FileUtils.mkdir_p(@output_dir) unless @dry_run

    # Phase 1: Process customers first (builds email mappings)
    puts '=== Phase 1: Processing Customers ==='
    process_db_file(6, 'customer')

    # Phase 2: Process custom domains (needs email→org mapping)
    puts "\n=== Phase 2: Processing Custom Domains ==="
    process_db_file(6, 'customdomain')

    # Phase 3: Process receipts (metadata → receipt)
    puts "\n=== Phase 3: Processing Receipts (Metadata) ==="
    process_db_file(7, 'metadata')

    # Phase 4: Process secrets
    puts "\n=== Phase 4: Processing Secrets ==="
    process_db_file(8, 'secret')

    # Phase 5: Write generated organizations and memberships
    puts "\n=== Phase 5: Writing Generated Records ==="
    write_generated_records unless @dry_run

    # Write manifest
    write_manifest unless @dry_run

    print_summary
  end

  private

  def process_db_file(db, model_prefix)
    input_files = Dir.glob(File.join(@input_dir, "db#{db}_keys_*.jsonl"))
      .reject { |f| f.end_with?('_manifest.json') }

    if input_files.empty?
      puts "  No input files found for db#{db}"
      return
    end

    input_file  = input_files.max # Latest by timestamp
    output_file = File.join(@output_dir, "#{model_prefix}_transformed_#{@timestamp}.jsonl")

    puts "  Reading: #{File.basename(input_file)}"
    puts "  Writing: #{File.basename(output_file)}" unless @dry_run

    records_written = 0
    output_handle   = @dry_run ? nil : File.open(output_file, 'w')

    File.foreach(input_file) do |line|
      record = JSON.parse(line.strip)
      key    = record['key']

      # Route to appropriate transformer based on key pattern
      transformed = case key
                    when /^customer:([^:]+):object$/
                      transform_customer(record, Regexp.last_match(1))
                    when /^customer:([^:]+):metadata$/
                      # Skip v1 metadata sorted sets (receipts tracked differently in v2)
                      @stats[:indexes][:skipped] += 1
                      nil
                    when /^customdomain:([^:]+):object$/
                      transform_custom_domain(record, Regexp.last_match(1))
                    when /^customdomain:([^:]+):(brand|logo|icon)$/
                      transform_custom_domain_hashkey(record, Regexp.last_match(1), Regexp.last_match(2))
                    when /^metadata:([^:]+):object$/
                      transform_receipt(record, Regexp.last_match(1))
                    when /^secret:([^:]+):object$/
                      transform_secret(record, Regexp.last_match(1))
                    when /^secret:([^:]+):email$/, /^feedback$/
                      # Preserve email notification records and feedback as-is
                      record
                    when /^onetime:/, /^customer:values$/, /^customdomain:(values|owners|display_domains)$/
                      # Skip v1 global indexes (will be rebuilt)
                      skip_index_key
                    else
                      skip_other_key
                    end

      next unless transformed

      unless @dry_run
        output_handle.puts(JSON.generate(transformed))
        records_written += 1
      end
    end

    output_handle&.close
    puts "  Records written: #{records_written}" unless @dry_run
  end

  def transform_customer(record, email)
    @stats[:customers][:scanned] += 1

    # Decode the DUMP data to inspect fields
    # Note: We can't actually decode Redis DUMP format without Redis,
    # so we'll transform the record metadata and pass through the dump
    # The actual field transformation happens at load time via Familia

    # For customers, the key pattern doesn't change in structure,
    # but the semantic meaning of custid changes from email to objid.
    # The dump contains the serialized hash which we'll restore as-is.

    # Parse created timestamp from record (extracted during dump phase)
    created_time = parse_created_time(record['created'])

    # Generate new objid for this customer using historical timestamp
    objid = generate_objid(created_time)
    extid = derive_extid_from_uuid(objid, prefix: 'cus')

    # Store mappings for later phases
    @email_to_objid[email] = objid

    # Generate corresponding Organization using customer's created timestamp
    # so they appear to have been created at the same time
    org_objid                  = generate_objid(created_time)
    org_extid                  = derive_extid_from_uuid(org_objid, prefix: 'org')
    @email_to_org_objid[email] = org_objid

    @email_to_org_data[email] = {
      objid: org_objid,
      extid: org_extid,
      owner_id: objid,
      contact_email: email,
      is_default: 'true',
      display_name: "#{email.split('@').first}'s Workspace",
      created: created_time&.to_f&.to_s || Time.now.to_f.to_s,
      v1_source_custid: email,
      migration_status: 'completed',
      migrated_at: Time.now.to_f.to_s,
    }

    # Generate OrganizationMembership using customer's created timestamp
    membership_objid            = generate_objid(created_time)
    membership_extid            = derive_extid_from_uuid(membership_objid, prefix: 'mem')
    @email_to_membership[email] = {
      objid: membership_objid,
      extid: membership_extid,
      organization_objid: org_objid,
      customer_objid: objid,
      role: 'owner',
      status: 'active',
      created: created_time&.to_f&.to_s || Time.now.to_f.to_s,
      joined_at: created_time&.to_f || Time.now.to_f,
      token: SecureRandom.urlsafe_base64(32),  # 256-bit entropy
      migration_status: 'completed',
      migrated_at: Time.now.to_f.to_s,
    }

    @stats[:customers][:transformed]   += 1
    @stats[:organizations][:generated] += 1
    @stats[:memberships][:generated]   += 1

    # Transform the key to use objid instead of email
    # Note: The actual Redis key stays as customer:{email}:object for now
    # because we're passing through the DUMP data which has the serialized hash.
    # The load script will need to handle the key transformation.

    {
      key: "customer:#{objid}:object",
      original_key: record['key'],
      type: record['type'],
      ttl_ms: record['ttl_ms'],
      dump: record['dump'],
      migration: {
        v1_custid: email,
        v2_objid: objid,
        v2_extid: extid,
        org_objid: org_objid,
        created_time: created_time&.iso8601,
      },
    }
  end

  def transform_custom_domain(record, domain_id)
    @stats[:custom_domains][:scanned] += 1

    # CustomDomain key pattern unchanged, but we need to record
    # the custid→org_id transformation that will happen at load time

    {
      key: record['key'],
      type: record['type'],
      ttl_ms: record['ttl_ms'],
      dump: record['dump'],
      migration: {
        domain_id: domain_id,
        # The actual custid→org_id mapping happens at load time
        # because we need to parse the dump data
        email_to_org_mapping: @email_to_org_objid,
      },
    }.tap { @stats[:custom_domains][:transformed] += 1 }
  end

  def transform_custom_domain_hashkey(record, _domain_id, _hashkey_name)
    # Preserve hashkey data (brand, logo, icon) as-is
    {
      key: record['key'],
      type: record['type'],
      ttl_ms: record['ttl_ms'],
      dump: record['dump'],
    }
  end

  def transform_receipt(record, receipt_id)
    @stats[:receipts][:scanned] += 1

    # Key transformation: metadata:{id}:object → receipt:{id}:object
    new_key = "receipt:#{receipt_id}:object"

    {
      key: new_key,
      original_key: record['key'],
      type: record['type'],
      ttl_ms: record['ttl_ms'],
      dump: record['dump'],
      migration: {
        v1_key: record['key'],
        receipt_id: receipt_id,
        # The actual custid→owner_id mapping happens at load time
        email_to_objid_mapping: @email_to_objid,
        email_to_org_mapping: @email_to_org_objid,
      },
    }.tap { @stats[:receipts][:transformed] += 1 }
  end

  def transform_secret(record, secret_id)
    @stats[:secrets][:scanned] += 1

    # Secret key pattern unchanged
    # Field transformations (custid→owner_id, remove original_size)
    # happen at load time

    {
      key: record['key'],
      type: record['type'],
      ttl_ms: record['ttl_ms'],
      dump: record['dump'],
      migration: {
        secret_id: secret_id,
        # The actual custid→owner_id mapping happens at load time
        email_to_objid_mapping: @email_to_objid,
      },
    }.tap { @stats[:secrets][:transformed] += 1 }
  end

  def skip_index_key
    @stats[:indexes][:skipped] += 1
    nil
  end

  def skip_other_key
    @stats[:other][:skipped] += 1
    nil
  end

  def write_generated_records
    # Write organizations
    org_file = File.join(@output_dir, "organization_generated_#{@timestamp}.jsonl")
    File.open(org_file, 'w') do |f|
      @email_to_org_data.each do |_email, org|
        record = {
          key: "organization:#{org[:objid]}:object",
          type: 'hash',
          ttl_ms: -1,
          generated: true,
          fields: org,
        }
        f.puts(JSON.generate(record))
      end
    end
    puts "  Written: #{File.basename(org_file)} (#{@email_to_org_data.size} records)"

    # Write memberships
    membership_file = File.join(@output_dir, "org_membership_generated_#{@timestamp}.jsonl")
    File.open(membership_file, 'w') do |f|
      @email_to_membership.each do |_email, membership|
        record = {
          key: "org_membership:#{membership[:objid]}:object",
          type: 'hash',
          ttl_ms: -1,
          generated: true,
          fields: membership,
        }
        f.puts(JSON.generate(record))
      end
    end
    puts "  Written: #{File.basename(membership_file)} (#{@email_to_membership.size} records)"
  end

  def write_manifest
    manifest = {
      timestamp: @timestamp,
      input_dir: @input_dir,
      output_dir: @output_dir,
      stats: @stats,
      mappings: {
        email_to_objid_count: @email_to_objid.size,
        email_to_org_count: @email_to_org_objid.size,
      },
    }

    manifest_file = File.join(@output_dir, "transform_manifest_#{@timestamp}.json")
    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "\n  Manifest: #{File.basename(manifest_file)}"
  end

  def print_summary
    puts "\n=== Transformation Summary ==="
    puts "Customers:      #{@stats[:customers][:transformed]} transformed, #{@stats[:customers][:skipped]} skipped"
    puts "Organizations:  #{@stats[:organizations][:generated]} generated"
    puts "Memberships:    #{@stats[:memberships][:generated]} generated"
    puts "Custom Domains: #{@stats[:custom_domains][:transformed]} transformed"
    puts "Receipts:       #{@stats[:receipts][:transformed]} transformed"
    puts "Secrets:        #{@stats[:secrets][:transformed]} transformed"
    puts "Indexes:        #{@stats[:indexes][:skipped]} skipped (will rebuild)"
    puts "Other:          #{@stats[:other][:skipped]} skipped"
  end

  # Parse created timestamp from record (float seconds since epoch)
  def parse_created_time(created_value)
    return nil if created_value.nil? || created_value.to_s.empty?

    Time.at(created_value.to_f)
  rescue ArgumentError
    nil
  end

  # Generate UUIDv7 from a specific time (preserves historical ordering)
  # Standalone implementation copied from lib/onetime/refinements/uuidv7_refinements.rb
  # to avoid requiring OT boot.
  def uuid_v7_from(time)
    timestamp_ms   = (time.to_f * 1000).to_i
    hex            = timestamp_ms.to_s(16).rjust(12, '0')
    timestamp_part = "#{hex[0, 8]}-#{hex[8, 4]}-7"
    base_uuid      = generate_base_uuid_v7
    base_parts     = base_uuid.split('-')
    "#{timestamp_part}#{base_parts[2][1..]}-#{base_parts[3]}-#{base_parts[4]}"
  end

  # Generate a base UUIDv7 with current time (used for random portion extraction)
  def generate_base_uuid_v7
    timestamp_ms = (Time.now.to_f * 1000).to_i
    random_bytes = SecureRandom.random_bytes(10).bytes

    uuid_bytes = [
      (timestamp_ms >> 40) & 0xFF,
      (timestamp_ms >> 32) & 0xFF,
      (timestamp_ms >> 24) & 0xFF,
      (timestamp_ms >> 16) & 0xFF,
      (timestamp_ms >> 8) & 0xFF,
      timestamp_ms & 0xFF,
      (0x70 | (random_bytes[0] & 0x0F)),  # version 7
      random_bytes[1],
      (0x80 | (random_bytes[2] & 0x3F)),  # variant 10xx
      random_bytes[3],
      random_bytes[4],
      random_bytes[5],
      random_bytes[6],
      random_bytes[7],
      random_bytes[8],
      random_bytes[9],
    ].pack('C*')

    hex = uuid_bytes.unpack1('H*')
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end

  # Derive deterministic external ID from UUID
  # Standalone implementation copied from migrations/20250728-1512_00_customer_objid.rb
  def derive_extid_from_uuid(uuid_string, prefix: 'ext')
    normalized_hex = uuid_string.delete('-')
    seed           = Digest::SHA256.digest(normalized_hex)
    prng           = Random.new(seed.unpack1('Q>'))
    random_bytes   = prng.bytes(16)
    external_part  = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')
    "#{prefix}_#{external_part}"
  end

  # Generate objid from optional created timestamp (falls back to Time.now)
  def generate_objid(created_time = nil)
    time = created_time || Time.now
    uuid_v7_from(time)
  end
end

def parse_args(args)
  options = {
    input_dir: 'exports',
    output_dir: 'exports/transformed',
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--output-dir=(.+)$/
      options[:output_dir] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/transform_keys.rb [OPTIONS]

        Options:
          --input-dir=DIR    Input directory (default: exports)
          --output-dir=DIR   Output directory (default: exports/transformed)
          --dry-run          Show what would be transformed
          --help             Show this help
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  transformer = KeyTransformer.new(
    input_dir: options[:input_dir],
    output_dir: options[:output_dir],
    dry_run: options[:dry_run],
  )

  transformer.transform_all
end
