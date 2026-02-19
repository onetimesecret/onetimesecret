#!/usr/bin/env ruby
# frozen_string_literal: true

# DOM-VAL-062: Verify owners hash can be rebuilt from org_id fields
#
# For each domain in custom_domain:instances, reads org_id from the
# domain's object hash and builds an expected {domainid => org_id} map.
# Compares this against HGETALL custom_domain:owners. Differences
# reveal the claim_orphaned_domain bug in action. The rebuilt map
# (from object fields) is authoritative.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/validate_owners_from_org_id.rb [--redis-url=URL] [--repair]

require 'redis'
require 'uri'

redis_url = ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', 'redis://localhost:6379')
repair_mode = false

ARGV.each do |arg|
  redis_url = Regexp.last_match(1) if arg =~ /^--redis-url=(.+)$/
  repair_mode = true if arg == '--repair'
end

uri = URI.parse(redis_url)
uri.path = '/0'
redis = Redis.new(url: uri.to_s)
redis.ping

instances_key = 'custom_domain:instances'
owners_key = 'custom_domain:owners'

# Build expected owners map from domain object fields (authoritative source)
instance_ids = redis.zrange(instances_key, 0, -1)
expected_owners = {}
missing_org_id = []

instance_ids.each do |domainid|
  object_key = "custom_domain:#{domainid}:object"
  org_id = redis.hget(object_key, 'org_id')

  if org_id.nil? || org_id.empty?
    missing_org_id << domainid
  else
    expected_owners[domainid] = org_id
  end
end

# Read actual owners hash
actual_owners = redis.hgetall(owners_key)

# Compare
mismatched = []
missing_from_owners = []
extra_in_owners = []

expected_owners.each do |domainid, expected_org|
  actual_org = actual_owners[domainid]
  if actual_org.nil?
    missing_from_owners << { domainid: domainid, expected_org: expected_org }
  elsif actual_org != expected_org
    mismatched << { domainid: domainid, expected_org: expected_org, actual_org: actual_org }
  end
end

(actual_owners.keys.to_set - expected_owners.keys.to_set).each do |domainid|
  extra_in_owners << { domainid: domainid, org_id: actual_owners[domainid] }
end

puts "=== DOM-VAL-062: Owners Hash vs org_id Fields ==="
puts ""
printf "Domains in instances:        %d\n", instance_ids.size
printf "Domains with org_id field:   %d\n", expected_owners.size
printf "Domains without org_id:      %d\n", missing_org_id.size
printf "Entries in owners hash:      %d\n", actual_owners.size
puts ""
printf "Missing from owners hash:    %d\n", missing_from_owners.size
printf "Mismatched org_id values:    %d\n", mismatched.size
printf "Extra entries in owners:     %d\n", extra_in_owners.size
puts ""

all_ok = missing_org_id.empty? && missing_from_owners.empty? && mismatched.empty? && extra_in_owners.empty?

if all_ok
  puts "PASS: Owners hash is consistent with domain object org_id fields."
else
  puts "FAIL: Inconsistencies found."

  unless missing_org_id.empty?
    puts ""
    puts "Domains with no org_id field (#{missing_org_id.size}):"
    missing_org_id.each { |id| puts "  #{id}" }
  end

  unless missing_from_owners.empty?
    puts ""
    puts "Missing from owners hash (#{missing_from_owners.size}):"
    missing_from_owners.each do |entry|
      printf "  %-40s should map to org %s\n", entry[:domainid], entry[:expected_org]
    end
  end

  unless mismatched.empty?
    puts ""
    puts "Mismatched org_id (#{mismatched.size}):"
    mismatched.each do |entry|
      printf "  %-40s object.org_id=%s  owners=%s\n",
             entry[:domainid], entry[:expected_org], entry[:actual_org]
    end
  end

  unless extra_in_owners.empty?
    puts ""
    puts "Extra entries in owners (not in instances) (#{extra_in_owners.size}):"
    extra_in_owners.each do |entry|
      printf "  %-40s org_id=%s\n", entry[:domainid], entry[:org_id]
    end
  end

  if repair_mode
    puts ""
    puts "REPAIR MODE: Rebuilding owners hash from authoritative org_id fields..."
    redis.del(owners_key)
    expected_owners.each do |domainid, org_id|
      redis.hset(owners_key, domainid, org_id)
    end
    puts "Rebuilt owners hash with #{expected_owners.size} entries."
  else
    puts ""
    puts "Hint: Run with --repair to rebuild the owners hash from authoritative org_id fields."
  end
end

redis.close
