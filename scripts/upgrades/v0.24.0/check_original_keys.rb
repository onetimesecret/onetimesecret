#!/usr/bin/env ruby
# frozen_string_literal: true

# Counts :object and :_original_object keys per model type in Redis DB 0.
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/check_original_keys.rb [--redis-url=URL]

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

MODEL_PREFIXES = %w[customer custom_domain receipt secret organization].freeze

counts = {}
MODEL_PREFIXES.each do |prefix|
  counts[prefix] = { object: 0, _original_object: 0 }
end

cursor = '0'
loop do
  cursor, keys = redis.scan(cursor, count: 1000)

  keys.each do |key|
    MODEL_PREFIXES.each do |prefix|
      if key.start_with?("#{prefix}:") && key.end_with?(':object')
        counts[prefix][:object] += 1
      elsif key.start_with?("#{prefix}:") && key.end_with?(':_original_object')
        counts[prefix][:_original_object] += 1
      end
    end
  end

  break if cursor == '0'
end

# Also count CustomDomain-specific _original_* keys
cd_related = { _original_brand: 0, _original_logo: 0, _original_icon: 0 }
cursor = '0'
loop do
  cursor, keys = redis.scan(cursor, match: 'custom_domain:*:_original_*', count: 1000)

  keys.each do |key|
    suffix = key.split(':').last
    cd_related[suffix.to_sym] += 1 if cd_related.key?(suffix.to_sym)
  end

  break if cursor == '0'
end

puts "=== Redis DB 0: object vs _original_object counts ==="
puts ""
printf "%-20s %10s %20s %s\n", 'Model', ':object', ':_original_object', 'Coverage'
printf "%-20s %10s %20s %s\n", '-' * 20, '-' * 10, '-' * 20, '-' * 10

counts.each do |prefix, c|
  pct = c[:object] > 0 ? format('%.1f%%', (c[:_original_object].to_f / c[:object]) * 100) : 'n/a'
  printf "%-20s %10d %20d %s\n", prefix, c[:object], c[:_original_object], pct
end

if cd_related.values.any?(&:positive?)
  puts ""
  puts "CustomDomain related _original_* keys:"
  cd_related.each do |suffix, count|
    printf "  %-30s %d\n", suffix, count
  end
end

redis.close
