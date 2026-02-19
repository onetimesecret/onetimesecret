#!/usr/bin/env ruby
# frozen_string_literal: true

# Detects inconsistencies between three sources of truth for receipt-domain
# relationships in Redis:
#
#   1. Domain ZSETs    — custom_domain:{id}:receipts (actual membership)
#   2. Domain ID field — receipt:{id}:object HGET domain_id (what the hash says)
#   3. Participations  — receipt:{id}:participations SET (reverse index for cleanup)
#
# Six categories of inconsistency:
#
#   PHANTOM     - Receipt in a domain ZSET but domain_id is nil or mismatched
#   ORPHAN      - Domain ZSET member that doesn't exist as a receipt object
#   STALE       - Receipt's domain_id points to a non-existent domain
#   MISSING     - Receipt has domain_id but is NOT in the corresponding ZSET
#   DRIFT_EXTRA - Participations set claims domain ZSET membership that doesn't exist
#   DRIFT_GONE  - Receipt is in a domain ZSET but participations set has no record of it
#
# The primary production risk is the v0.24.0 migration script which sets
# ZSET membership (ZADD) and domain_id on the hash in separate phases.
# The V2 API code (index_receipt_to_domain) is safe — it guards with a
# domain existence check before both setting domain_id AND calling
# add_to_custom_domain_receipts atomically.
#
# Usage:
#   bundle exec ruby scripts/detect_phantom_receipts.rb [OPTIONS]
#
# Options:
#   --redis-url=URL      Redis/Valkey URL (default: env VALKEY_URL or REDIS_URL)
#   --redis-db=N         Override database number
#   --max-examples=N     Max examples per category in report (default: 20)
#   --json               Output as JSON instead of human-readable report
#   --help               Show this help

require 'json'

class PhantomReceiptDetector
  attr_reader :stats

  def initialize(redis_url:, redis_db: nil, max_examples: 20, json_output: false)
    @redis_url = redis_url
    @redis_db = redis_db
    @max_examples = max_examples
    @json_output = json_output

    @stats = {
      domains_scanned: 0,
      zset_members_checked: 0,
      receipts_scanned: 0,
      receipts_with_domain_id: 0,
      participations_checked: 0,
      phantoms: [],
      orphans: [],
      stale: [],
      missing: [],
      drift_extra: [],
      drift_gone: [],
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

    # Phase 1: Scan domain ZSETs for phantoms and orphans
    scan_domain_zsets(redis)

    # Phase 2: Scan receipt hashes for stale domain refs and missing ZSET entries
    scan_receipt_hashes(redis)

    # Phase 3: Three-way consistency check via participations sets
    scan_participations(redis)

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
      @stats[:missing].empty? &&
      @stats[:drift_extra].empty? &&
      @stats[:drift_gone].empty?
  end

  private

  # ── Phase 1 ─────────────────────────────────────────────────────────
  # Walk every custom_domain:*:receipts ZSET.
  # For each member, check that the receipt exists and its domain_id
  # matches the ZSET's domain.
  def scan_domain_zsets(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:receipts', count: 100)

      keys.each do |zset_key|
        domain_id = extract_domain_id(zset_key)
        next unless domain_id

        @stats[:domains_scanned] += 1
        members = redis.zrange(zset_key, 0, -1)

        members.each do |objid|
          @stats[:zset_members_checked] += 1
          receipt_key = "receipt:#{objid}:object"

          unless redis.exists?(receipt_key)
            @stats[:orphans] << { objid: objid, zset_domain_id: domain_id }
            next
          end

          actual_domain_id = redis.hget(receipt_key, 'domain_id')
          actual_domain_id = unwrap_json_string(actual_domain_id)

          if actual_domain_id.nil? || actual_domain_id.empty? || actual_domain_id != domain_id
            @stats[:phantoms] << {
              objid: objid,
              zset_domain_id: domain_id,
              actual_domain_id: actual_domain_id,
            }
          end
        end
      end

      break if cursor == '0'
    end
  end

  # ── Phase 2 ─────────────────────────────────────────────────────────
  # Walk every receipt:*:object hash.
  # For each receipt with a domain_id, verify the domain exists and
  # the receipt appears in the domain's ZSET.
  def scan_receipt_hashes(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'receipt:*:object', count: 200)

      keys.each do |receipt_key|
        @stats[:receipts_scanned] += 1

        domain_id = redis.hget(receipt_key, 'domain_id')
        domain_id = unwrap_json_string(domain_id)
        next if domain_id.nil? || domain_id.empty?

        @stats[:receipts_with_domain_id] += 1

        objid = extract_objid(receipt_key)
        next unless objid

        domain_key = "custom_domain:#{domain_id}:object"
        unless redis.exists?(domain_key)
          @stats[:stale] << { objid: objid, domain_id: domain_id }
          next
        end

        zset_key = "custom_domain:#{domain_id}:receipts"
        score = redis.zscore(zset_key, objid)

        if score.nil?
          @stats[:missing] << { objid: objid, domain_id: domain_id }
        end
      end

      break if cursor == '0'
    end
  end

  # ── Phase 3 ─────────────────────────────────────────────────────────
  # Walk every receipt:*:participations SET.
  # For each domain ZSET key listed in the participations set, verify:
  #   (a) the receipt is actually a member of that ZSET (drift_extra if not)
  #   (b) the ZSET has the receipt as a member but participations doesn't
  #       list it (drift_gone — checked from Phase 1 data)
  #
  # This catches split-phase migration issues where SADD and ZADD
  # got out of sync.
  def scan_participations(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'receipt:*:participations', count: 200)

      keys.each do |part_key|
        objid = extract_participations_objid(part_key)
        next unless objid

        # Familia v2 stores participation members as JSON-encoded strings,
        # so the raw SET member may be quoted: "\"custom_domain:abc:receipts\""
        raw_members = redis.smembers(part_key)
        domain_zset_keys = raw_members
          .map { |m| unwrap_participations_member(m) }
          .compact
          .select { |m| m.match?(/^custom_domain:[^:]+:receipts$/) }

        next if domain_zset_keys.empty?

        @stats[:participations_checked] += 1

        domain_zset_keys.each do |zset_key|
          # Check: does the ZSET actually contain this receipt?
          score = redis.zscore(zset_key, objid)

          if score.nil?
            domain_id = extract_domain_id(zset_key)
            @stats[:drift_extra] << {
              objid: objid,
              participations_claims: zset_key,
              domain_id: domain_id,
            }
          end
        end
      end

      break if cursor == '0'
    end

    # Reverse check: find receipts in domain ZSETs that have NO
    # participations entry for that ZSET. Re-scan domain ZSETs
    # but only check the participations set (Phase 1 already
    # validated the hash and ZSET).
    scan_missing_participations(redis)
  end

  # For each receipt in a domain ZSET, check that the receipt's
  # participations set contains the ZSET key. If not, the reverse
  # index is incomplete and destroy! won't clean up properly.
  def scan_missing_participations(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:receipts', count: 100)

      keys.each do |zset_key|
        members = redis.zrange(zset_key, 0, -1)

        members.each do |objid|
          part_key = "receipt:#{objid}:participations"

          # Skip if receipt doesn't exist (already flagged as ORPHAN)
          next unless redis.exists?("receipt:#{objid}:object")

          # Check both raw and JSON-quoted forms since Familia v2
          # stores members as JSON strings
          has_entry = redis.sismember(part_key, zset_key) ||
                      redis.sismember(part_key, zset_key.to_json)

          unless has_entry
            domain_id = extract_domain_id(zset_key)
            @stats[:drift_gone] << {
              objid: objid,
              zset_key: zset_key,
              domain_id: domain_id,
            }
          end
        end
      end

      break if cursor == '0'
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def extract_domain_id(key)
    match = key.match(/^custom_domain:([^:]+):receipts$/)
    match ? match[1] : nil
  end

  def extract_objid(receipt_key)
    match = receipt_key.match(/^receipt:([^:]+):object$/)
    match ? match[1] : nil
  end

  def extract_participations_objid(part_key)
    match = part_key.match(/^receipt:([^:]+):participations$/)
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

  # Familia v2 stores participations SET members as JSON strings,
  # e.g. "\"custom_domain:abc:receipts\"". Unwrap the quoting.
  def unwrap_participations_member(raw)
    return raw unless raw.start_with?('"')

    parsed = JSON.parse(raw)
    parsed.is_a?(String) ? parsed : raw
  rescue JSON::ParserError
    raw
  end

  # ── Report ──────────────────────────────────────────────────────────

  def print_json_report
    puts JSON.pretty_generate({
      summary: {
        success: success?,
        domains_scanned: @stats[:domains_scanned],
        zset_members_checked: @stats[:zset_members_checked],
        receipts_scanned: @stats[:receipts_scanned],
        receipts_with_domain_id: @stats[:receipts_with_domain_id],
        participations_checked: @stats[:participations_checked],
      },
      phantoms: format_category(@stats[:phantoms],
        'Receipt in domain ZSET but domain_id is nil or mismatched'),
      orphans: format_category(@stats[:orphans],
        'Domain ZSET member that does not exist as a receipt object'),
      stale: format_category(@stats[:stale],
        'Receipt domain_id points to a non-existent domain'),
      missing: format_category(@stats[:missing],
        'Receipt has domain_id but is not in the corresponding domain ZSET'),
      drift_extra: format_category(@stats[:drift_extra],
        'Participations set claims domain ZSET membership that does not exist'),
      drift_gone: format_category(@stats[:drift_gone],
        'Receipt in domain ZSET but participations set has no record of it'),
      errors: @stats[:errors].first(10),
    })
  end

  def format_category(entries, description)
    {
      count: entries.size,
      description: description,
      examples: entries.first(@max_examples),
    }
  end

  def print_report
    puts
    puts '=== Phantom Receipt Detection Report ==='
    puts "Domains scanned:           #{@stats[:domains_scanned]}"
    puts "ZSET members checked:      #{@stats[:zset_members_checked]}"
    puts "Receipt hashes scanned:    #{@stats[:receipts_scanned]}"
    puts "Receipts with domain_id:   #{@stats[:receipts_with_domain_id]}"
    puts "Participations checked:    #{@stats[:participations_checked]}"
    puts

    print_category('PHANTOM', @stats[:phantoms],
      'Receipt in domain ZSET but domain_id is nil or mismatched') do |e|
      domain_info = e[:actual_domain_id] ? "actual=#{e[:actual_domain_id]}" : 'actual=nil'
      "  #{e[:objid]}  zset=#{e[:zset_domain_id]}  #{domain_info}"
    end

    print_category('ORPHAN', @stats[:orphans],
      'Domain ZSET member that does not exist as a receipt object') do |e|
      "  #{e[:objid]}  zset=#{e[:zset_domain_id]}"
    end

    print_category('STALE', @stats[:stale],
      'Receipt domain_id points to a non-existent domain') do |e|
      "  #{e[:objid]}  domain_id=#{e[:domain_id]}"
    end

    print_category('MISSING', @stats[:missing],
      'Receipt has domain_id but is not in the corresponding domain ZSET') do |e|
      "  #{e[:objid]}  domain_id=#{e[:domain_id]}"
    end

    print_category('DRIFT_EXTRA', @stats[:drift_extra],
      'Participations set claims domain ZSET membership that does not exist') do |e|
      "  #{e[:objid]}  claims=#{e[:participations_claims]}"
    end

    print_category('DRIFT_GONE', @stats[:drift_gone],
      'Receipt in domain ZSET but participations set has no record of it') do |e|
      "  #{e[:objid]}  zset=#{e[:zset_key]}  domain=#{e[:domain_id]}"
    end

    if success?
      puts 'RESULT: OK - No inconsistencies detected.'
    else
      total = @stats[:phantoms].size + @stats[:orphans].size +
              @stats[:stale].size + @stats[:missing].size +
              @stats[:drift_extra].size + @stats[:drift_gone].size
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
        Usage: bundle exec ruby scripts/detect_phantom_receipts.rb [OPTIONS]

        Detects inconsistencies across three sources of truth for
        receipt-domain relationships in Redis:

          1. Domain ZSETs    (custom_domain:{id}:receipts)
          2. Domain ID field (receipt:{id}:object HGET domain_id)
          3. Participations  (receipt:{id}:participations SET)

        Categories:
          PHANTOM     Receipt in domain ZSET but domain_id is nil/mismatched
          ORPHAN      Domain ZSET member that doesn't exist as a receipt
          STALE       Receipt domain_id points to a non-existent domain
          MISSING     Receipt has domain_id but not in corresponding ZSET
          DRIFT_EXTRA Participations set claims ZSET membership that doesn't exist
          DRIFT_GONE  Receipt in domain ZSET but participations set missing entry

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

  detector = PhantomReceiptDetector.new(
    redis_url: options[:redis_url],
    redis_db: options[:redis_db],
    max_examples: options[:max_examples],
    json_output: options[:json_output],
  )

  success = detector.run
  exit(success ? 0 : 1)
end
