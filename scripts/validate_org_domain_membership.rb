#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that every member of an organization's domain sorted set
# has a matching org_id field pointing back to that organization.
#
# Detects phantom memberships where a domain was moved to another org
# but the old sorted set was not cleaned up.
#
# Three categories of inconsistency:
#
#   PHANTOM  - Domain is in org's ZSET but its org_id is nil or points
#              to a different organization
#   ORPHAN   - Org ZSET member that doesn't exist as a domain object
#   STALE    - Domain's org_id points to a non-existent organization
#   MISSING  - Domain has org_id set but is NOT in the corresponding
#              org's domains ZSET
#
# Usage:
#   bundle exec ruby scripts/validate_org_domain_membership.rb [OPTIONS]
#
# Options:
#   --redis-url=URL      Redis/Valkey URL (default: env VALKEY_URL or REDIS_URL)
#   --redis-db=N         Override database number
#   --max-examples=N     Max examples per category in report (default: 20)
#   --json               Output as JSON instead of human-readable report
#   --help               Show this help

require 'json'

class OrgDomainMembershipValidator
  attr_reader :stats

  def initialize(redis_url:, redis_db: nil, max_examples: 20, json_output: false)
    @redis_url = redis_url
    @redis_db = redis_db
    @max_examples = max_examples
    @json_output = json_output

    @stats = {
      orgs_scanned: 0,
      zset_members_checked: 0,
      domains_scanned: 0,
      domains_with_org_id: 0,
      phantoms: [],
      orphans: [],
      stale: [],
      missing: [],
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

    # Phase 1: Scan all organization:*:domains ZSETs for phantoms and orphans
    scan_org_domain_zsets(redis)

    # Phase 2: Scan all custom_domain:*:object hashes for stale org refs and missing ZSET entries
    scan_domain_hashes(redis)

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
    @stats[:phantoms].empty? &&
      @stats[:orphans].empty? &&
      @stats[:stale].empty? &&
      @stats[:missing].empty?
  end

  private

  # Phase 1: Walk every organization:*:domains ZSET.
  # For each member, check that the domain exists and its org_id
  # matches the organization key.
  def scan_org_domain_zsets(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'organization:*:domains', count: 100)

      keys.each do |zset_key|
        org_id = extract_org_id(zset_key)
        next unless org_id

        @stats[:orgs_scanned] += 1
        members = redis.zrange(zset_key, 0, -1)

        members.each do |objid|
          @stats[:zset_members_checked] += 1
          domain_key = "custom_domain:#{objid}:object"

          # Check if domain hash exists at all
          unless redis.exists?(domain_key)
            @stats[:orphans] << { objid: objid, zset_org_id: org_id }
            next
          end

          # Check org_id field matches
          actual_org_id = redis.hget(domain_key, 'org_id')
          actual_org_id = unwrap_json_string(actual_org_id)

          if actual_org_id.nil? || actual_org_id.empty? || actual_org_id != org_id
            @stats[:phantoms] << {
              objid: objid,
              display_domain: unwrap_json_string(redis.hget(domain_key, 'display_domain')),
              zset_org_id: org_id,
              actual_org_id: actual_org_id,
            }
          end
        end
      end

      break if cursor == '0'
    end
  end

  # Phase 2: Walk every custom_domain:*:object hash.
  # For each domain with an org_id, verify the org exists and
  # the domain appears in the org's ZSET.
  def scan_domain_hashes(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:object', count: 200)

      keys.each do |domain_key|
        @stats[:domains_scanned] += 1

        org_id = redis.hget(domain_key, 'org_id')
        org_id = unwrap_json_string(org_id)
        next if org_id.nil? || org_id.empty?

        @stats[:domains_with_org_id] += 1

        objid = extract_domain_objid(domain_key)
        next unless objid

        display_domain = unwrap_json_string(redis.hget(domain_key, 'display_domain'))

        # Check if the referenced organization actually exists
        org_key = "organization:#{org_id}:object"
        unless redis.exists?(org_key)
          @stats[:stale] << { objid: objid, display_domain: display_domain, org_id: org_id }
          next
        end

        # Check if domain is in the org's ZSET
        zset_key = "organization:#{org_id}:domains"
        score = redis.zscore(zset_key, objid)

        if score.nil?
          @stats[:missing] << { objid: objid, display_domain: display_domain, org_id: org_id }
        end
      end

      break if cursor == '0'
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def extract_org_id(zset_key)
    match = zset_key.match(/^organization:([^:]+):domains$/)
    match ? match[1] : nil
  end

  def extract_domain_objid(domain_key)
    match = domain_key.match(/^custom_domain:([^:]+):object$/)
    match ? match[1] : nil
  end

  def unwrap_json_string(value)
    return nil if value.nil?
    return nil if value == 'null'

    # Familia v2 JSON-encodes values, so "abc" is stored as "\"abc\""
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
        orgs_scanned: @stats[:orgs_scanned],
        zset_members_checked: @stats[:zset_members_checked],
        domains_scanned: @stats[:domains_scanned],
        domains_with_org_id: @stats[:domains_with_org_id],
      },
      phantoms: {
        count: @stats[:phantoms].size,
        description: 'Domain in org ZSET but org_id is nil or mismatched',
        examples: @stats[:phantoms].first(@max_examples),
      },
      orphans: {
        count: @stats[:orphans].size,
        description: 'Org ZSET member that does not exist as a domain object',
        examples: @stats[:orphans].first(@max_examples),
      },
      stale: {
        count: @stats[:stale].size,
        description: 'Domain org_id points to a non-existent organization',
        examples: @stats[:stale].first(@max_examples),
      },
      missing: {
        count: @stats[:missing].size,
        description: 'Domain has org_id but is not in the corresponding org ZSET',
        examples: @stats[:missing].first(@max_examples),
      },
      errors: @stats[:errors].first(10),
    })
  end

  def print_report
    puts
    puts '=== Organization Domain Membership Validation Report ==='
    puts "Organizations scanned:     #{@stats[:orgs_scanned]}"
    puts "ZSET members checked:      #{@stats[:zset_members_checked]}"
    puts "Domain hashes scanned:     #{@stats[:domains_scanned]}"
    puts "Domains with org_id:       #{@stats[:domains_with_org_id]}"
    puts

    print_category('PHANTOM', @stats[:phantoms],
      'Domain in org ZSET but org_id is nil or mismatched') do |e|
      org_info = e[:actual_org_id] ? "actual=#{e[:actual_org_id]}" : 'actual=nil'
      "  #{e[:objid]} (#{e[:display_domain]})  zset=#{e[:zset_org_id]}  #{org_info}"
    end

    print_category('ORPHAN', @stats[:orphans],
      'Org ZSET member that does not exist as a domain object') do |e|
      "  #{e[:objid]}  zset=#{e[:zset_org_id]}"
    end

    print_category('STALE', @stats[:stale],
      'Domain org_id points to a non-existent organization') do |e|
      "  #{e[:objid]} (#{e[:display_domain]})  org_id=#{e[:org_id]}"
    end

    print_category('MISSING', @stats[:missing],
      'Domain has org_id but is not in the corresponding org ZSET') do |e|
      "  #{e[:objid]} (#{e[:display_domain]})  org_id=#{e[:org_id]}"
    end

    if success?
      puts 'RESULT: OK - No inconsistencies detected.'
    else
      total = @stats[:phantoms].size + @stats[:orphans].size +
              @stats[:stale].size + @stats[:missing].size
      puts "RESULT: FAIL - #{total} inconsistencies found."
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
        Usage: bundle exec ruby scripts/validate_org_domain_membership.rb [OPTIONS]

        Validates that every member of an organization's domain sorted set
        has a matching org_id field pointing back to that organization.

        Categories:
          PHANTOM  Domain in org ZSET but org_id is nil/mismatched
          ORPHAN   Org ZSET member that doesn't exist as a domain
          STALE    Domain org_id points to a non-existent organization
          MISSING  Domain has org_id but not in corresponding ZSET

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

  validator = OrgDomainMembershipValidator.new(
    redis_url: options[:redis_url],
    redis_db: options[:redis_db],
    max_examples: options[:max_examples],
    json_output: options[:json_output],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
