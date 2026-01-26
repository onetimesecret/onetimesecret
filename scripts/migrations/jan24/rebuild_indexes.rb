#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild v2 indexes after migration.
#
# Creates the Familia v2 index structures:
# - {model}:instances sorted sets (objid with created timestamp as score)
# - {model}:{field}:index unique lookup hashes
# - Organization participation sets (members, domains, receipts)
#
# Usage:
#   ruby scripts/migrations/jan24/rebuild_indexes.rb [OPTIONS]
#
# Options:
#   --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
#   --dry-run          Show what would be created without writing
#
# Index structures:
# - customer:instances (zset: objid → created)
# - customer:email_index (hash: email → objid)
# - customer:extid_lookup (hash: extid → objid)
# - organization:instances (zset: objid → created)
# - organization:contact_email_index (hash: contact_email → objid)
# - organization:{objid}:members (zset: auto-populated by Familia participates_in)
# - organization:{objid}:domains (zset: auto-populated by Familia participates_in)
# - customdomain:instances (zset: domainid → created)
# - customdomain:display_domain_index (hash: display_domain → domainid)
# - receipt:instances (zset: objid → created)
# - secret:instances (zset: objid → created)

require 'redis'
require 'json'
require 'securerandom'

class IndexRebuilder
  # External ID prefixes (from Familia v2 models)
  # Format: prefix + first 16 chars of objid (no dashes)
  EXTID_PREFIXES = {
    customer: 'ur',
    organization: 'on',
    customdomain: 'cd',
    receipt: 'rc',
  }.freeze

  # Generate external ID in the correct format
  # @param prefix [String] Model prefix (ur, on, cd, rc)
  # @param objid [String] Object identifier (UUID format)
  # @return [String] External ID (prefix + 16 hex chars)
  def generate_extid(prefix, objid)
    # Remove dashes from UUID and take first 16 chars
    clean_id = objid.to_s.delete('-')[0, 16]
    "#{prefix}#{clean_id}"
  end

  def initialize(valkey_url:, dry_run: false)
    @valkey_url = valkey_url
    @dry_run    = dry_run
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    @stats = {
      instances: { created: 0 },
      unique_indexes: { created: 0 },
      extid_lookups: { created: 0 },
      participation_sets: { created: 0 },
      errors: 0,
    }

    @errors = []
  end

  def rebuild_all
    @valkey = Redis.new(url: @valkey_url) unless @dry_run

    puts '=== Rebuilding V2 Indexes ==='
    puts "  URL: #{@valkey_url}"
    puts "  Dry run: #{@dry_run}"

    # Phase 1: Build instances sorted sets
    puts "\n=== Phase 1: Building instances sorted sets ==="
    build_customer_instances
    build_organization_instances
    build_membership_instances
    build_customdomain_instances
    build_receipt_instances
    build_secret_instances

    # Phase 2: Build unique indexes
    puts "\n=== Phase 2: Building unique indexes ==="
    build_customer_email_index
    build_customer_extid_lookup
    build_organization_contact_email_index
    build_organization_extid_lookup
    build_customdomain_display_domain_index
    build_membership_indexes

    # Phase 3: Build participation sets
    puts "\n=== Phase 3: Building participation sets ==="
    build_organization_members_sets
    build_organization_domains_sets
    build_organization_receipts_sets
    build_customdomain_receipts_sets

    # Write manifest
    write_manifest unless @dry_run

    print_summary
  end

  private

  # ============================================
  # Phase 1: Instances Sorted Sets
  # ============================================

  def build_customer_instances
    build_instances_set('customer', 'customer')
  end

  def build_organization_instances
    build_instances_set('organization', 'organization')
  end

  def build_membership_instances
    build_instances_set('org_membership', 'org_membership')
  end

  def build_customdomain_instances
    build_instances_set('customdomain', 'customdomain')
  end

  def build_receipt_instances
    build_instances_set('receipt', 'receipt')
  end

  def build_secret_instances
    build_instances_set('secret', 'secret')
  end

  def build_instances_set(model_prefix, index_name)
    puts "  Building #{index_name}:instances..."

    instances_key = "#{index_name}:instances"
    count         = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: "#{model_prefix}:*:object", count: 1000)

      keys.each do |key|
        # Extract objid from key
        objid = key.split(':')[1]

        # Get created timestamp for score (fall back to current time)
        created = @valkey.hget(key, 'created') || @valkey.hget(key, 'joined_at') || Time.now.to_f

        unless @dry_run
          @valkey.zadd(instances_key, created.to_f, objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{instances_key}"
    @stats[:instances][:created] += count
  end

  # ============================================
  # Phase 2: Unique Indexes
  # ============================================

  def build_customer_email_index
    puts '  Building customer:email_index...'

    index_key = 'customer:email_index'
    count     = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customer:*:object', count: 1000)

      keys.each do |key|
        email = @valkey.hget(key, 'email')
        objid = @valkey.hget(key, 'objid')

        next if email.to_s.empty? || objid.to_s.empty?

        unless @dry_run
          @valkey.hset(index_key, email, objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{index_key}"
    @stats[:unique_indexes][:created] += count
  end

  def build_customer_extid_lookup
    puts '  Building customer:extid_lookup...'

    lookup_key = 'customer:extid_lookup'
    count      = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customer:*:object', count: 1000)

      keys.each do |key|
        objid = @valkey.hget(key, 'objid')
        next if objid.to_s.empty?

        # Generate extid if not present
        extid = @valkey.hget(key, 'extid')
        if extid.to_s.empty?
          extid = generate_extid(EXTID_PREFIXES[:customer], objid)
          @valkey.hset(key, 'extid', extid) unless @dry_run
        end

        unless @dry_run
          @valkey.hset(lookup_key, extid, objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{lookup_key}"
    @stats[:extid_lookups][:created] += count
  end

  def build_organization_contact_email_index
    puts '  Building organization:contact_email_index...'

    index_key = 'organization:contact_email_index'
    count     = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'organization:*:object', count: 1000)

      keys.each do |key|
        contact_email = @valkey.hget(key, 'contact_email')
        objid         = @valkey.hget(key, 'objid')

        next if contact_email.to_s.empty? || objid.to_s.empty?

        unless @dry_run
          @valkey.hset(index_key, contact_email, objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{index_key}"
    @stats[:unique_indexes][:created] += count
  end

  def build_organization_extid_lookup
    puts '  Building organization:extid_lookup...'

    lookup_key = 'organization:extid_lookup'
    count      = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'organization:*:object', count: 1000)

      keys.each do |key|
        objid = @valkey.hget(key, 'objid')
        next if objid.to_s.empty?

        # Generate extid if not present
        extid = @valkey.hget(key, 'extid')
        if extid.to_s.empty?
          extid = generate_extid(EXTID_PREFIXES[:organization], objid)
          @valkey.hset(key, 'extid', extid) unless @dry_run
        end

        unless @dry_run
          @valkey.hset(lookup_key, extid, objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{lookup_key}"
    @stats[:extid_lookups][:created] += count
  end

  def build_customdomain_display_domain_index
    puts '  Building customdomain:display_domain_index...'

    index_key = 'customdomain:display_domain_index'
    count     = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customdomain:*:object', count: 1000)

      keys.each do |key|
        display_domain = @valkey.hget(key, 'display_domain')
        domainid       = key.split(':')[1] # Extract from key pattern

        next if display_domain.to_s.empty?

        unless @dry_run
          @valkey.hset(index_key, display_domain, domainid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} entries to #{index_key}"
    @stats[:unique_indexes][:created] += count
  end

  def build_membership_indexes
    puts '  Building org_membership indexes...'

    token_lookup        = 'org_membership:token_lookup'
    org_email_lookup    = 'org_membership:org_email_lookup'
    org_customer_lookup = 'org_membership:org_customer_lookup'
    count               = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'org_membership:*:object', count: 1000)

      keys.each do |key|
        membership = @valkey.hgetall(key)
        objid      = membership['objid']
        next if objid.to_s.empty?

        unless @dry_run
          # Token lookup
          unless membership['token'].to_s.empty?
            @valkey.hset(token_lookup, membership['token'], objid)
          end

          # Org+email lookup (for pending invites)
          org_objid     = membership['organization_objid']
          invited_email = membership['invited_email']
          if org_objid && invited_email
            composite_key = "#{org_objid}:#{invited_email.downcase}"
            @valkey.hset(org_email_lookup, composite_key, objid)
          end

          # Org+customer lookup (for active memberships)
          customer_objid = membership['customer_objid']
          if org_objid && customer_objid
            composite_key = "#{org_objid}:#{customer_objid}"
            @valkey.hset(org_customer_lookup, composite_key, objid)
          end
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Built membership indexes (#{count} memberships)"
    @stats[:unique_indexes][:created] += count
  end

  # ============================================
  # Phase 3: Participation Sets
  # ============================================

  def build_organization_members_sets
    puts '  Building organization:{objid}:members sets...'

    count = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'org_membership:*:object', count: 1000)

      keys.each do |key|
        membership = @valkey.hgetall(key)

        org_objid      = membership['organization_objid']
        customer_objid = membership['customer_objid']
        joined_at      = membership['joined_at'] || Time.now.to_f

        next if org_objid.to_s.empty? || customer_objid.to_s.empty?

        members_key = "organization:#{org_objid}:members"

        unless @dry_run
          @valkey.zadd(members_key, joined_at.to_f, customer_objid)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} member entries"
    @stats[:participation_sets][:created] += count
  end

  def build_organization_domains_sets
    puts '  Building organization:{objid}:domains sets...'

    count = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customdomain:*:object', count: 1000)

      keys.each do |key|
        org_id    = @valkey.hget(key, 'org_id')
        domain_id = key.split(':')[1]
        created   = @valkey.hget(key, 'created') || Time.now.to_f

        next if org_id.to_s.empty?

        domains_key = "organization:#{org_id}:domains"

        unless @dry_run
          @valkey.zadd(domains_key, created.to_f, domain_id)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} domain entries"
    @stats[:participation_sets][:created] += count
  end

  def build_organization_receipts_sets
    puts '  Building organization:{objid}:receipts sets...'

    count = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'receipt:*:object', count: 1000)

      keys.each do |key|
        org_id     = @valkey.hget(key, 'org_id')
        receipt_id = key.split(':')[1]
        created    = @valkey.hget(key, 'created') || Time.now.to_f

        next if org_id.to_s.empty?

        receipts_key = "organization:#{org_id}:receipts"

        unless @dry_run
          @valkey.zadd(receipts_key, created.to_f, receipt_id)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} receipt entries to organization sets"
    @stats[:participation_sets][:created] += count
  end

  def build_customdomain_receipts_sets
    puts '  Building customdomain:{domainid}:receipts sets...'

    count = 0

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'receipt:*:object', count: 1000)

      keys.each do |key|
        domain_id  = @valkey.hget(key, 'domain_id')
        receipt_id = key.split(':')[1]
        created    = @valkey.hget(key, 'created') || Time.now.to_f

        next if domain_id.to_s.empty?

        receipts_key = "customdomain:#{domain_id}:receipts"

        unless @dry_run
          @valkey.zadd(receipts_key, created.to_f, receipt_id)
        end
        count += 1
      end

      break if cursor == '0'
    end

    puts "    Added #{count} receipt entries to domain sets"
    @stats[:participation_sets][:created] += count
  end

  # ============================================
  # Reporting
  # ============================================

  def write_manifest
    manifest = {
      timestamp: @timestamp,
      valkey_url: @valkey_url.sub(/:[^:@]*@/, ':***@'),
      stats: @stats,
      errors: @errors.first(20),
    }

    manifest_file = "rebuild_indexes_manifest_#{@timestamp}.json"
    File.write(manifest_file, JSON.pretty_generate(manifest))
    puts "\n  Manifest: #{manifest_file}"
  end

  def print_summary
    puts "\n=== Index Rebuild Summary ==="
    puts "  Instances entries:       #{@stats[:instances][:created]}"
    puts "  Unique index entries:    #{@stats[:unique_indexes][:created]}"
    puts "  ExtID lookup entries:    #{@stats[:extid_lookups][:created]}"
    puts "  Participation set entries: #{@stats[:participation_sets][:created]}"
    puts "  Errors:                  #{@stats[:errors]}"
  end
end

def parse_args(args)
  options = {
    valkey_url: 'redis://127.0.0.1:6379/0',
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--valkey-url=(.+)$/
      options[:valkey_url] = Regexp.last_match(1)
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/rebuild_indexes.rb [OPTIONS]

        Options:
          --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
          --dry-run          Show what would be created
          --help             Show this help
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  rebuilder = IndexRebuilder.new(
    valkey_url: options[:valkey_url],
    dry_run: options[:dry_run],
  )

  rebuilder.rebuild_all
end
