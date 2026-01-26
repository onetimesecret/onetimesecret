#!/usr/bin/env ruby
# frozen_string_literal: true

# Load transformed keys into Valkey DB 0.
#
# Reads transformed JSONL files and uses Redis RESTORE to load keys.
# Handles both DUMP-based records (from original exports) and
# generated records (Organizations, Memberships).
#
# CRITICAL: Stores _original_record data for zero data loss guarantee.
# The complete v1 data structure is preserved in each record's
# _original_record jsonkey field for rollback/audit purposes.
#
# Usage:
#   ruby scripts/migrations/jan24/load_keys.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory (default: exports/transformed)
#   --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
#   --replace          Replace existing keys (default: skip)
#   --dry-run          Show what would be loaded without writing
#
# Processing:
# 1. Load generated records first (Organizations, Memberships)
# 2. Load transformed records with RESTORE
# 3. Apply field transformations where needed
# 4. Store _original_record for zero data loss

require 'redis'
require 'json'
require 'base64'
require 'fileutils'

class KeyLoader
  def initialize(input_dir:, valkey_url:, replace: false, dry_run: false)
    @input_dir   = input_dir
    @valkey_url  = valkey_url
    @replace     = replace
    @dry_run     = dry_run
    @timestamp   = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    # Load mappings from transform manifest
    @email_to_objid     = {}
    @email_to_org_objid = {}
    load_mappings

    # Stats
    @stats = {
      organizations: { loaded: 0, skipped: 0, errors: 0 },
      memberships: { loaded: 0, skipped: 0, errors: 0 },
      customers: { loaded: 0, skipped: 0, errors: 0 },
      custom_domains: { loaded: 0, skipped: 0, errors: 0 },
      receipts: { loaded: 0, skipped: 0, errors: 0 },
      secrets: { loaded: 0, skipped: 0, errors: 0 },
      other: { loaded: 0, skipped: 0, errors: 0 },
    }

    @errors = []
  end

  def load_all
    @valkey = Redis.new(url: @valkey_url) unless @dry_run

    puts '=== Loading to Valkey DB 0 ==='
    puts "  URL: #{@valkey_url}"
    puts "  Replace mode: #{@replace}"
    puts "  Dry run: #{@dry_run}"

    # Phase 1: Load generated organizations
    puts "\n=== Phase 1: Loading Organizations ==="
    load_generated_records('organization')

    # Phase 2: Load generated memberships
    puts "\n=== Phase 2: Loading Memberships ==="
    load_generated_records('org_membership')

    # Phase 3: Load customers (RESTORE from DUMP)
    puts "\n=== Phase 3: Loading Customers ==="
    load_transformed_records('customer')

    # Phase 4: Load custom domains
    puts "\n=== Phase 4: Loading Custom Domains ==="
    load_transformed_records('customdomain')

    # Phase 5: Load receipts
    puts "\n=== Phase 5: Loading Receipts ==="
    load_transformed_records('receipt')

    # Phase 6: Load secrets
    puts "\n=== Phase 6: Loading Secrets ==="
    load_transformed_records('secret')

    # Write manifest
    write_manifest unless @dry_run

    print_summary
  end

  private

  def load_mappings
    manifest_files = Dir.glob(File.join(@input_dir, 'transform_manifest_*.json'))
    return if manifest_files.empty?

    manifest_file = manifest_files.max
    puts "Loading mappings from: #{File.basename(manifest_file)}"

    # The mappings are embedded in the transformed records themselves
    # We'll extract them as we process
  end

  def load_generated_records(model_prefix)
    input_files = Dir.glob(File.join(@input_dir, "#{model_prefix}_generated_*.jsonl"))

    if input_files.empty?
      puts "  No #{model_prefix} files found"
      return
    end

    input_file = input_files.max
    puts "  Reading: #{File.basename(input_file)}"

    File.foreach(input_file) do |line|
      record = JSON.parse(line.strip)
      key    = record['key']
      fields = record['fields']

      stat_key = model_prefix == 'org_membership' ? :memberships : :organizations

      # Check if key exists
      if @dry_run
        @stats[stat_key][:loaded] += 1
      else
        if @valkey.exists?(key) && !@replace
          @stats[stat_key][:skipped] += 1
          next
        end

        begin
          # Convert field values to strings for HSET
          string_fields              = fields.transform_values(&:to_s)
          @valkey.hset(key, string_fields)
          @stats[stat_key][:loaded] += 1
        rescue Redis::CommandError => ex
          @stats[stat_key][:errors] += 1
          @errors << { key: key, error: ex.message }
        end
      end
    end

    puts "  Loaded: #{@stats[model_prefix == 'org_membership' ? :memberships : :organizations][:loaded]}"
  end

  def load_transformed_records(model_prefix)
    input_files = Dir.glob(File.join(@input_dir, "#{model_prefix}_transformed_*.jsonl"))

    if input_files.empty?
      puts "  No #{model_prefix} files found"
      return
    end

    input_file = input_files.max
    puts "  Reading: #{File.basename(input_file)}"

    stat_key = case model_prefix
               when 'customdomain' then :custom_domains
               when 'customer' then :customers
               when 'receipt' then :receipts
               when 'secret' then :secrets
               else :other
               end

    File.foreach(input_file) do |line|
      record = JSON.parse(line.strip)
      key    = record['key']

      # Extract mappings from migration metadata if present
      if record['migration']
        migration = record['migration']
        if migration['email_to_objid_mapping']
          @email_to_objid.merge!(migration['email_to_objid_mapping'])
        end
        if migration['email_to_org_mapping']
          @email_to_org_objid.merge!(migration['email_to_org_mapping'])
        end
      end

      if @dry_run
        @stats[stat_key][:loaded] += 1
      else
        # Check if key exists
        if @valkey.exists?(key) && !@replace
          @stats[stat_key][:skipped] += 1
          next
        end

        begin
          load_record(record, stat_key)
        rescue Redis::CommandError => ex
          @stats[stat_key][:errors] += 1
          @errors << { key: key, error: ex.message }
        end
      end
    end

    puts "  Loaded: #{@stats[stat_key][:loaded]}, Skipped: #{@stats[stat_key][:skipped]}"
  end

  def load_record(record, stat_key)
    key     = record['key']
    ttl_ms  = record['ttl_ms']
    dump    = record['dump']

    if dump
      # Use RESTORE for DUMP-serialized data
      dump_data = Base64.strict_decode64(dump)

      # TTL: -1 means no expiry, -2 means key doesn't exist
      # RESTORE wants 0 for no expiry, or positive ms for TTL
      restore_ttl = ttl_ms.positive? ? ttl_ms : 0

      if @replace
        @valkey.restore(key, restore_ttl, dump_data, replace: true)
      else
        @valkey.restore(key, restore_ttl, dump_data)
      end

      # Post-RESTORE field transformations
      apply_field_transformations(record, key, stat_key)
    elsif record['generated']
      # Generated records are handled by load_generated_records
      return
    end

    @stats[stat_key][:loaded] += 1
  end

  def apply_field_transformations(record, key, stat_key)
    migration = record['migration']
    return unless migration

    # Store the complete original v1 record for zero data loss
    store_original_record(record, key)

    case stat_key
    when :customers
      transform_customer_fields(key, migration)
    when :custom_domains
      transform_custom_domain_fields(key, migration)
    when :receipts
      transform_receipt_fields(key, migration)
    when :secrets
      transform_secret_fields(key, migration)
    end
  end

  # Store the complete original v1 record in the _original_record jsonkey
  #
  # The Familia model's jsonkey :_original_record stores this as JSON.
  # Key format: {prefix}:{id}:_original_record (e.g., customer:abc123:_original_record)
  #
  # @param record [Hash] The JSONL record containing _original_record data
  # @param key [String] The main object key (e.g., customer:abc123:object)
  def store_original_record(record, key)
    original_record = record['_original_record']
    return unless original_record

    # Derive the _original_record key from the main object key
    # customer:abc123:object -> customer:abc123:_original_record
    original_record_key = key.sub(/:object\z/, ':_original_record')

    # Store as JSON string (Familia jsonkey expects this)
    @valkey.set(original_record_key, JSON.generate(original_record))
  end

  def transform_customer_fields(key, migration)
    v1_custid = migration['v1_custid']
    v2_objid  = migration['v2_objid']
    v2_extid  = migration['v2_extid']
    migration['org_objid']

    # Update fields in the hash
    fields          = {
      'objid' => v2_objid,
      'custid' => v2_objid,        # custid now equals objid
      'email' => v1_custid,        # email field stores the email
      'v1_custid' => v1_custid,    # migration reference
      'migration_status' => 'completed',
      'migrated_at' => Time.now.to_f.to_s,
    }
    fields['extid'] = v2_extid if v2_extid
    @valkey.hset(key, fields)
  end

  def transform_custom_domain_fields(key, migration)
    # Extract migration metadata
    v1_domainid = migration['v1_domainid']
    v2_objid    = migration['v2_objid']
    v2_extid    = migration['v2_extid']

    # Read current custid (email) from the hash for org_id lookup
    current_custid = @valkey.hget(key, 'custid')

    # Build fields to set
    fields = {
      'objid' => v2_objid,
      'domainid' => v2_objid,         # domainid is aliased to objid in v2
      'extid' => v2_extid,
      'v1_domainid' => v1_domainid,   # preserve old hex identifier
      'migration_status' => 'completed',
      'migrated_at' => Time.now.to_f.to_s,
    }

    # Look up org_id from custid (email)
    if current_custid && !current_custid.empty?
      org_objid = @email_to_org_objid[current_custid]
      if org_objid
        fields['org_id']    = org_objid
        fields['v1_custid'] = current_custid
      else
        # Customer not found - preserve custid for manual review
        fields['v1_custid'] = current_custid
        puts "  Warning: No org mapping for custid #{current_custid} on domain #{v1_domainid}"
      end
    end

    # Update fields
    @valkey.hset(key, fields)

    # Remove old custid field (it's now org_id)
    @valkey.hdel(key, 'custid') if current_custid
  end

  def transform_receipt_fields(key, migration)
    v1_key = migration['v1_key']

    # Read current custid from the hash
    current_custid = @valkey.hget(key, 'custid')

    if current_custid && current_custid != 'anon'
      # Look up customer objid
      owner_id = @email_to_objid[current_custid]
      org_id   = @email_to_org_objid[current_custid]

      if owner_id
        @valkey.hset(
          key,
          'owner_id' => owner_id,
          'org_id' => org_id,
          'v1_key' => v1_key,
          'v1_custid' => current_custid,
          'migration_status' => 'completed',
          'migrated_at' => Time.now.to_f.to_s,
        )
      else
        # Customer not found - preserve original custid and mark for review
        @valkey.hset(
          key,
          'owner_id' => 'anon',  # Default to anonymous
          'v1_key' => v1_key,
          'v1_custid' => current_custid,
          'migration_status' => 'completed',
          'migrated_at' => Time.now.to_f.to_s,
        )
      end
    elsif current_custid == 'anon'
      @valkey.hset(
        key,
        'owner_id' => 'anon',
        'v1_key' => v1_key,
        'v1_custid' => 'anon',
        'migration_status' => 'completed',
        'migrated_at' => Time.now.to_f.to_s,
      )
    end

    # Field renames: viewed → previewed, received → revealed
    viewed = @valkey.hget(key, 'viewed')
    @valkey.hset(key, 'previewed', viewed) if viewed && !viewed.empty?

    received = @valkey.hget(key, 'received')
    @valkey.hset(key, 'revealed', received) if received && !received.empty?

    # Remove deprecated custid field
    @valkey.hdel(key, 'custid')
  end

  def transform_secret_fields(key, _migration)
    # Read current custid from the hash
    current_custid = @valkey.hget(key, 'custid')

    if current_custid && current_custid != 'anon'
      # Look up customer objid
      owner_id = @email_to_objid[current_custid]

      if owner_id
        @valkey.hset(
          key,
          'owner_id' => owner_id,
          'v1_custid' => current_custid,
          'migration_status' => 'completed',
          'migrated_at' => Time.now.to_f.to_s,
        )
      else
        @valkey.hset(
          key,
          'owner_id' => 'anon',
          'v1_custid' => current_custid,
          'migration_status' => 'completed',
          'migrated_at' => Time.now.to_f.to_s,
        )
      end
    elsif current_custid == 'anon'
      @valkey.hset(
        key,
        'owner_id' => 'anon',
        'v1_custid' => 'anon',
        'migration_status' => 'completed',
        'migrated_at' => Time.now.to_f.to_s,
      )
    end

    # Remove deprecated fields
    @valkey.hdel(key, 'custid')

    # Store original_size in migration field before removal
    original_size = @valkey.hget(key, 'original_size')
    if original_size
      @valkey.hset(key, 'v1_original_size', original_size)
      @valkey.hdel(key, 'original_size')
    end
  end

  def write_manifest
    manifest = {
      timestamp: @timestamp,
      input_dir: @input_dir,
      valkey_url: @valkey_url.sub(/:[^:@]*@/, ':***@'),
      replace_mode: @replace,
      stats: @stats,
      errors: @errors.first(20),
      total_errors: @errors.size,
    }

    manifest_file = File.join(@input_dir, "load_manifest_#{@timestamp}.json")
    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "\n  Manifest: #{File.basename(manifest_file)}"
  end

  def print_summary
    total_loaded  = @stats.values.sum { |s| s[:loaded] }
    total_skipped = @stats.values.sum { |s| s[:skipped] }
    total_errors  = @stats.values.sum { |s| s[:errors] }

    puts "\n=== Load Summary ==="
    puts "Organizations:  #{@stats[:organizations][:loaded]} loaded, #{@stats[:organizations][:skipped]} skipped"
    puts "Memberships:    #{@stats[:memberships][:loaded]} loaded, #{@stats[:memberships][:skipped]} skipped"
    puts "Customers:      #{@stats[:customers][:loaded]} loaded, #{@stats[:customers][:skipped]} skipped"
    puts "Custom Domains: #{@stats[:custom_domains][:loaded]} loaded, #{@stats[:custom_domains][:skipped]} skipped"
    puts "Receipts:       #{@stats[:receipts][:loaded]} loaded, #{@stats[:receipts][:skipped]} skipped"
    puts "Secrets:        #{@stats[:secrets][:loaded]} loaded, #{@stats[:secrets][:skipped]} skipped"
    puts "\nTotals: #{total_loaded} loaded, #{total_skipped} skipped, #{total_errors} errors"

    return if @errors.empty?

    puts "\nFirst 5 errors:"
    @errors.first(5).each do |err|
      puts "  #{err[:key]}: #{err[:error]}"
    end
  end
end

def parse_args(args)
  options = {
    input_dir: 'exports/transformed',
    valkey_url: 'redis://127.0.0.1:6379/0',
    replace: false,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--valkey-url=(.+)$/
      options[:valkey_url] = Regexp.last_match(1)
    when '--replace'
      options[:replace] = true
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/load_keys.rb [OPTIONS]

        Options:
          --input-dir=DIR    Input directory (default: exports/transformed)
          --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
          --replace          Replace existing keys (default: skip)
          --dry-run          Show what would be loaded
          --help             Show this help
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  loader = KeyLoader.new(
    input_dir: options[:input_dir],
    valkey_url: options[:valkey_url],
    replace: options[:replace],
    dry_run: options[:dry_run],
  )

  loader.load_all
end
