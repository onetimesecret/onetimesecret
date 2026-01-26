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
# - customer:instances (zset: objid -> created)
# - customer:email_index (hash: email -> objid)
# - customer:extid_lookup (hash: extid -> objid)
# - customer:objid_lookup (hash: objid -> objid JSON serialized string)
# - customer:secrets_created
# - customer:secrets_shared
# - organization:instances (zset: objid -> created)
# - organization:contact_email_index (hash: contact_email -> objid)
# - organization:stripe_customer_id_index (hash: stripe_customer_id -> objid)
# - organization:stripe_subscription_id_index (hash: stripe_subscription_id -> objid)
# - organization:{objid}:members (zset: auto-populated by Familia participates_in)
# - organization:{objid}:domains (zset: auto-populated by Familia participates_in)
# - customdomain:instances (zset: domainid -> created)
# - customdomain:display_domain_index (hash: display_domain -> domainid)
# - customdomain:display_domains
# - customdomain:extid_lookup
# - customdomain:instances
# - customdomain:objid_lookup (hash: objid -> objid JSON serialized string)
# - customdomain:owners
# - receipt:instances (zset: objid -> created)
# - receipt:expiration_timeline (zset: expires date -> objid)
# - receipt:objid_lookup (hash: objid -> objid JSON serialized string)
# - secret:instances (zset: objid -> created)
# - secret:objid_lookup (hash: objid -> objid JSON serialized string)

require 'redis'
require 'json'
require 'securerandom'

require_relative 'rebuild_indexes/base'
require_relative 'rebuild_indexes/customer_indexes'
require_relative 'rebuild_indexes/organization_indexes'
require_relative 'rebuild_indexes/membership_indexes'
require_relative 'rebuild_indexes/customdomain_indexes'
require_relative 'rebuild_indexes/receipt_indexes'
require_relative 'rebuild_indexes/secret_indexes'

# Orchestrates the index rebuilding process across all models
class IndexRebuilderOrchestrator
  def initialize(valkey_url:, dry_run: false)
    @valkey_url = valkey_url
    @dry_run    = dry_run
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    @stats = {
      instances: { created: 0 },
      unique_indexes: { created: 0 },
      extid_lookups: { created: 0 },
      stripe_indexes: { created: 0 },
      class_hashkeys: { created: 0 },
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

    # Initialize model-specific builders
    customer     = IndexRebuilder::CustomerIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)
    organization = IndexRebuilder::OrganizationIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)
    membership   = IndexRebuilder::MembershipIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)
    customdomain = IndexRebuilder::CustomdomainIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)
    receipt      = IndexRebuilder::ReceiptIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)
    secret       = IndexRebuilder::SecretIndexes.new(valkey: @valkey, dry_run: @dry_run, stats: @stats)

    # Phase 1: Build instances sorted sets
    puts "\n=== Phase 1: Building instances sorted sets ==="
    customer.build_instances
    organization.build_instances
    membership.build_instances
    customdomain.build_instances
    receipt.build_instances
    secret.build_instances

    # Phase 2: Build unique indexes
    puts "\n=== Phase 2: Building unique indexes ==="
    customer.build_email_index
    customer.build_extid_lookup
    organization.build_contact_email_index
    organization.build_extid_lookup
    organization.build_stripe_customer_id_index
    organization.build_stripe_subscription_id_index
    customdomain.build_display_domain_index
    membership.build_lookup_indexes

    # Phase 2b: Build class hashkeys (model-level lookup hashes)
    puts "\n=== Phase 2b: Building class hashkeys ==="
    customdomain.build_class_hashkeys

    # Phase 3: Build participation sets
    puts "\n=== Phase 3: Building participation sets ==="
    organization.build_participation_sets
    customdomain.build_participation_sets

    # Write manifest
    write_manifest unless @dry_run

    print_summary
  end

  private

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
    puts "  Instances entries:         #{@stats[:instances][:created]}"
    puts "  Unique index entries:      #{@stats[:unique_indexes][:created]}"
    puts "  ExtID lookup entries:      #{@stats[:extid_lookups][:created]}"
    puts "  Stripe index entries:      #{@stats[:stripe_indexes][:created]}"
    puts "  Class hashkey entries:     #{@stats[:class_hashkeys][:created]}"
    puts "  Participation set entries: #{@stats[:participation_sets][:created]}"
    puts "  Errors:                    #{@stats[:errors]}"
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

  orchestrator = IndexRebuilderOrchestrator.new(
    valkey_url: options[:valkey_url],
    dry_run: options[:dry_run],
  )

  orchestrator.rebuild_all
end
