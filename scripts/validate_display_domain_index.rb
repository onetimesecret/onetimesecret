#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that the custom_domain:display_domains hash index is consistent
# with the actual domain objects in Redis.
#
# The display_domains hash is the primary lookup for incoming requests
# (FQDN -> domain objid). Stale entries cause wrong domain resolution.
#
# Three categories of inconsistency:
#
#   STALE    - Index entry points to a domain object that no longer exists
#   MISMATCH - Index entry exists but the domain's display_domain field
#              does not match the FQDN key in the index
#   MISSING  - A domain object exists with a display_domain but has no
#              corresponding entry in the display_domains index
#
# Usage:
#   bundle exec ruby scripts/validate_display_domain_index.rb [OPTIONS]
#
# Options:
#   --redis-url=URL      Redis/Valkey URL (default: env VALKEY_URL or REDIS_URL)
#   --redis-db=N         Override database number
#   --max-examples=N     Max examples per category in report (default: 20)
#   --json               Output as JSON instead of human-readable report
#   --help               Show this help

require 'json'

class DisplayDomainIndexValidator
  attr_reader :stats

  DISPLAY_DOMAINS_KEY = 'custom_domain:display_domains'

  def initialize(redis_url:, redis_db: nil, max_examples: 20, json_output: false)
    @redis_url = redis_url
    @redis_db = redis_db
    @max_examples = max_examples
    @json_output = json_output

    @stats = {
      index_entries_checked: 0,
      domains_scanned: 0,
      domains_with_display_domain: 0,
      stale: [],
      mismatch: [],
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

    # Phase 1: Walk the display_domains index and verify each entry
    scan_display_domains_index(redis)

    # Phase 2: Walk all domain objects and check for missing index entries
    scan_domain_objects(redis)

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
    @stats[:stale].empty? &&
      @stats[:mismatch].empty? &&
      @stats[:missing].empty?
  end

  private

  # Phase 1: HGETALL custom_domain:display_domains.
  # For each (fqdn, objid), check:
  #   - The domain object exists
  #   - Its display_domain field matches the fqdn key
  def scan_display_domains_index(redis)
    cursor = '0'
    loop do
      cursor, entries = redis.hscan(DISPLAY_DOMAINS_KEY, cursor, count: 100)

      entries.each do |fqdn, objid|
        @stats[:index_entries_checked] += 1

        objid = unwrap_json_string(objid) || objid
        domain_key = "custom_domain:#{objid}:object"

        # Check if domain object exists
        unless redis.exists?(domain_key)
          @stats[:stale] << { fqdn: fqdn, objid: objid }
          next
        end

        # Check display_domain field matches the index key
        actual_display_domain = redis.hget(domain_key, 'display_domain')
        actual_display_domain = unwrap_json_string(actual_display_domain)

        if actual_display_domain.nil? || actual_display_domain.downcase != fqdn.downcase
          @stats[:mismatch] << {
            fqdn: fqdn,
            objid: objid,
            actual_display_domain: actual_display_domain,
          }
        end
      end

      break if cursor == '0'
    end
  end

  # Phase 2: Walk every custom_domain:*:object hash.
  # For each domain with a display_domain, check it has a corresponding
  # entry in the display_domains index.
  def scan_domain_objects(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:object', count: 200)

      keys.each do |domain_key|
        @stats[:domains_scanned] += 1

        display_domain = redis.hget(domain_key, 'display_domain')
        display_domain = unwrap_json_string(display_domain)
        next if display_domain.nil? || display_domain.empty?

        @stats[:domains_with_display_domain] += 1

        objid = extract_domain_objid(domain_key)
        next unless objid

        # Check if this domain has a corresponding index entry
        indexed_objid = redis.hget(DISPLAY_DOMAINS_KEY, display_domain.downcase)
        indexed_objid = unwrap_json_string(indexed_objid) || indexed_objid

        if indexed_objid.nil?
          @stats[:missing] << { objid: objid, display_domain: display_domain }
        elsif indexed_objid != objid
          # Index points to a different domain for this display_domain
          @stats[:missing] << {
            objid: objid,
            display_domain: display_domain,
            indexed_to: indexed_objid,
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

    # Filter out class-level keys like "display_domains", "owners", "instances"
    objid = match[1]
    return nil if %w[display_domains owners instances display_domain_index].include?(objid)

    objid
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
        index_entries_checked: @stats[:index_entries_checked],
        domains_scanned: @stats[:domains_scanned],
        domains_with_display_domain: @stats[:domains_with_display_domain],
      },
      stale: {
        count: @stats[:stale].size,
        description: 'Index entry points to a domain object that no longer exists',
        examples: @stats[:stale].first(@max_examples),
      },
      mismatch: {
        count: @stats[:mismatch].size,
        description: 'Index entry exists but domain display_domain does not match',
        examples: @stats[:mismatch].first(@max_examples),
      },
      missing: {
        count: @stats[:missing].size,
        description: 'Domain has display_domain but no corresponding index entry',
        examples: @stats[:missing].first(@max_examples),
      },
      errors: @stats[:errors].first(10),
    })
  end

  def print_report
    puts
    puts '=== Display Domain Index Validation Report ==='
    puts "Index entries checked:      #{@stats[:index_entries_checked]}"
    puts "Domain objects scanned:     #{@stats[:domains_scanned]}"
    puts "Domains with display_domain: #{@stats[:domains_with_display_domain]}"
    puts

    print_category('STALE', @stats[:stale],
      'Index entry points to a domain object that no longer exists') do |e|
      "  #{e[:fqdn]}  objid=#{e[:objid]}"
    end

    print_category('MISMATCH', @stats[:mismatch],
      'Index entry exists but domain display_domain does not match') do |e|
      "  #{e[:fqdn]}  objid=#{e[:objid]}  actual=#{e[:actual_display_domain]}"
    end

    print_category('MISSING', @stats[:missing],
      'Domain has display_domain but no corresponding index entry') do |e|
      indexed = e[:indexed_to] ? "  indexed_to=#{e[:indexed_to]}" : ''
      "  #{e[:objid]} (#{e[:display_domain]})#{indexed}"
    end

    if success?
      puts 'RESULT: OK - No inconsistencies detected.'
    else
      total = @stats[:stale].size + @stats[:mismatch].size + @stats[:missing].size
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
        Usage: bundle exec ruby scripts/validate_display_domain_index.rb [OPTIONS]

        Validates the custom_domain:display_domains hash index against
        actual domain objects in Redis.

        Categories:
          STALE     Index entry points to a non-existent domain object
          MISMATCH  Index entry exists but display_domain field doesn't match
          MISSING   Domain has display_domain but no corresponding index entry

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

  validator = DisplayDomainIndexValidator.new(
    redis_url: options[:redis_url],
    redis_db: options[:redis_db],
    max_examples: options[:max_examples],
    json_output: options[:json_output],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
