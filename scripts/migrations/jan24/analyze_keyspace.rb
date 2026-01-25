#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyzes Redis keyspace to discover unique key patterns and hash field structures.
# Usage: ruby scripts/analyze_keyspace.rb [database_number]
#
# Output: JSON with key patterns, field structures, index stats, and sample keys

require 'redis'
require 'json'

class KeyspaceAnalyzer
  # Known Familia class prefixes - preserve these as literals
  KNOWN_PREFIXES = Set.new(
    %w[
      session customer customdomain secret metadata
      emailreceipt feedback onetime
    ],
  ).freeze

  # Patterns to detect variable segments in keys (order matters - checked sequentially)
  ID_PATTERNS = {
    email: /\A[^:@\s]+@[^:@\s]+\.[^:@\s]+\z/,
    uuid: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
    sha256: /\A[0-9a-f]{64}\z/i,
    sha1: /\A[0-9a-f]{40}\z/i,
    md5: /\A[0-9a-f]{32}\z/i,
    objid: /\A[0-9a-f]{20}\z/i,  # Familia 20-char hex identifiers
    token: /\A[0-9a-f]{16,31}\z/i,
    numeric: /\A\d+\z/,
  }.freeze

  HASH_SAMPLE_SIZE = 5  # Number of hash keys to sample per pattern

  def initialize(db_number, redis_url: 'redis://127.0.0.1:6379')
    @db_number   = db_number
    @redis       = Redis.new(url: "#{redis_url}/#{db_number}")
    @patterns    = Hash.new { |h, k| h[k] = { count: 0, samples: [], types: Set.new } }
    @hash_fields = Hash.new { |h, k| h[k] = { samples: [], field_sets: [] } }
    @index_stats = {}  # zset index name => { member_count, sample_members }
  end

  def analyze
    scan_keys
    sample_hash_fields
    analyze_indexes
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
    pattern  = extract_pattern(key)
    key_type = @redis.type(key)

    entry          = @patterns[pattern]
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

    # Preserve known class prefixes as literals
    return part if KNOWN_PREFIXES.include?(part.downcase)

    # Check against ID patterns
    ID_PATTERNS.each do |type, regex|
      return "{#{type}}" if part.match?(regex)
    end

    # Fallback: mixed alphanumeric that looks like an ID (8+ chars, not pure letters)
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
          fields: fields.transform_values { |v| truncate_value(v) },
        }
      end
    end
  end

  def analyze_indexes
    @patterns.each do |_pattern, data|
      next unless data[:types].include?('zset')

      # Familia indexes are typically singleton zsets like "onetime:customer"
      data[:samples].each do |key|
        member_count   = @redis.zcard(key)
        sample_members = @redis.zrange(key, 0, 4)  # First 5 members

        @index_stats[key] = {
          member_count: member_count,
          sample_members: sample_members,
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
    sorted_patterns = build_pattern_entries.sort_by { |p| -p[:count] }

    {
      database: @db_number,
      analyzed_at: Time.now.utc.iso8601,
      summary: {
        total_keys: @patterns.values.sum { |p| p[:count] },
        unique_patterns: @patterns.size,
        types_found: @patterns.values.flat_map { |p| p[:types].to_a }.uniq.sort,
      },
      patterns: sorted_patterns,
      indexes: @index_stats,
    }
  end

  def build_pattern_entries
    @patterns.map do |pattern, data|
      entry = {
        pattern: pattern,
        count: data[:count],
        types: data[:types].to_a,
        sample_keys: data[:samples],
      }

      if @hash_fields.key?(pattern)
        field_data     = @hash_fields[pattern]
        all_field_sets = field_data[:field_sets]
        common_fields  = all_field_sets.reduce { |a, b| a & b } || []
        all_fields     = all_field_sets.flatten.uniq.sort

        entry[:hash_analysis] = {
          common_fields: common_fields,
          all_fields_seen: all_fields,
          field_variance: all_field_sets.uniq.size > 1,
          sample_data: field_data[:samples],
        }
      end

      entry
    end
  end
end

if __FILE__ == $0
  db       = (ARGV[0] || 0).to_i
  analyzer = KeyspaceAnalyzer.new(db)
  result   = analyzer.analyze

  puts JSON.pretty_generate(result)
end
