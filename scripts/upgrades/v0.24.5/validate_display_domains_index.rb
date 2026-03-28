#!/usr/bin/env ruby
# frozen_string_literal: true

# DOM-VAL-024: Every live domain has entry in display_domains index
#
# Iterates custom_domain:instances sorted set, reads each domain's
# display_domain field from its object hash, then verifies
# HGET custom_domain:display_domains {display_domain} returns the
# correct domain identifier. Missing entries mean the domain can't
# be found by name even though the object exists.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/validate_display_domains_index.rb [--redis-url=URL]

require 'redis'
require 'uri'

redis_url = ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', 'redis://localhost:6379')

ARGV.each do |arg|
  redis_url = Regexp.last_match(1) if arg =~ /^--redis-url=(.+)$/
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
  return raw unless raw.is_a?(String) # Non-strings already normalized
  return raw if raw.empty?

  JSON.parse(raw)
rescue JSON::ParserError
  raw
end

# Check if two values match, accounting for JSON encoding differences.
def values_match?(val_a, val_b)
  return true if val_a == val_b
  normalize_value(val_a) == normalize_value(val_b)
end

# Try to find a value in a hash index, checking multiple key variants.
# Returns [key_used, value] or [nil, nil] if not found.
def hget_flexible(redis, hash_key, display_domain)
  domain_str = display_domain.to_s
  # Try exact case first
  value = redis.hget(hash_key, domain_str)
  return [domain_str, value] if value

  # Try lowercase
  lower = domain_str.downcase
  if lower != domain_str
    value = redis.hget(hash_key, lower)
    return [lower, value] if value
  end

  [nil, nil]
end

instances_key = 'custom_domain:instances'
display_domains_key = 'custom_domain:display_domains'

instance_ids = redis.zrange(instances_key, 0, -1)

missing_index = []
mismatched_index = []
no_display_domain = []

instance_ids.each do |domainid|
  object_key = "custom_domain:#{domainid}:object"

  # Read the display_domain field from the domain's object hash
  # May be JSON-encoded (Familia convention), so normalize it
  display_domain_raw = redis.hget(object_key, 'display_domain')
  display_domain = normalize_value(display_domain_raw)

  if display_domain.nil? || display_domain.to_s.empty?
    no_display_domain << domainid
    next
  end

  # Check the display_domains index maps this name back to this domainid
  # Try multiple key variants (exact case, lowercase)
  key_used, indexed_id = hget_flexible(redis, display_domains_key, display_domain)

  if indexed_id.nil?
    missing_index << { domainid: domainid, display_domain: display_domain }
  elsif !values_match?(indexed_id, domainid)
    mismatched_index << {
      domainid: domainid,
      display_domain: display_domain,
      indexed_as: normalize_value(indexed_id),
      key_used: key_used
    }
  end
end

puts "=== DOM-VAL-024: Display Domains Index Completeness ==="
puts ""
printf "Domains in instances:           %d\n", instance_ids.size
printf "Missing display_domain field:   %d\n", no_display_domain.size
printf "Missing from display_domains:   %d\n", missing_index.size
printf "Mismatched in display_domains:  %d\n", mismatched_index.size
puts ""

all_ok = no_display_domain.empty? && missing_index.empty? && mismatched_index.empty?

if all_ok
  puts "PASS: All live domains have correct entries in display_domains index."
else
  puts "FAIL: Issues found."

  unless no_display_domain.empty?
    puts ""
    puts "Domains with no display_domain field (#{no_display_domain.size}):"
    no_display_domain.each { |id| puts "  #{id}" }
  end

  unless missing_index.empty?
    puts ""
    puts "Domains missing from display_domains index (#{missing_index.size}):"
    missing_index.each do |entry|
      printf "  %-40s display_domain=%s\n", entry[:domainid], redact_fqdn(entry[:display_domain])
    end
  end

  unless mismatched_index.empty?
    puts ""
    puts "Domains with mismatched index entry (#{mismatched_index.size}):"
    mismatched_index.each do |entry|
      printf "  %-40s display_domain=%s indexed_as=%s\n",
             entry[:domainid], redact_fqdn(entry[:display_domain]), entry[:indexed_as]
    end
  end

  puts ""
  puts "Action required: Repair display_domains index for affected entries."
end

redis.close
