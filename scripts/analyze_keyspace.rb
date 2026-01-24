#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyzes Redis keyspace to discover unique key patterns and hash field structures.
# Usage: ruby scripts/analyze_keyspace.rb [database_number]
#
# Output: JSON with key patterns, field structures, and sample keys

require 'redis'
require 'json'

class KeyspaceAnalyzer
  # Patterns to detect variable segments in keys
  ID_PATTERNS = {
    uuid: /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
    sha256: /\b[0-9a-f]{64}\b/i,
    sha1_or_token: /\b[0-9a-f]{40}\b/i,
    md5_or_short_hash: /\b[0-9a-f]{32}\b/i,
    short_token: /\b[0-9a-f]{16,31}\b/i,
    objid: /\b[0-9a-z]{12,16}\b/,  # Familia-style object IDs
    numeric_id: /\b\d{6,}\b/,
    timestamp: /\b\d{10,13}\b/,
    email_like: /\b[^:@\s]+@[^:@\s]+\.[^:@\s]+\b/,
    domain_like: /\b[a-z0-9][-a-z0-9]*\.[a-z]{2,}\b/i,
  }.freeze

  HASH_SAMPLE_SIZE = 5  # Number of hash keys to sample per pattern

  def initialize(db_number, redis_url: 'redis://127.0.0.1:6379')
    @db_number = db_number
    @redis = Redis.new(url: "#{redis_url}/#{db_number}")
    @patterns = Hash.new { |h, k| h[k] = { count: 0, samples: [], types: Set.new } }
    @hash_fields = Hash.new { |h, k| h[k] = { samples: [], field_sets: [] } }
  end

  def analyze
    scan_keys
    sample_hash_fields
    build_report
  end

  private

  def scan_keys
    cursor = '0'
    loop do
      cursor, keys = @redis.scan(cursor, count: 1000)
      keys.each { |key| process_key(key) }
      break if cursor == '0'
    end
  end

  def process_key(key)
    pattern = extract_pattern(key)
    key_type = @redis.type(key)

    entry = @patterns[pattern]
    entry[:count] += 1
    entry[:types] << key_type
    entry[:samples] << key if entry[:samples].size < 3
  end

  def extract_pattern(key)
    parts = key.split(':')
    parts.map { |part| normalize_part(part) }.join(':')
  end

  def normalize_part(part)
    return part if part.empty?

    ID_PATTERNS.each do |type, regex|
      if part.match?(regex)
        # Check if the entire part is the pattern or just contains it
        if part.match?(/\A#{regex.source}\z/i)
          return "{#{type}}"
        end
      end
    end

    # Check for pure numeric
    return '{numeric}' if part.match?(/\A\d+\z/)

    # Check for mixed alphanumeric that looks like an ID (not a word)
    return '{id}' if part.match?(/\A[a-z0-9]{8,}\z/i) && !part.match?(/\A[a-z]+\z/i)

    part
  end

  def sample_hash_fields
    @patterns.each do |pattern, data|
      next unless data[:types].include?('hash')

      samples = data[:samples].first(HASH_SAMPLE_SIZE)
      samples.each do |key|
        fields = @redis.hgetall(key)
        @hash_fields[pattern][:field_sets] << fields.keys.sort
        @hash_fields[pattern][:samples] << {
          key: key,
          fields: fields.transform_values { |v| truncate_value(v) }
        }
      end
    end
  end

  def truncate_value(value)
    return value if value.nil?

    # Handle binary data that can't be converted to UTF-8
    safe_value = begin
      value.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    rescue Encoding::UndefinedConversionError
      "[binary data: #{value.bytesize} bytes]"
    end

    safe_value.length > 100 ? "#{safe_value[0..97]}..." : safe_value
  end

  def build_report
    {
      database: @db_number,
      analyzed_at: Time.now.utc.iso8601,
      summary: {
        total_keys: @patterns.values.sum { |p| p[:count] },
        unique_patterns: @patterns.size,
        types_found: @patterns.values.flat_map { |p| p[:types].to_a }.uniq.sort
      },
      patterns: @patterns.map do |pattern, data|
        entry = {
          pattern: pattern,
          count: data[:count],
          types: data[:types].to_a,
          sample_keys: data[:samples]
        }

        if @hash_fields.key?(pattern)
          field_data = @hash_fields[pattern]
          # Find common fields across all samples
          all_field_sets = field_data[:field_sets]
          common_fields = all_field_sets.reduce { |a, b| a & b } || []
          all_fields = all_field_sets.flatten.uniq.sort

          entry[:hash_analysis] = {
            common_fields: common_fields,
            all_fields_seen: all_fields,
            field_variance: all_field_sets.uniq.size > 1,
            sample_data: field_data[:samples]
          }
        end

        entry
      end.sort_by { |p| -p[:count] }
    }
  end
end

if __FILE__ == $0
  db = (ARGV[0] || 0).to_i
  analyzer = KeyspaceAnalyzer.new(db)
  result = analyzer.analyze

  puts JSON.pretty_generate(result)
end
