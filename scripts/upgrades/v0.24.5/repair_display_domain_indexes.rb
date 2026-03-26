#!/usr/bin/env ruby
# frozen_string_literal: true

# Repair display_domain_index and display_domains mismatches
#
# The v0.24.5 migration used non-deterministic UUIDv7 generation (random bytes).
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
#   ruby scripts/upgrades/v0.24.5/repair_display_domain_indexes.rb [OPTIONS]
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
      Usage: ruby scripts/upgrades/v0.24.5/repair_display_domain_indexes.rb [OPTIONS]

      Repairs display_domain_index and display_domains mismatches caused by
      non-deterministic UUIDv7 generation during v0.24.5 migration.

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

# Normalize a value that may or may not be JSON-encoded.
# Familia HashKey values are JSON-serialized (strings have quotes),
# but sorted set members are raw strings. This handles both.
def normalize_value(raw)
  return nil if raw.nil?
  return raw if raw.empty?

  # Try parsing as JSON first (handles '"abc123"' -> 'abc123')
  JSON.parse(raw)
rescue JSON::ParserError
  # Not valid JSON, return as-is (handles raw 'abc123')
  raw
end

# Check if two values match, accounting for JSON encoding differences.
# Either value may be raw or JSON-encoded.
def values_match?(val_a, val_b)
  return true if val_a == val_b
  normalize_value(val_a) == normalize_value(val_b)
end

# Try to find a value in a hash index, checking multiple key variants.
# Returns [key_used, value] or [nil, nil] if not found.
def hget_flexible(redis, hash_key, display_domain)
  # Try exact case first
  value = redis.hget(hash_key, display_domain)
  return [display_domain, value] if value

  # Try lowercase
  lower = display_domain.downcase
  if lower != display_domain
    value = redis.hget(hash_key, lower)
    return [lower, value] if value
  end

  [nil, nil]
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

  # Normalize display_domain and objid from the :object hash
  # These are stored JSON-encoded by Familia, so parse them
  display_domain_raw = fields['display_domain']
  record_objid_raw = fields['objid']

  display_domain = normalize_value(display_domain_raw)
  record_objid = normalize_value(record_objid_raw)

  if display_domain.nil? || display_domain.to_s.empty?
    stats[:no_display_domain] += 1
    next
  end

  if record_objid.nil? || record_objid.to_s.empty?
    # Use instance_id as fallback (it's the key used in instances sorted set)
    record_objid = instance_id
  end

  # The correct index value should be JSON-encoded (Familia HashKey convention)
  correct_value_json = record_objid.to_json

  # Check display_domain_index - try multiple key variants
  key_1_used, indexed_value_1 = hget_flexible(redis, DISPLAY_DOMAIN_INDEX_KEY, display_domain)
  index_1_mismatch = indexed_value_1 && !values_match?(indexed_value_1, record_objid)

  # Check display_domains - try multiple key variants
  key_2_used, indexed_value_2 = hget_flexible(redis, DISPLAY_DOMAINS_KEY, display_domain)
  index_2_mismatch = indexed_value_2 && !values_match?(indexed_value_2, record_objid)

  if verbose || index_1_mismatch || index_2_mismatch
    puts "Checking: #{redact_fqdn(display_domain)}"
    puts "  record objid:           #{record_objid}"
    puts "  display_domain_index:   #{indexed_value_1 || '(missing)'} (key: #{key_1_used || 'n/a'})"
    puts "  display_domains:        #{indexed_value_2 || '(missing)'} (key: #{key_2_used || 'n/a'})"
  end

  if index_1_mismatch
    stats[:display_domain_index_mismatches] += 1
    puts "  MISMATCH in display_domain_index: has #{indexed_value_1}, should be #{correct_value_json}"

    unless dry_run
      # Update using the key that was found (preserves existing case convention)
      fix_key = key_1_used || display_domain
      redis.hset(DISPLAY_DOMAIN_INDEX_KEY, fix_key, correct_value_json)
      stats[:fixed_display_domain_index] += 1
      puts "  FIXED display_domain_index (key: #{fix_key})"
    end
  end

  if index_2_mismatch
    stats[:display_domains_mismatches] += 1
    puts "  MISMATCH in display_domains: has #{indexed_value_2}, should be #{correct_value_json}"

    unless dry_run
      # Update using the key that was found (preserves existing case convention)
      fix_key = key_2_used || display_domain
      redis.hset(DISPLAY_DOMAINS_KEY, fix_key, correct_value_json)
      stats[:fixed_display_domains] += 1
      puts "  FIXED display_domains (key: #{fix_key})"
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
