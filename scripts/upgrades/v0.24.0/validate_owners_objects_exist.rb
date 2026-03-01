#!/usr/bin/env ruby
# frozen_string_literal: true

# DOM-VAL-031: Every entry in owners hash has valid corresponding object
#
# Reads HKEYS custom_domain:owners and checks that each domain ID
# has a corresponding custom_domain:{id}:object key in Redis.
# Missing objects indicate a domain was deleted but rem() failed
# partway through, leaving a stale owners entry.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/validate_owners_objects_exist.rb [--redis-url=URL]

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

owners_key = 'custom_domain:owners'
owner_entries = redis.hgetall(owners_key)

orphaned = []

owner_entries.each do |domainid, org_id|
  object_key = "custom_domain:#{domainid}:object"
  unless redis.exists(object_key) > 0
    orphaned << { domainid: domainid, org_id: org_id }
  end
end

puts "=== DOM-VAL-031: Owners Hash Object Existence Check ==="
puts ""
printf "Entries in owners hash:   %d\n", owner_entries.size
printf "Missing object keys:      %d\n", orphaned.size
puts ""

if orphaned.empty?
  puts "PASS: All entries in owners hash have corresponding object keys."
else
  puts "FAIL: Stale entries found in owners hash (domain object deleted, owners entry remains)."
  puts ""
  orphaned.each do |entry|
    printf "  domainid=%-40s org_id=%s\n", entry[:domainid], entry[:org_id]
  end
  puts ""
  puts "Action required: Remove stale entries from custom_domain:owners."
end

redis.close
