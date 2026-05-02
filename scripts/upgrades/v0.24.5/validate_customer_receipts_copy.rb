#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb
#
# Read-only paired validator for copy_customer_receipts_zset.rb. Verifies
# that the per-customer receipt ZSETs were copied from v1 (source) to v2
# (target) with member-count parity, score parity (sampled), org-mirror
# parity, and reverse-participation indexing.
#
# Why this exists:
#   The copier is additive (ZADD/SADD) and idempotent for matching
#   (score, member) pairs. It does NOT detect score-clobbering: if the
#   target already has the same member at a different score, ZADD
#   overwrites with the source score. This is the highest-severity risk
#   identified in the QA brief. This validator surfaces post-copy state
#   so an operator can catch drift.
#
# Score precision:
#   v1 scores are `OT.now.to_i` integers (seconds-since-epoch). All such
#   values fit exactly in IEEE-754 Float64 (no rounding within ±2^53).
#   Therefore, exact `==` is the correct comparison and we do not need a
#   tolerance window. If you ever encounter fractional scores, switch to
#   ZSCORE returning a string and compare strings.
#
# What it verifies:
#   1. Member-count parity: ZCARD(source) == ZCARD(target customer:{cust}:receipts)
#   2. Score parity (sampled): ZSCORE equal for up to N random members per key
#   3. Org-mirror parity: same sampled members ZSCORE-equal on
#      organization:{org}:receipts (when org_objid resolvable)
#   4. Reverse participation: SISMEMBER receipt:{objid}:participations
#      "organization:{org}:receipts" == 1
#   5. Aggregate ZCARD totals: source vs target customer-side
#
# Read-only on both connections. No writes.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb [OPTIONS]
#
# Options:
#   --source-url=URL       v1 Redis URL  (env: SOURCE_REDIS_URL or REDIS_URL)
#   --target-url=URL       v2 Valkey URL (env: TARGET_VALKEY_URL or VALKEY_URL)
#   --customer-lookup=PATH email → cust_objid JSON
#                          (default: data/upgrades/v0.24.5/customer/email_to_objid.json)
#   --org-lookup=PATH      cust_objid → org_objid JSON
#                          (default: data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json)
#   --scan-count=N         SCAN COUNT hint on source (default: 1000)
#   --sample-size=N        Members sampled per source ZSET (default: 5)
#   --progress-every=N     Print progress every N source keys (default: 500)
#   --max-mismatch-samples=N  Cap on stored mismatch samples (default: 50)
#   --allow-target-superset   Don't fail when target ZCARD > source ZCARD.
#                             Use ONLY if you intentionally pre-seeded targets
#                             from another source. Default: any delta fails.
#   --verbose              Per-key logging
#   --help                 Show this help
#
# Exit codes:
#   0  full parity (or allowed superset, when --allow-target-superset is set)
#   1  any invariant failure or operational error
#
# Examples:
#   ruby scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb \
#     --source-url=redis://v1-redis:6379/6 \
#     --target-url=redis://v2-valkey:6379/0
#
#   # Larger sample for higher confidence on score parity
#   ruby scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb \
#     --source-url=$SRC --target-url=$TGT --sample-size=20

require 'json'
require 'redis'
require 'uri'

class CustomerReceiptsCopyValidator
  DEFAULT_CUSTOMER_LOOKUP    = 'data/upgrades/v0.24.5/customer/email_to_objid.json'
  DEFAULT_ORG_LOOKUP         = 'data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json'
  DEFAULT_SCAN_COUNT         = 1000
  DEFAULT_SAMPLE_SIZE        = 5
  DEFAULT_PROGRESS_EVERY     = 500
  DEFAULT_MAX_MISMATCH_SAMPLES = 50

  SOURCE_KEY_PATTERN = 'customer:*:metadata'
  SOURCE_KEY_REGEX   = /\Acustomer:(.+):metadata\z/.freeze

  attr_reader :stats

  def initialize(
    source_url:,
    target_url:,
    customer_lookup_path:,
    org_lookup_path:,
    scan_count:           DEFAULT_SCAN_COUNT,
    sample_size:          DEFAULT_SAMPLE_SIZE,
    progress_every:       DEFAULT_PROGRESS_EVERY,
    max_mismatch_samples: DEFAULT_MAX_MISMATCH_SAMPLES,
    allow_target_superset: false,
    verbose:              false
  )
    @source_url           = source_url
    @target_url           = target_url
    @customer_lookup_path = customer_lookup_path
    @org_lookup_path      = org_lookup_path
    @scan_count           = scan_count
    @sample_size          = sample_size
    @progress_every       = progress_every
    @max_mismatch_samples = max_mismatch_samples
    @allow_target_superset = allow_target_superset
    @verbose              = verbose

    @customer_lookup = load_lookup(customer_lookup_path, 'customer')
    @org_lookup      = load_lookup(org_lookup_path, 'org')

    @stats = {
      source_keys_scanned:     0,
      source_keys_empty:       0,
      source_keys_compared:    0,

      missing_customer_lookup: 0,
      missing_org_lookup:      0,
      missing_emails:          Hash.new(0),

      # Aggregate counts
      source_zcard_total:      0,
      target_customer_zcard_total: 0,

      # Member-count parity
      zcard_mismatches:        0,
      zcard_mismatch_samples:  [],
      target_superset_keys:    0,  # target ZCARD > source ZCARD

      # Score parity (customer)
      members_sampled:         0,
      score_mismatches:        0,
      score_mismatch_samples:  [],
      target_missing_member:   0,  # member present on source, absent on target
      target_missing_samples:  [],

      # Org mirror
      org_score_mismatches:    0,
      org_score_mismatch_samples: [],
      org_missing_member:      0,
      org_missing_samples:     [],

      # Reverse participation
      participation_missing:   0,
      participation_missing_samples: [],

      errors:                  [],
      start_at:                nil,
      end_at:                  nil,
    }
  end

  def run
    @stats[:start_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    source = connect(@source_url, label: 'source')
    target = connect(@target_url, label: 'target')

    begin
      source.ping
    rescue Redis::CannotConnectError => ex
      raise Redis::CannotConnectError, "Cannot reach source: #{ex.message}"
    end

    begin
      target.ping
    rescue Redis::CannotConnectError => ex
      raise Redis::CannotConnectError, "Cannot reach target: #{ex.message}"
    end

    log_banner

    cursor = '0'
    loop do
      cursor, keys = source.scan(cursor, match: SOURCE_KEY_PATTERN, count: @scan_count)
      keys.each { |source_key| validate_source_key(source, target, source_key) }
      break if cursor == '0'
    end

    @stats[:end_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    log_summary
    @stats
  ensure
    source&.close
    target&.close
  end

  def passed?
    return false unless @stats[:errors].empty?
    return false if @stats[:score_mismatches].positive?
    return false if @stats[:org_score_mismatches].positive?
    return false if @stats[:target_missing_member].positive?
    return false if @stats[:org_missing_member].positive?
    return false if @stats[:participation_missing].positive?

    if @stats[:zcard_mismatches].positive?
      # zcard_mismatches counts strict inequality. If --allow-target-superset
      # is set, supersets do not count as failures.
      return false unless @allow_target_superset
      return false if (@stats[:zcard_mismatches] - @stats[:target_superset_keys]).positive?
    end

    true
  end

  private

  def connect(url, label:)
    raise ArgumentError, "#{label} URL is required" if url.nil? || url.empty?

    Redis.new(
      url: url,
      connect_timeout:    10,
      read_timeout:       30,
      write_timeout:      10,
      reconnect_attempts: [0.5, 1.0, 2.0],
    )
  rescue URI::InvalidURIError => ex
    raise ArgumentError, "Invalid #{label} URL: #{ex.message}"
  end

  def load_lookup(path, name)
    raise ArgumentError, "#{name} lookup path required" if path.nil? || path.empty?
    raise ArgumentError, "#{name} lookup not found: #{path}" unless File.exist?(path)

    data = JSON.parse(File.read(path))
    raise ArgumentError, "#{name} lookup must be a JSON object" unless data.is_a?(Hash)

    puts "Loaded #{data.size} #{name} entries from #{path}"
    data
  end

  def validate_source_key(source, target, source_key)
    @stats[:source_keys_scanned] += 1

    email = extract_email(source_key)
    unless email
      @stats[:errors] << { key: source_key, error: 'unparseable source key' }
      return
    end

    cust_objid = @customer_lookup[email]
    unless cust_objid
      @stats[:missing_customer_lookup] += 1
      @stats[:missing_emails][email]   += 1
      log_verbose("[skip] #{redact_email(email)}: no customer objid in lookup")
      return
    end

    customer_target = "customer:#{cust_objid}:receipts"
    org_objid       = @org_lookup[cust_objid]
    org_target      = org_objid ? "organization:#{org_objid}:receipts" : nil
    @stats[:missing_org_lookup] += 1 if org_objid.nil?

    source_zcard = source.zcard(source_key)
    if source_zcard.zero?
      @stats[:source_keys_empty] += 1
      log_verbose("[empty] #{redact_email(email)}: source ZSET has no members")
      return
    end

    target_zcard = target.zcard(customer_target)

    @stats[:source_zcard_total]          += source_zcard
    @stats[:target_customer_zcard_total] += target_zcard

    if source_zcard != target_zcard
      @stats[:zcard_mismatches] += 1
      @stats[:target_superset_keys] += 1 if target_zcard > source_zcard
      record_sample(@stats[:zcard_mismatch_samples], {
        email:        redact_email(email),
        cust_objid:   cust_objid,
        source_zcard: source_zcard,
        target_zcard: target_zcard,
        delta:        target_zcard - source_zcard,
      })
    end

    members = sample_members(source, source_key, source_zcard)
    members.each do |member|
      verify_member_scores(source, target, source_key, customer_target, org_target,
                           email, cust_objid, org_objid, member)
    end

    @stats[:source_keys_compared] += 1
    log_verbose("[ok] #{redact_email(email)} → #{cust_objid}: src=#{source_zcard} tgt=#{target_zcard}" \
                "#{org_objid ? " org=#{org_objid}" : ''}")
    log_progress if (@stats[:source_keys_scanned] % @progress_every).zero?
  rescue Redis::BaseError => ex
    @stats[:errors] << { key: source_key, error: ex.message }
  end

  # Random sample without replacement using ZRANDMEMBER when available;
  # falls back to ZRANGE + Array#sample for older servers.
  def sample_members(source, source_key, source_zcard)
    n = [@sample_size, source_zcard].min
    return [] if n.zero?

    begin
      result = source.zrandmember(source_key, n)
      return Array(result) unless result.nil? || (result.respond_to?(:empty?) && result.empty?)
    rescue Redis::CommandError, NoMethodError
      # ZRANDMEMBER unsupported (Redis < 6.2); fall through.
    end

    all = source.zrange(source_key, 0, -1)
    all.sample(n)
  end

  def verify_member_scores(source, target, source_key, customer_target, org_target,
                           email, cust_objid, org_objid, member)
    @stats[:members_sampled] += 1

    source_score = source.zscore(source_key, member)
    target_score = target.zscore(customer_target, member)

    if target_score.nil?
      @stats[:target_missing_member] += 1
      record_sample(@stats[:target_missing_samples], {
        email:        redact_email(email),
        cust_objid:   cust_objid,
        member:       member,
        source_score: source_score,
      })
    elsif !scores_equal?(source_score, target_score)
      @stats[:score_mismatches] += 1
      record_sample(@stats[:score_mismatch_samples], {
        email:        redact_email(email),
        cust_objid:   cust_objid,
        member:       member,
        source_score: source_score,
        target_score: target_score,
      })
    end

    return unless org_target

    org_score = target.zscore(org_target, member)
    if org_score.nil?
      @stats[:org_missing_member] += 1
      record_sample(@stats[:org_missing_samples], {
        email:        redact_email(email),
        cust_objid:   cust_objid,
        org_objid:    org_objid,
        member:       member,
        source_score: source_score,
      })
    elsif !scores_equal?(source_score, org_score)
      @stats[:org_score_mismatches] += 1
      record_sample(@stats[:org_score_mismatch_samples], {
        email:        redact_email(email),
        cust_objid:   cust_objid,
        org_objid:    org_objid,
        member:       member,
        source_score: source_score,
        org_score:    org_score,
      })
    end

    # Reverse participation: SISMEMBER receipt:{objid}:participations org_target
    membership = target.sismember("receipt:#{member}:participations", org_target)
    return if membership

    @stats[:participation_missing] += 1
    record_sample(@stats[:participation_missing_samples], {
      email:      redact_email(email),
      cust_objid: cust_objid,
      org_objid:  org_objid,
      member:     member,
    })
  end

  # OT.now.to_i integers fit exactly in Float64; equality is correct.
  # nil-safe: nil never equals a present score.
  def scores_equal?(a, b)
    return false if a.nil? || b.nil?
    a == b
  end

  def record_sample(bucket, entry)
    return if bucket.size >= @max_mismatch_samples
    bucket << entry
  end

  def extract_email(source_key)
    match = source_key.match(SOURCE_KEY_REGEX)
    match ? match[1] : nil
  end

  def log_banner
    puts 'validate_customer_receipts_copy (read-only)'
    puts "  source:           #{redact_url(@source_url)}"
    puts "  target:           #{redact_url(@target_url)}"
    puts "  customer lookup:  #{@customer_lookup_path} (#{@customer_lookup.size} entries)"
    puts "  org lookup:       #{@org_lookup_path} (#{@org_lookup.size} entries)"
    puts "  scan count:       #{@scan_count}"
    puts "  sample size:      #{@sample_size}"
    puts "  superset allowed: #{@allow_target_superset}"
    puts
  end

  def log_progress
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @stats[:start_at]
    rate    = elapsed > 0 ? (@stats[:source_keys_scanned] / elapsed).round : 0
    puts "  scanned=#{@stats[:source_keys_scanned]} compared=#{@stats[:source_keys_compared]} " \
         "sampled=#{@stats[:members_sampled]} (#{rate} keys/s)"
    $stdout.flush
  end

  def log_summary
    elapsed = @stats[:end_at] - @stats[:start_at]
    rate    = elapsed > 0 ? (@stats[:source_keys_scanned] / elapsed).round : 0

    puts
    puts '=== Customer Receipts Copy Validation Summary ==='
    puts
    puts 'Source keys:'
    puts "  Scanned:  #{@stats[:source_keys_scanned]}"
    puts "  Compared: #{@stats[:source_keys_compared]}"
    puts "  Empty:    #{@stats[:source_keys_empty]}"
    puts
    puts 'Lookup misses:'
    puts "  Customer (no email→objid):    #{@stats[:missing_customer_lookup]}"
    puts "  Organization (no objid→org):  #{@stats[:missing_org_lookup]}"
    puts
    puts 'Aggregate ZCARDs (compared keys only):'
    puts "  Source customer:*:metadata total:    #{@stats[:source_zcard_total]}"
    puts "  Target customer:{id}:receipts total: #{@stats[:target_customer_zcard_total]}"
    diff = @stats[:target_customer_zcard_total] - @stats[:source_zcard_total]
    puts "  Diff (target - source):              #{diff}"
    puts
    puts 'Member-count parity (per-key ZCARD):'
    puts "  Mismatches:           #{@stats[:zcard_mismatches]}"
    puts "  Of which superset:    #{@stats[:target_superset_keys]} (target > source)"
    print_sample(@stats[:zcard_mismatch_samples], 'ZCARD mismatch samples')
    puts
    puts 'Score parity (sampled, customer:{id}:receipts):'
    puts "  Members sampled:       #{@stats[:members_sampled]}"
    puts "  Score mismatches:      #{@stats[:score_mismatches]}"
    puts "  Member missing target: #{@stats[:target_missing_member]}"
    print_sample(@stats[:score_mismatch_samples], 'Score mismatch samples')
    print_sample(@stats[:target_missing_samples], 'Target-missing-member samples')
    puts
    puts 'Org mirror parity (sampled, organization:{id}:receipts):'
    puts "  Score mismatches:      #{@stats[:org_score_mismatches]}"
    puts "  Member missing target: #{@stats[:org_missing_member]}"
    print_sample(@stats[:org_score_mismatch_samples], 'Org score mismatch samples')
    print_sample(@stats[:org_missing_samples], 'Org-missing-member samples')
    puts
    puts 'Reverse participation (receipt:{id}:participations):'
    puts "  Missing entries:       #{@stats[:participation_missing]}"
    print_sample(@stats[:participation_missing_samples], 'Participation-missing samples')

    if @stats[:missing_emails].any?
      sample = @stats[:missing_emails].sort_by { |_, count| -count }.first(10)
      puts
      puts "Top missing emails (#{@stats[:missing_emails].size} unique):"
      sample.each { |email, count| puts "  #{redact_email(email)}: #{count}" }
    end

    if @stats[:errors].any?
      puts
      puts "Errors (#{@stats[:errors].size}):"
      @stats[:errors].first(10).each { |e| puts "  #{e[:key]}: #{e[:error]}" }
      puts "  ... and #{@stats[:errors].size - 10} more" if @stats[:errors].size > 10
    end

    puts
    puts "Elapsed: #{elapsed.round(1)}s (#{rate} keys/s)"
    puts
    puts(passed? ? 'RESULT: PASS' : 'RESULT: FAIL')
  end

  def print_sample(bucket, label)
    return if bucket.empty?
    puts "  #{label} (showing #{bucket.size}, cap #{@max_mismatch_samples}):"
    bucket.each { |entry| puts "    #{entry.inspect}" }
  end

  def log_verbose(line)
    return unless @verbose
    puts line
    $stdout.flush
  end

  def redact_url(url)
    url.to_s.sub(/:[^:@\/]+@/, ':***@')
  end

  def redact_email(email)
    return '***' unless email.is_a?(String) && email.include?('@')
    local, domain = email.split('@', 2)
    "#{local[0..2]}***@#{domain.sub(/\A[^.]+/, '***')}"
  end
end

def parse_args(args)
  options = {
    source_url:           ENV['SOURCE_REDIS_URL']  || ENV.fetch('REDIS_URL', nil),
    target_url:           ENV['TARGET_VALKEY_URL'] || ENV.fetch('VALKEY_URL', nil),
    customer_lookup_path: CustomerReceiptsCopyValidator::DEFAULT_CUSTOMER_LOOKUP,
    org_lookup_path:      CustomerReceiptsCopyValidator::DEFAULT_ORG_LOOKUP,
    scan_count:           CustomerReceiptsCopyValidator::DEFAULT_SCAN_COUNT,
    sample_size:          CustomerReceiptsCopyValidator::DEFAULT_SAMPLE_SIZE,
    progress_every:       CustomerReceiptsCopyValidator::DEFAULT_PROGRESS_EVERY,
    max_mismatch_samples: CustomerReceiptsCopyValidator::DEFAULT_MAX_MISMATCH_SAMPLES,
    allow_target_superset: false,
    verbose:              false,
  }

  args.each do |arg|
    case arg
    when /\A--source-url=(.+)\z/            then options[:source_url]            = Regexp.last_match(1)
    when /\A--target-url=(.+)\z/            then options[:target_url]            = Regexp.last_match(1)
    when /\A--customer-lookup=(.+)\z/       then options[:customer_lookup_path]  = Regexp.last_match(1)
    when /\A--org-lookup=(.+)\z/            then options[:org_lookup_path]       = Regexp.last_match(1)
    when /\A--scan-count=(\d+)\z/           then options[:scan_count]            = Regexp.last_match(1).to_i
    when /\A--sample-size=(\d+)\z/          then options[:sample_size]           = Regexp.last_match(1).to_i
    when /\A--progress-every=(\d+)\z/       then options[:progress_every]        = Regexp.last_match(1).to_i
    when /\A--max-mismatch-samples=(\d+)\z/ then options[:max_mismatch_samples]  = Regexp.last_match(1).to_i
    when '--allow-target-superset'          then options[:allow_target_superset] = true
    when '--verbose'                        then options[:verbose]               = true
    when '--help', '-h'
      puts File.read(__FILE__).each_line.drop(2).take_while { |l| l.start_with?('#', "\n") }.join
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  missing = []
  missing << '--source-url (or SOURCE_REDIS_URL / REDIS_URL)' if options[:source_url].nil? || options[:source_url].empty?
  missing << '--target-url (or TARGET_VALKEY_URL / VALKEY_URL)' if options[:target_url].nil? || options[:target_url].empty?
  unless missing.empty?
    warn "Missing required: #{missing.join(', ')}"
    warn 'Use --help for usage.'
    exit 1
  end

  validator = CustomerReceiptsCopyValidator.new(**options)
  validator.run
  exit(validator.passed? ? 0 : 1)
end
