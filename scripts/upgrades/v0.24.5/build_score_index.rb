#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/upgrades/v0.24.5/build_score_index.rb
#
# Build a sorted set ordered by a hash field for a Familia v1 model.
# The output zset is consumed by the RabbitMQ/Kicks-driven migration worker
# to process oldest records first (lowest score = earliest timestamp).
#
# Default: dry-run. Pass --execute to write to Redis.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/build_score_index.rb [OPTIONS]
#
# Options:
#   --prefix=NAME       Model prefix to scan, e.g. customer (required)
#   --field=NAME        Hash field to use as score, e.g. updated (required)
#   --output=KEY        Destination sorted set key (required)
#   --fallback=NAME     Fallback field when primary is missing (optional)
#   --on-missing=POLICY :skip, :default, or :fallback_field (default: skip)
#   --default-score=N   Score for on-missing: :default (default: 0)
#   --batch-size=N      Keys per Lua call (default: 500)
#   --redis-url=URL     Redis URL (env: VALKEY_URL or REDIS_URL)
#   --clear             DEL output key before indexing
#   --execute           Write to Redis (default is dry-run)
#   --verbose           Extra output
#   --help              Show this help
#
# Examples:
#   # Preview what would be indexed
#   ruby build_score_index.rb --prefix=customer --field=updated \
#     --output=ots:migration:customer:by_updated
#
#   # Build the index
#   ruby build_score_index.rb --prefix=customer --field=updated \
#     --output=ots:migration:customer:by_updated --execute
#
#   # With fallback and clear
#   ruby build_score_index.rb --prefix=customdomain --field=updated \
#     --fallback=created --on-missing=fallback_field \
#     --output=ots:migration:customdomain:by_updated --clear --execute

require 'uri'

# Load from project root when run via `ruby scripts/…`
$LOAD_PATH.unshift(File.join(__dir__, '..', '..', '..', 'lib'))
require 'onetime/services/zset_indexer'

def parse_args(args)
  options = {
    redis_url:     ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    prefix:        nil,
    field:         nil,
    output:        nil,
    fallback:      nil,
    on_missing:    :skip,
    default_score: 0,
    batch_size:    500,
    clear:         false,
    execute:       false,
    verbose:       false,
  }

  args.each do |arg|
    case arg
    when /\A--prefix=(.+)\z/
      options[:prefix] = Regexp.last_match(1)
    when /\A--field=(.+)\z/
      options[:field] = Regexp.last_match(1)
    when /\A--output=(.+)\z/
      options[:output] = Regexp.last_match(1)
    when /\A--fallback=(.+)\z/
      options[:fallback] = Regexp.last_match(1)
    when /\A--on-missing=(.+)\z/
      options[:on_missing] = Regexp.last_match(1).to_sym
    when /\A--default-score=(\d+)\z/
      options[:default_score] = Regexp.last_match(1).to_i
    when /\A--batch-size=(\d+)\z/
      options[:batch_size] = Regexp.last_match(1).to_i
    when /\A--redis-url=(.+)\z/
      options[:redis_url] = Regexp.last_match(1)
    when '--clear'
      options[:clear] = true
    when '--execute'
      options[:execute] = true
    when '--verbose'
      options[:verbose] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.5/build_score_index.rb [OPTIONS]

        Build a sorted set from Familia v1 hash fields without per-key round trips.
        Uses Lua server-side aggregation to read N keys per EVAL call, then
        a pipelined ZADD batch — ~500x fewer round trips than the naive approach.

        Options:
          --prefix=NAME       Model prefix (e.g. customer, customdomain, secret)
          --field=NAME        Hash field to score by (e.g. updated, created)
          --output=KEY        Destination sorted set key
          --fallback=NAME     Fallback field when primary is missing
          --on-missing=POLICY skip|default|fallback_field  (default: skip)
          --default-score=N   Score for on-missing:default (default: 0)
          --batch-size=N      Keys per Lua call (default: 500)
          --redis-url=URL     Redis URL (env: VALKEY_URL or REDIS_URL)
          --clear             DEL output key before indexing
          --execute           Write to Redis (default: dry-run)
          --verbose           Extra output
          --help              Show this help

        Examples:
          ruby build_score_index.rb --prefix=customer --field=updated \\
            --output=ots:migration:customer:by_updated

          ruby build_score_index.rb --prefix=customer --field=updated \\
            --output=ots:migration:customer:by_updated --execute

          ruby build_score_index.rb --prefix=customdomain --field=updated \\
            --fallback=created --on-missing=fallback_field \\
            --output=ots:migration:customdomain:by_updated --clear --execute
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

options = parse_args(ARGV)

missing = %i[prefix field output].select { |k| options[k].nil? }
unless missing.empty?
  warn "Missing required options: #{missing.map { "--#{it}" }.join(', ')}"
  warn "Use --help for usage."
  exit 1
end

unless options[:redis_url]
  warn 'No Redis URL: set VALKEY_URL or REDIS_URL env, or pass --redis-url=...'
  exit 1
end

puts "build_score_index"
puts "  redis:      #{options[:redis_url].gsub(/:[^:@]+@/, ':***@')}"
puts "  prefix:     #{options[:prefix]}"
puts "  field:      #{options[:field]}"
puts "  output:     #{options[:output]}"
puts "  on_missing: #{options[:on_missing]}#{options[:on_missing] == :fallback_field ? " (#{options[:fallback]})" : ''}"
puts "  batch_size: #{options[:batch_size]}"
puts "  clear:      #{options[:clear]}"
puts "  mode:       #{options[:execute] ? 'EXECUTE' : 'DRY RUN'}"
puts

indexer = Onetime::Services::ZsetIndexer.new(
  redis_url:       options[:redis_url],
  model_prefix:    options[:prefix],
  field_name:      options[:field],
  output_zset_key: options[:output],
  fallback_field:  options[:fallback],
  on_missing:      options[:on_missing],
  default_score:   options[:default_score],
  batch_size:      options[:batch_size],
  clear_first:     options[:clear],
)

result = indexer.run(execute: options[:execute])

exit(result[:errors].empty? ? 0 : 1)
