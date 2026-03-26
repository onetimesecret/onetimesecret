#!/usr/bin/env ruby
# frozen_string_literal: true

# Repair instance index scores for customer, custom_domain, and organization
#
# The v0.24.5 migration used Time.now as a fallback when the `created` timestamp
# wasn't available in the JSONL envelope. This caused sorted set scores to reflect
# migration execution time rather than actual record creation time.
#
# This script:
# 1. Iterates all members in each model's :instances sorted set
# 2. Reads the stored `created` field from each record's :object hash
# 3. Compares to the current ZSCORE
# 4. Updates mismatched scores with ZADD
#
# The record's stored `created` field is the source of truth.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/repair_instance_index_scores.rb [OPTIONS]
#
# Options:
#   --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
#   --execute        Actually apply fixes (default: dry-run)
#   --verbose        Show details for every record checked

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
      Usage: ruby scripts/upgrades/v0.24.5/repair_instance_index_scores.rb [OPTIONS]

      Repairs instance index scores for customer, custom_domain, and organization.
      Fixes scores that used Time.now fallback instead of actual created timestamps.

      Options:
        --redis-url=URL  Redis URL (env: VALKEY_URL or REDIS_URL)
        --execute        Actually apply fixes (default: dry-run)
        --verbose        Show details for every record checked

      Affected indexes:
        customer:instances
        custom_domain:instances
        organization:instances
    HELP
    exit 0
  end
end

uri = URI.parse(redis_url)
uri.path = '/0'
redis = Redis.new(url: uri.to_s)
redis.ping

MODELS = [
  { name: 'customer', instances_key: 'customer:instances', object_prefix: 'customer' },
  { name: 'custom_domain', instances_key: 'custom_domain:instances', object_prefix: 'custom_domain' },
  { name: 'organization', instances_key: 'organization:instances', object_prefix: 'organization' },
].freeze

def parse_json_value(raw)
  return nil if raw.nil?
  JSON.parse(raw)
rescue JSON::ParserError
  raw
end

puts "=== Instance Index Score Repair Tool ==="
puts ""
puts "Redis: #{redis_url.gsub(/:[^:@]+@/, ':***@')}"
puts "Mode:  #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
puts ""

total_stats = { checked: 0, mismatches: 0, fixed: 0 }

MODELS.each do |model|
  stats = { checked: 0, mismatches: 0, fixed: 0 }

  members = redis.zrange(model[:instances_key], 0, -1, with_scores: true)

  members.each do |objid, score|
    stats[:checked] += 1

    object_key = "#{model[:object_prefix]}:#{objid}:object"
    created_raw = redis.hget(object_key, 'created')

    unless created_raw
      puts "  SKIP: #{objid} - no created field" if verbose
      next
    end

    stored_created = parse_json_value(created_raw)
    stored_ts = stored_created.to_f.to_i
    index_ts = score.to_i

    diff = (stored_ts - index_ts).abs

    if diff <= 1
      puts "  OK: #{objid}" if verbose
      next
    end

    stats[:mismatches] += 1

    if verbose
      puts "  MISMATCH: #{objid}"
      puts "    stored created: #{stored_ts}"
      puts "    index score:    #{index_ts}"
      puts "    diff:           #{diff}s"
    end

    unless dry_run
      redis.zadd(model[:instances_key], stored_ts, objid)
      stats[:fixed] += 1
      puts "    FIXED" if verbose
    end
  end

  puts "#{model[:name]}:"
  puts "  Checked:    #{stats[:checked]}"
  puts "  Mismatches: #{stats[:mismatches]}"
  puts "  Fixed:      #{stats[:fixed]}" unless dry_run
  puts ""

  total_stats[:checked] += stats[:checked]
  total_stats[:mismatches] += stats[:mismatches]
  total_stats[:fixed] += stats[:fixed]
end

puts "=== Summary ==="
puts ""
puts "Total checked:    #{total_stats[:checked]}"
puts "Total mismatches: #{total_stats[:mismatches]}"

if dry_run
  if total_stats[:mismatches] > 0
    puts ""
    puts "DRY RUN: #{total_stats[:mismatches]} score(s) would be fixed."
    puts "Run with --execute to apply fixes."
  else
    puts "No mismatches found."
  end
else
  puts "Total fixed:      #{total_stats[:fixed]}"
  if total_stats[:fixed] > 0
    puts ""
    puts "Repairs complete. Instance indexes now reflect actual creation timestamps."
  end
end

redis.close

exit(total_stats[:mismatches] > 0 ? 1 : 0) if dry_run
