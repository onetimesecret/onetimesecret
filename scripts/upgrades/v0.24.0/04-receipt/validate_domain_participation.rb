#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates consistency between receipt domain_id fields and
# custom_domain:{id}:receipts ZSET membership.
#
# Detects three categories of inconsistency:
#
#   PHANTOM  - receipt objid in a domain ZSET, but receipt's domain_id
#              is nil or points to a different domain
#   ORPHAN   - receipt objid in a domain ZSET, but the receipt hash
#              key does not exist in Redis
#   MISSING  - receipt has a domain_id field set, but is not a member
#              of the corresponding custom_domain:{domain_id}:receipts ZSET
#
# Can validate against either:
#   (a) Live Redis (--redis-url), scanning actual keys
#   (b) Migration JSONL files (--indexes-file + --transformed-file)
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/04-receipt/validate_domain_participation.rb [OPTIONS]
#
# Options:
#   --mode=live|jsonl       Validation mode (default: jsonl)
#   --redis-url=URL         Redis URL (required for live mode; env: VALKEY_URL or REDIS_URL)
#   --redis-db=N            Database number for live mode (default: from URL)
#   --indexes-file=FILE     Indexes JSONL (default: data/upgrades/v0.24.0/metadata/receipt_indexes.jsonl)
#   --transformed-file=FILE Transformed JSONL (default: data/upgrades/v0.24.0/metadata/receipt_transformed.jsonl)
#   --max-examples=N        Max examples per category in report (default: 20)
#   --help                  Show this help

require 'json'
require 'set'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class DomainParticipationValidator
  DEFAULT_INDEXES_FILE     = File.join(DEFAULT_DATA_DIR, 'metadata/receipt_indexes.jsonl')
  DEFAULT_TRANSFORMED_FILE = File.join(DEFAULT_DATA_DIR, 'metadata/receipt_transformed.jsonl')

  def initialize(mode:, redis_url: nil, redis_db: nil, indexes_file: nil, transformed_file: nil, max_examples: 20)
    @mode             = mode
    @redis_url        = redis_url
    @redis_db         = redis_db
    @indexes_file     = indexes_file || DEFAULT_INDEXES_FILE
    @transformed_file = transformed_file || DEFAULT_TRANSFORMED_FILE
    @max_examples     = max_examples

    @stats = {
      domains_scanned: 0,
      zset_members_checked: 0,
      receipts_with_domain_id: 0,
      phantoms: [],   # {objid:, zset_domain_id:, actual_domain_id:}
      orphans: [],    # {objid:, zset_domain_id:}
      missing: [],    # {objid:, domain_id:}
      errors: [],
    }
  end

  def run
    case @mode
    when 'live'
      run_live
    when 'jsonl'
      run_jsonl
    else
      raise ArgumentError, "Unknown mode: #{@mode}. Use 'live' or 'jsonl'."
    end

    print_report
    success?
  end

  def success?
    @stats[:phantoms].empty? && @stats[:orphans].empty? && @stats[:missing].empty?
  end

  private

  # ── Live Redis mode ─────────────────────────────────────────────────

  def run_live
    require 'redis'
    require 'uri'

    raise ArgumentError, '--redis-url is required for live mode' unless @redis_url

    uri = URI.parse(@redis_url)
    uri.path = "/#{@redis_db}" if @redis_db
    redis = Redis.new(url: uri.to_s)

    # Phase 1: Scan all custom_domain:*:receipts ZSETs
    scan_domain_zsets_live(redis)

    # Phase 2: Scan all receipt:*:object hashes for domain_id field
    scan_receipt_hashes_live(redis)
  ensure
    redis&.close
  end

  def scan_domain_zsets_live(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'custom_domain:*:receipts', count: 100)

      keys.each do |zset_key|
        domain_id = extract_domain_id_from_key(zset_key)
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
          # Familia v2 stores JSON-encoded values; unwrap if quoted
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

  def scan_receipt_hashes_live(redis)
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'receipt:*:object', count: 200)

      keys.each do |receipt_key|
        domain_id = redis.hget(receipt_key, 'domain_id')
        domain_id = unwrap_json_string(domain_id)
        next if domain_id.nil? || domain_id.empty?

        @stats[:receipts_with_domain_id] += 1

        objid = extract_objid_from_receipt_key(receipt_key)
        next unless objid

        zset_key = "custom_domain:#{domain_id}:receipts"
        score = redis.zscore(zset_key, objid)

        if score.nil?
          @stats[:missing] << { objid: objid, domain_id: domain_id }
        end
      end

      break if cursor == '0'
    end
  end

  # ── JSONL file mode ─────────────────────────────────────────────────

  def run_jsonl
    validate_jsonl_files

    # Build domain ZSET membership from indexes file
    # domain_id -> Set of receipt objids
    domain_zsets = build_domain_zsets_from_indexes

    # Build receipt domain_id map from transformed file
    # objid -> domain_id (or nil)
    receipt_domains, receipt_objids = build_receipt_domain_map

    # Phase 1: Check each ZSET member against receipt data
    domain_zsets.each do |domain_id, member_objids|
      @stats[:domains_scanned] += 1

      member_objids.each do |objid|
        @stats[:zset_members_checked] += 1

        unless receipt_objids.include?(objid)
          @stats[:orphans] << { objid: objid, zset_domain_id: domain_id }
          next
        end

        actual_domain_id = receipt_domains[objid]
        if actual_domain_id.nil? || actual_domain_id != domain_id
          @stats[:phantoms] << {
            objid: objid,
            zset_domain_id: domain_id,
            actual_domain_id: actual_domain_id,
          }
        end
      end
    end

    # Phase 2: Check each receipt with domain_id has a ZSET entry
    receipt_domains.each do |objid, domain_id|
      next if domain_id.nil?

      @stats[:receipts_with_domain_id] += 1
      zset_members = domain_zsets[domain_id]

      if zset_members.nil? || !zset_members.include?(objid)
        @stats[:missing] << { objid: objid, domain_id: domain_id }
      end
    end
  end

  def validate_jsonl_files
    raise ArgumentError, "Indexes file not found: #{@indexes_file}" unless File.exist?(@indexes_file)
    raise ArgumentError, "Transformed file not found: #{@transformed_file}" unless File.exist?(@transformed_file)
  end

  def build_domain_zsets_from_indexes
    domain_zsets = Hash.new { |h, k| h[k] = Set.new }

    File.foreach(@indexes_file) do |line|
      record = JSON.parse(line)

      # Match: ZADD custom_domain:{domain_id}:receipts score objid
      next unless record['command'] == 'ZADD'

      key = record['key']
      next unless key&.match?(/^custom_domain:[^:]+:receipts$/)

      domain_id = extract_domain_id_from_key(key)
      next unless domain_id

      # args: [score, objid]
      objid = record['args'][1]
      domain_zsets[domain_id].add(objid) if objid
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'indexes', error: "JSON parse: #{ex.message}" }
    end

    domain_zsets
  end

  def build_receipt_domain_map
    receipt_domains = {}  # objid -> domain_id (may be nil)
    receipt_objids = Set.new

    File.foreach(@transformed_file) do |line|
      record = JSON.parse(line)
      key = record['key']
      next unless key&.match?(/^receipt:[^:]+:object$/)

      objid = record['objid']
      next unless objid

      receipt_objids.add(objid)
      receipt_domains[objid] = record['domain_id']  # may be nil
    rescue JSON::ParserError => ex
      @stats[:errors] << { file: 'transformed', error: "JSON parse: #{ex.message}" }
    end

    [receipt_domains, receipt_objids]
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def extract_domain_id_from_key(key)
    match = key.match(/^custom_domain:([^:]+):receipts$/)
    match ? match[1] : nil
  end

  def extract_objid_from_receipt_key(key)
    match = key.match(/^receipt:([^:]+):object$/)
    match ? match[1] : nil
  end

  def unwrap_json_string(value)
    return nil if value.nil?
    return nil if value == 'null'

    # Familia v2 JSON-encodes values, so a string "abc" is stored as "\"abc\""
    parsed = JSON.parse(value)
    parsed.is_a?(String) ? parsed : nil
  rescue JSON::ParserError
    # If it doesn't parse as JSON, treat the raw value as the string
    value
  end

  # ── Report ──────────────────────────────────────────────────────────

  def print_report
    puts
    puts '=== Domain Participation Validation ==='
    puts "Mode: #{@mode}"
    puts "Domains scanned: #{@stats[:domains_scanned]}"
    puts "ZSET members checked: #{@stats[:zset_members_checked]}"
    puts "Receipts with domain_id: #{@stats[:receipts_with_domain_id]}"
    puts

    print_category('PHANTOM', @stats[:phantoms],
      'Receipt in domain ZSET but domain_id is nil or mismatched') do |entry|
      domain_info = entry[:actual_domain_id] ? "actual=#{entry[:actual_domain_id]}" : 'actual=nil'
      "  #{entry[:objid]}  zset=#{entry[:zset_domain_id]}  #{domain_info}"
    end

    print_category('ORPHAN', @stats[:orphans],
      'Receipt in domain ZSET but receipt hash does not exist') do |entry|
      "  #{entry[:objid]}  zset=#{entry[:zset_domain_id]}"
    end

    print_category('MISSING', @stats[:missing],
      'Receipt has domain_id but is not in the corresponding ZSET') do |entry|
      "  #{entry[:objid]}  domain_id=#{entry[:domain_id]}"
    end

    if success?
      puts 'OK: No inconsistencies detected.'
    else
      total = @stats[:phantoms].size + @stats[:orphans].size + @stats[:missing].size
      puts "FAIL: #{total} inconsistencies found."
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
    mode: 'jsonl',
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    redis_db: nil,
    indexes_file: DomainParticipationValidator::DEFAULT_INDEXES_FILE,
    transformed_file: DomainParticipationValidator::DEFAULT_TRANSFORMED_FILE,
    max_examples: 20,
  }

  args.each do |arg|
    case arg
    when /^--mode=(.+)$/
      options[:mode] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--redis-db=(\d+)$/
      options[:redis_db] = Regexp.last_match(1).to_i
    when /^--indexes-file=(.+)$/
      options[:indexes_file] = Regexp.last_match(1)
    when /^--transformed-file=(.+)$/
      options[:transformed_file] = Regexp.last_match(1)
    when /^--max-examples=(\d+)$/
      options[:max_examples] = Regexp.last_match(1).to_i
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/04-receipt/validate_domain_participation.rb [OPTIONS]

        Validates consistency between receipt domain_id fields and
        custom_domain:{id}:receipts ZSET membership.

        Detects:
          PHANTOM  Receipt in domain ZSET but domain_id is nil/mismatched
          ORPHAN   Receipt in domain ZSET but receipt hash doesn't exist
          MISSING  Receipt has domain_id but not in corresponding ZSET

        Options:
          --mode=live|jsonl       Validation mode (default: jsonl)
          --redis-url=URL         Redis URL for live mode (env: VALKEY_URL or REDIS_URL)
          --redis-db=N            Override database number for live mode
          --indexes-file=FILE     Indexes JSONL for jsonl mode
                                  (default: data/upgrades/v0.24.0/metadata/receipt_indexes.jsonl)
          --transformed-file=FILE Transformed JSONL for jsonl mode
                                  (default: data/upgrades/v0.24.0/metadata/receipt_transformed.jsonl)
          --max-examples=N        Max examples per category (default: 20)
          --help                  Show this help

        JSONL mode validates migration output files before applying to Redis.
        Live mode validates the actual Redis state post-migration.
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

  validator = DomainParticipationValidator.new(
    mode: options[:mode],
    redis_url: options[:redis_url],
    redis_db: options[:redis_db],
    indexes_file: options[:indexes_file],
    transformed_file: options[:transformed_file],
    max_examples: options[:max_examples],
  )

  success = validator.run
  exit(success ? 0 : 1)
end
