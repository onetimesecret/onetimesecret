#!/usr/bin/env ruby
# frozen_string_literal: true

# Detects domains with nil org_id that still appear in organization
# domain sorted sets.
#
# This is a targeted consistency check: if a domain has nil org_id,
# it should NOT appear in ANY organization:*:domains ZSET. If it does,
# the domain looks owned from the org side but acts unowned from the
# domain side -- a split-brain state.
#
# Categories:
#
#   LEAKED   - Domain has nil/empty org_id but appears in at least one
#              organization's domains ZSET
#
# Usage:
#   bundle exec ruby scripts/validate_orphan_domain_zset_leaks.rb [OPTIONS]
#
# Options:
#   --redis-url=URL      Redis/Valkey URL (default: env VALKEY_URL or REDIS_URL)
#   --redis-db=N         Override database number
#   --max-examples=N     Max examples per category in report (default: 20)
#   --json               Output as JSON instead of human-readable report
#   --help               Show this help

require 'json'

class OrphanDomainZsetLeakValidator
  attr_reader :stats

  def initialize(redis_url:, redis_db: nil, max_examples: 20, json_output: false)
    @redis_url = redis_url
    @redis_db = redis_db
    @max_examples = max_examples
    @json_output = json_output

    @stats = {
      domains_scanned: 0,
      orphaned_domains: 0,
      org_zsets_checked: 0,
      leaked: [],
      errors: [],
    }
  end

  def run
    require 'redis'
    require 'uri'

    raise ArgumentError, 'Redis URL is required' unless @redis_url

    uri = URI.parse(@redis_url)
    uri.path = "/#{@redis_db}" if @redis_db
    redis = Redis.new(url: uri.to_s)

    # Step 1: Find all domains with nil/empty org_id
    orphan_objids = find_orphaned_domains(redis)

    # Step 2: Scan all org domain ZSETs for leaked orphans
    check_org_zsets_for_orphans(redis, orphan_objids)

    if @json_output
      print_json_report
    else
      print_report
    end

    success?
  ensure
    redis&.close
  end

  def success?
    @stats[:leaked].empty?
  end

  private

  def find_orphaned_domains(redis)
    orphans = {}
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:object', count: 200)

      keys.each do |domain_key|
        @stats[:domains_scanned] += 1

        objid = extract_domain_objid(domain_key)
        next unless objid

        org_id = redis.hget(domain_key, 'org_id')
        org_id = unwrap_json_string(org_id)

        if org_id.nil? || org_id.empty?
          @stats[:orphaned_domains] += 1
          display_domain = unwrap_json_string(redis.hget(domain_key, 'display_domain'))
          orphans[objid] = display_domain
        end
      end

      break if cursor == '0'
    end
    orphans
  end

  def check_org_zsets_for_orphans(redis, orphan_objids)
    return if orphan_objids.empty?

    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'organization:*:domains', count: 100)

      keys.each do |zset_key|
        @stats[:org_zsets_checked] += 1
        org_id = extract_org_id(zset_key)
        next unless org_id

        members = redis.zrange(zset_key, 0, -1)
        members.each do |member_objid|
          next unless orphan_objids.key?(member_objid)

          @stats[:leaked] << {
            objid: member_objid,
            display_domain: orphan_objids[member_objid],
            org_id: org_id,
            zset_key: zset_key,
          }
        end
      end

      break if cursor == '0'
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def extract_domain_objid(domain_key)
    match = domain_key.match(/^custom_domain:([^:]+):object$/)
    return nil unless match

    objid = match[1]
    return nil if %w[display_domains owners instances display_domain_index].include?(objid)

    objid
  end

  def extract_org_id(zset_key)
    match = zset_key.match(/^organization:([^:]+):domains$/)
    match ? match[1] : nil
  end

  def unwrap_json_string(value)
    return nil if value.nil?
    return nil if value == 'null'

    parsed = JSON.parse(value)
    parsed.is_a?(String) ? parsed : nil
  rescue JSON::ParserError
    value
  end

  # ── Report ──────────────────────────────────────────────────────────

  def print_json_report
    puts JSON.pretty_generate({
      summary: {
        success: success?,
        domains_scanned: @stats[:domains_scanned],
        orphaned_domains: @stats[:orphaned_domains],
        org_zsets_checked: @stats[:org_zsets_checked],
      },
      leaked: {
        count: @stats[:leaked].size,
        description: 'Orphaned domain (nil org_id) found in an organization domains ZSET',
        examples: @stats[:leaked].first(@max_examples),
      },
      errors: @stats[:errors].first(10),
    })
  end

  def print_report
    puts
    puts '=== Orphan Domain ZSET Leak Detection Report ==='
    puts "Domains scanned:          #{@stats[:domains_scanned]}"
    puts "Orphaned domains found:   #{@stats[:orphaned_domains]}"
    puts "Org ZSET keys checked:    #{@stats[:org_zsets_checked]}"
    puts

    print_category('LEAKED', @stats[:leaked],
      'Orphaned domain (nil org_id) found in an organization domains ZSET') do |e|
      "  #{e[:objid]} (#{e[:display_domain]})  in #{e[:zset_key]}"
    end

    if success?
      puts 'RESULT: OK - No leaked orphans detected.'
    else
      puts "RESULT: FAIL - #{@stats[:leaked].size} leaked orphans found."
    end
    puts

    return unless @stats[:errors].any?

    puts "Errors (#{@stats[:errors].size}):"
    @stats[:errors].first(10).each { |err| puts "  #{err}" }
    puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
  end

  def print_category(label, entries, description)
    count = entries.size
    status = count.zero? ? 'OK' : 'WARN'
    puts "#{label}: #{count} [#{status}]"

    if count > 0
      puts "  #{description}"
      entries.first(@max_examples).each do |entry|
        puts yield(entry)
      end
      puts "  ... and #{count - @max_examples} more" if count > @max_examples
    end

    puts
  end
end

# ── CLI ────────────────────────────────────────────────────────────────

def parse_args(args)
  options = {
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    redis_db: nil,
    max_examples: 20,
    json_output: false,
  }

  args.each do |arg|
    case arg
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--redis-db=(\d+)$/
      options[:redis_db] = Regexp.last_match(1).to_i
    when /^--max-examples=(\d+)$/
      options[:max_examples] = Regexp.last_match(1).to_i
    when '--json'
      options[:json_output] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: bundle exec ruby scripts/validate_orphan_domain_zset_leaks.rb [OPTIONS]

        Detects domains with nil org_id that still appear in organization
        domain sorted sets (split-brain state).

        Categories:
          LEAKED  Orphaned domain (nil org_id) found in an org domains ZSET

        Options:
          --redis-url=URL      Redis/Valkey URL (env: VALKEY_URL or REDIS_URL)
          --redis-db=N         Override database number
          --max-examples=N     Max examples per category (default: 20)
          --json               Output as JSON
          --help               Show this help
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  validator = OrphanDomainZsetLeakValidator.new(
    redis_url: options[:redis_url],
    redis_db: options[:redis_db],
    max_examples: options[:max_examples],
    json_output: options[:json_output],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
