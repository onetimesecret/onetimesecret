#!/usr/bin/env ruby
# frozen_string_literal: true

# Repair display_domain_index and display_domains mismatches
#
# The v0.24.0 migration used non-deterministic UUIDv7 generation (random bytes).
# If the enrichment step was run multiple times, or if transform.rb and
# create_indexes.rb read different states of the dump file, the objid stored
# in the indexes may differ from the objid in the actual domain records.
#
# This script:
# 1. Iterates all domains in custom_domain:instances
# 2. Reads each domain's objid from its :object hash
# 3. Checks both display_domain_index and display_domains for mismatches
# 4. Updates the indexes to contain the correct objid from the record
#
# The record's objid is considered the source of truth because that's what
# the application uses when calling identifier().
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/repair_display_domain_indexes.rb [OPTIONS]
#
# Options:
#   --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
#   --execute        Actually apply fixes (default: dry-run)
#   --verbose        Show details for every domain checked

require 'redis'
require 'json'
require 'uri'

redis_url = ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', 'redis://localhost:6379')
dry_run = true
verbose = false

ARGV.each do |arg|
  case arg
  when /^--redis-url=(.+)$/
    redis_url = Regexp.last_match(1)
  when '--execute'
    dry_run = false
  when '--verbose'
    verbose = true
  when '--help', '-h'
    puts <<~HELP
      Usage: ruby scripts/upgrades/v0.24.0/repair_display_domain_indexes.rb [OPTIONS]

      Repairs display_domain_index and display_domains mismatches caused by
      non-deterministic UUIDv7 generation during v0.24.0 migration.

      Options:
        --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
        --execute        Actually apply fixes (default: dry-run)
        --verbose        Show details for every domain checked

      Affected indexes:
        custom_domain:display_domain_index  (unique_index - Familia auto-uses this)
        custom_domain:display_domains       (class_hashkey - manual lookups)

      Both indexes map display_domain (FQDN) -> objid (JSON-encoded).
    HELP
    exit 0
  end
end

uri = URI.parse(redis_url)
uri.path = '/0'
redis = Redis.new(url: uri.to_s)
redis.ping

def redact_fqdn(fqdn)
  return '***' unless fqdn.is_a?(String) && fqdn.include?('.')
  parts = fqdn.split('.')
  parts[0] = '***'
  parts[-2] = '***' if parts.size >= 2
  parts.join('.')
end

INSTANCES_KEY = 'custom_domain:instances'
DISPLAY_DOMAIN_INDEX_KEY = 'custom_domain:display_domain_index'
DISPLAY_DOMAINS_KEY = 'custom_domain:display_domains'

stats = {
  total_domains: 0,
  checked: 0,
  no_display_domain: 0,
  display_domain_index_mismatches: 0,
  display_domains_mismatches: 0,
  fixed_display_domain_index: 0,
  fixed_display_domains: 0,
  errors: []
}

# Get all domain identifiers from instances
instance_ids = redis.zrange(INSTANCES_KEY, 0, -1)
stats[:total_domains] = instance_ids.size

puts "=== Display Domain Index Repair Tool ==="
puts ""
puts "Redis: #{redis_url.gsub(/:[^:@]+@/, ':***@')}"
puts "Mode:  #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
puts "Domains to check: #{stats[:total_domains]}"
puts ""

instance_ids.each do |instance_id|
  stats[:checked] += 1

  object_key = "custom_domain:#{instance_id}:object"

  # Read the domain's fields
  fields = redis.hgetall(object_key)

  if fields.empty?
    stats[:errors] << { id: instance_id, error: 'Object hash not found' }
    next
  end

  display_domain = fields['display_domain']
  record_objid = fields['objid']

  if display_domain.nil? || display_domain.empty?
    stats[:no_display_domain] += 1
    next
  end

  if record_objid.nil? || record_objid.empty?
    # Use instance_id as fallback (it's the key used in instances sorted set)
    record_objid = instance_id
  end

  # The record's objid (JSON-encoded) is what the indexes should contain
  # Familia stores values as JSON, so "abc123" in Ruby becomes '"abc123"' in Redis
  record_objid_json = record_objid.to_json

  # Check display_domain_index
  indexed_value_1 = redis.hget(DISPLAY_DOMAIN_INDEX_KEY, display_domain)
  index_1_mismatch = indexed_value_1 && indexed_value_1 != record_objid_json

  # Check display_domains
  indexed_value_2 = redis.hget(DISPLAY_DOMAINS_KEY, display_domain)
  index_2_mismatch = indexed_value_2 && indexed_value_2 != record_objid_json

  if verbose || index_1_mismatch || index_2_mismatch
    puts "Checking: #{redact_fqdn(display_domain)}"
    puts "  record objid:           #{record_objid}"
    puts "  display_domain_index:   #{indexed_value_1 || '(missing)'}"
    puts "  display_domains:        #{indexed_value_2 || '(missing)'}"
  end

  if index_1_mismatch
    stats[:display_domain_index_mismatches] += 1
    puts "  MISMATCH in display_domain_index: has #{indexed_value_1}, should be #{record_objid_json}"

    unless dry_run
      redis.hset(DISPLAY_DOMAIN_INDEX_KEY, display_domain, record_objid_json)
      stats[:fixed_display_domain_index] += 1
      puts "  FIXED display_domain_index"
    end
  end

  if index_2_mismatch
    stats[:display_domains_mismatches] += 1
    puts "  MISMATCH in display_domains: has #{indexed_value_2}, should be #{record_objid_json}"

    unless dry_run
      redis.hset(DISPLAY_DOMAINS_KEY, display_domain, record_objid_json)
      stats[:fixed_display_domains] += 1
      puts "  FIXED display_domains"
    end
  end

  puts "" if verbose || index_1_mismatch || index_2_mismatch
end

puts ""
puts "=== Summary ==="
puts ""
printf "Domains in instances:                  %d\n", stats[:total_domains]
printf "Domains checked:                       %d\n", stats[:checked]
printf "Missing display_domain field:          %d\n", stats[:no_display_domain]
printf "Errors (no object hash):               %d\n", stats[:errors].size
puts ""
printf "display_domain_index mismatches:       %d\n", stats[:display_domain_index_mismatches]
printf "display_domains mismatches:            %d\n", stats[:display_domains_mismatches]
puts ""

if dry_run
  total_mismatches = stats[:display_domain_index_mismatches] + stats[:display_domains_mismatches]
  if total_mismatches > 0
    puts "DRY RUN: #{total_mismatches} mismatch(es) would be fixed."
    puts "Run with --execute to apply fixes."
  else
    puts "No mismatches found."
  end
else
  printf "Fixed display_domain_index:            %d\n", stats[:fixed_display_domain_index]
  printf "Fixed display_domains:                 %d\n", stats[:fixed_display_domains]

  if stats[:fixed_display_domain_index] > 0 || stats[:fixed_display_domains] > 0
    puts ""
    puts "Repairs complete. Affected domains should now save without errors."
  end
end

unless stats[:errors].empty?
  puts ""
  puts "=== Errors ==="
  stats[:errors].each do |err|
    puts "  #{err[:id]}: #{err[:error]}"
  end
end

redis.close

exit(stats[:display_domain_index_mismatches] + stats[:display_domains_mismatches] > 0 ? 1 : 0) if dry_run
