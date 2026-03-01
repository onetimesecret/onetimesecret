#!/usr/bin/env ruby
# frozen_string_literal: true

# DOM-VAL-005: Validate no domain appears in multiple orgs' sorted sets
#
# Scans all organization:*:domains sorted-set keys, builds a map of
# domain objid -> [org_ids]. Reports any domain that appears in more
# than one organization. This can occur if add_domain fails the
# already-belongs check or if a migration maps the same domain to
# multiple orgs.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/validate_domain_org_exclusivity.rb [--redis-url=URL]

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

# Scan for all organization:*:domains sorted-set keys
domain_to_orgs = Hash.new { |h, k| h[k] = [] }
org_count = 0

cursor = '0'
loop do
  cursor, keys = redis.scan(cursor, match: 'organization:*:domains', count: 500)

  keys.each do |key|
    # Extract org objid from key pattern: organization:<objid>:domains
    parts = key.split(':')
    next unless parts.length == 3

    org_objid = parts[1]
    org_count += 1

    # Get all domain objids from this org's domains sorted set
    members = redis.zrange(key, 0, -1)
    members.each do |domain_objid|
      domain_to_orgs[domain_objid] << org_objid
    end
  end

  break if cursor == '0'
end

# Report results
total_domains = domain_to_orgs.size
duplicates = domain_to_orgs.select { |_domain, orgs| orgs.length > 1 }

puts "=== DOM-VAL-005: Domain-to-Organization Exclusivity Check ==="
puts ""
printf "Organizations scanned:  %d\n", org_count
printf "Unique domain entries:  %d\n", total_domains
printf "Multi-org domains:      %d\n", duplicates.size
puts ""

if duplicates.empty?
  puts "PASS: No domain appears in multiple organizations' sorted sets."
else
  puts "FAIL: The following domains appear in multiple organizations:"
  puts ""
  duplicates.each do |domain_objid, org_ids|
    printf "  Domain %-40s => orgs: %s\n", domain_objid, org_ids.join(', ')
  end
  puts ""
  puts "Action required: Remove stale entries from organization sorted sets."
end

redis.close
