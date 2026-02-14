#!/usr/bin/env ruby
# frozen_string_literal: true

# DOM-VAL-004: Validate instances sorted set and owners hash have identical domain sets
#
# Compares ZRANGE custom_domain:instances 0 -1 (as set) vs
# HKEYS custom_domain:owners (as set). Reports symmetric differences.
# Both are written by create!/add and removed by rem. Differences
# reveal claim_orphaned_domain bugs or partial operations.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/validate_instances_owners_parity.rb [--redis-url=URL]

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

# Retrieve both collections
instances_key = 'custom_domain:instances'
owners_key = 'custom_domain:owners'

instance_members = redis.zrange(instances_key, 0, -1).to_set
owner_keys = redis.hkeys(owners_key).to_set

# Compute symmetric difference
in_instances_only = instance_members - owner_keys
in_owners_only = owner_keys - instance_members

puts "=== DOM-VAL-004: Instances vs Owners Parity Check ==="
puts ""
printf "Entries in instances sorted set:  %d\n", instance_members.size
printf "Entries in owners hash:           %d\n", owner_keys.size
puts ""

if in_instances_only.empty? && in_owners_only.empty?
  puts "PASS: instances and owners have identical domain ID sets."
else
  puts "FAIL: Symmetric differences found."
  puts ""

  unless in_instances_only.empty?
    puts "In instances but NOT in owners (#{in_instances_only.size}):"
    in_instances_only.each { |id| puts "  #{id}" }
    puts ""
  end

  unless in_owners_only.empty?
    puts "In owners but NOT in instances (#{in_owners_only.size}):"
    in_owners_only.each { |id| puts "  #{id}" }
    puts ""
  end

  puts "Action required: Reconcile stale entries in instances or owners."
end

redis.close
