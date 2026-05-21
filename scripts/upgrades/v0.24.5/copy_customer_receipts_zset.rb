#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb
#
# Copy the per-customer receipt index (formerly metadata) from a v1 Redis
# instance to a v2 Valkey instance, in place — without going through the
# JSONL dump/transform/load pipeline.
#
# Source key pattern (v1, DB 6 by convention):
#   customer:{email}:metadata        — ZSET, score=created, member=receipt_objid
#
# Target writes (v2, DB 0 by convention):
#   customer:{cust_objid}:receipts                — Customer.sorted_set :receipts
#   organization:{org_objid}:receipts             — Receipt.participates_in
#                                                   Onetime::Organization, :receipts,
#                                                   score: :created
#   receipt:{receipt_objid}:participations        — reverse SADD index used by
#                                                   Familia v2 destroy! cleanup
#
# v1 sorted set members are bare receipt identifiers (Familia v1 stored
# `obj.key`, which returns the identifier portion only — see
# apps/api/v1/models/customer.rb#add_metadata in the v0.23 source). Those
# identifiers are reused unchanged as v2 receipt objids (Receipt uses
# Familia::VerifiableIdentifier and the migration preserves the original
# identifier — see scripts/upgrades/v0.24.5/04-receipt/transform.rb).
#
# Idempotency:
#   ZADD with the same (score, member) is a no-op; SADD with the same member
#   is a no-op. Re-running converges to the same target state. A mid-run
#   crash leaves a partial result — re-run to complete.
#
# Lookups:
#   Email → customer objid and customer objid → org objid are read from the
#   JSON files produced by the existing pipeline:
#     data/upgrades/v0.24.5/customer/email_to_objid.json
#     data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json
#   These are required (you can regenerate them by running the pipeline up
#   through 02-organization/generate.rb).
#
# Default is DRY RUN. Pass --execute to write to the target.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb [OPTIONS]
#
# Options:
#   --source-url=URL       v1 Redis URL  (env: SOURCE_REDIS_URL or REDIS_URL)
#   --target-url=URL       v2 Valkey URL (env: TARGET_VALKEY_URL or VALKEY_URL)
#   --customer-lookup=PATH email → cust_objid JSON
#                          (default: data/upgrades/v0.24.5/customer/email_to_objid.json)
#   --org-lookup=PATH      cust_objid → org_objid JSON
#                          (default: data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json)
#   --scan-count=N         SCAN COUNT hint on source (default: 1000)
#   --batch-size=N         Members per pipeline batch (default: 500)
#   --progress-every=N     Print progress every N source keys (default: 500)
#   --execute              Write to target (default: dry-run)
#   --verbose              Per-key logging
#   --help                 Show this help
#
# Examples:
#   # Preview the plan (no writes)
#   ruby scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb \
#     --source-url=redis://v1-redis:6379/6 \
#     --target-url=redis://v2-valkey:6379/0
#
#   # Copy
#   ruby scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb \
#     --source-url=redis://v1-redis:6379/6 \
#     --target-url=redis://v2-valkey:6379/0 \
#     --execute

require 'json'
require 'redis'
require 'uri'

class CustomerReceiptsCopier
  DEFAULT_CUSTOMER_LOOKUP = 'data/upgrades/v0.24.5/customer/email_to_objid.json'
  DEFAULT_ORG_LOOKUP      = 'data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json'
  DEFAULT_SCAN_COUNT      = 1000
  DEFAULT_BATCH_SIZE      = 500
  DEFAULT_PROGRESS_EVERY  = 500

  SOURCE_KEY_PATTERN = 'customer:*:metadata'
  # customer:{email}:metadata — email may contain ':' so capture is greedy.
  SOURCE_KEY_REGEX   = /\Acustomer:(.+):metadata\z/.freeze

  attr_reader :stats

  def initialize(
    source_url:,
    target_url:,
    customer_lookup_path:,
    org_lookup_path:,
    scan_count:     DEFAULT_SCAN_COUNT,
    batch_size:     DEFAULT_BATCH_SIZE,
    progress_every: DEFAULT_PROGRESS_EVERY,
    execute:        false,
    verbose:        false
  )
    @source_url           = source_url
    @target_url           = target_url
    @customer_lookup_path = customer_lookup_path
    @org_lookup_path      = org_lookup_path
    @scan_count           = scan_count
    @batch_size           = batch_size
    @progress_every       = progress_every
    @execute              = execute
    @verbose              = verbose

    @customer_lookup = load_lookup(customer_lookup_path, 'customer')
    @org_lookup      = load_lookup(org_lookup_path, 'org')

    @stats = {
      source_keys_scanned:    0,
      source_keys_empty:      0,
      source_keys_processed:  0,
      members_seen:           0,
      members_copied:         0,
      customer_zadds:         0,
      org_zadds:              0,
      participation_sadds:    0,
      missing_customer_lookup: 0,
      missing_org_lookup:     0,
      missing_emails:         Hash.new(0),
      empty_members:          0,
      errors:                 [],
      start_at:               nil,
      end_at:                 nil,
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
      keys.each { |source_key| process_source_key(source, target, source_key) }
      break if cursor == '0'
    end

    @stats[:end_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    log_summary
    @stats
  ensure
    source&.close
    target&.close
  end

  private

  def connect(url, label:)
    raise ArgumentError, "#{label} URL is required" if url.nil? || url.empty?

    Redis.new(
      url: url,
      connect_timeout: 10,
      read_timeout:    30,
      write_timeout:   10,
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

  def process_source_key(source, target, source_key)
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

    members_with_scores = source.zrange(source_key, 0, -1, with_scores: true)
    if members_with_scores.empty?
      @stats[:source_keys_empty] += 1
      log_verbose("[empty] #{redact_email(email)}: source ZSET has no members")
      return
    end

    org_objid = @org_lookup[cust_objid] # may be nil for customers without an org
    @stats[:missing_org_lookup] += 1 if org_objid.nil?

    customer_target = "customer:#{cust_objid}:receipts"
    org_target      = org_objid ? "organization:#{org_objid}:receipts" : nil

    members_with_scores.each_slice(@batch_size) do |slice|
      copy_slice(target, slice, customer_target: customer_target, org_target: org_target)
    end

    @stats[:source_keys_processed] += 1
    log_verbose("[ok] #{redact_email(email)} → #{cust_objid}: #{members_with_scores.size} members" \
                "#{org_objid ? " + org #{org_objid}" : ''}")
    log_progress if (@stats[:source_keys_scanned] % @progress_every).zero?
  rescue Redis::BaseError => ex
    @stats[:errors] << { key: source_key, error: ex.message }
  end

  def copy_slice(target, slice, customer_target:, org_target:)
    cust_pairs    = []  # [score, member, score, member, ...]
    org_pairs     = []
    participation = []  # [[receipt_objid, org_target], ...]

    slice.each do |member, score|
      @stats[:members_seen] += 1

      receipt_objid = normalize_member(member)
      if receipt_objid.nil? || receipt_objid.empty?
        @stats[:empty_members] += 1
        next
      end

      cust_pairs << score << receipt_objid
      next unless org_target

      org_pairs << score << receipt_objid
      participation << [receipt_objid, org_target]
    end

    return if cust_pairs.empty?

    if @execute
      target.pipelined(exception: false) do |pipe|
        cust_pairs.each_slice(2) { |s, m| pipe.zadd(customer_target, s, m) }
        org_pairs.each_slice(2)  { |s, m| pipe.zadd(org_target, s, m) } if org_target
        participation.each       { |objid, key| pipe.sadd("receipt:#{objid}:participations", key) }
      end
    end

    cust_count = cust_pairs.size / 2
    org_count  = org_pairs.size / 2
    @stats[:customer_zadds]      += cust_count
    @stats[:org_zadds]           += org_count
    @stats[:participation_sadds] += participation.size
    @stats[:members_copied]      += cust_count
  end

  # v1 stored bare identifiers (`obj.key` was the identifier in old Familia).
  # Be defensive: if the prior pipeline ever stored a full `metadata:OBJID`
  # form, strip the prefix.
  def normalize_member(member)
    return nil if member.nil?

    s = member.to_s.strip
    return s.sub(/\Ametadata:/, '') if s.start_with?('metadata:')
    s
  end

  def extract_email(source_key)
    match = source_key.match(SOURCE_KEY_REGEX)
    match ? match[1] : nil
  end

  def log_banner
    puts 'copy_customer_receipts_zset'
    puts "  source:         #{redact_url(@source_url)}"
    puts "  target:         #{redact_url(@target_url)}"
    puts "  customer lookup: #{@customer_lookup_path} (#{@customer_lookup.size} entries)"
    puts "  org lookup:     #{@org_lookup_path} (#{@org_lookup.size} entries)"
    puts "  scan count:     #{@scan_count}"
    puts "  batch size:     #{@batch_size}"
    puts "  mode:           #{@execute ? 'EXECUTE' : 'DRY RUN'}"
    puts
  end

  def log_progress
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @stats[:start_at]
    rate    = elapsed > 0 ? (@stats[:source_keys_scanned] / elapsed).round : 0
    puts "  scanned=#{@stats[:source_keys_scanned]} processed=#{@stats[:source_keys_processed]} " \
         "members=#{@stats[:members_copied]} (#{rate} keys/s)"
    $stdout.flush
  end

  def log_summary
    elapsed = @stats[:end_at] - @stats[:start_at]
    rate    = elapsed > 0 ? (@stats[:source_keys_scanned] / elapsed).round : 0

    puts
    puts '=== Customer Receipts ZSET Copy Summary ==='
    puts "Mode: #{@execute ? 'EXECUTE' : 'DRY RUN'}"
    puts
    puts 'Source keys:'
    puts "  Scanned:   #{@stats[:source_keys_scanned]}"
    puts "  Processed: #{@stats[:source_keys_processed]}"
    puts "  Empty:     #{@stats[:source_keys_empty]}"
    puts
    puts 'Members:'
    puts "  Seen:   #{@stats[:members_seen]}"
    puts "  Copied: #{@stats[:members_copied]}"
    puts "  Empty:  #{@stats[:empty_members]}"
    puts
    puts 'Writes:'
    puts "  customer:{id}:receipts ZADDs:        #{@stats[:customer_zadds]}"
    puts "  organization:{id}:receipts ZADDs:    #{@stats[:org_zadds]}"
    puts "  receipt:{id}:participations SADDs:   #{@stats[:participation_sadds]}"
    puts
    puts 'Lookup misses:'
    puts "  Customer (no email→objid):    #{@stats[:missing_customer_lookup]}"
    puts "  Organization (no objid→org):  #{@stats[:missing_org_lookup]}"

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
    customer_lookup_path: CustomerReceiptsCopier::DEFAULT_CUSTOMER_LOOKUP,
    org_lookup_path:      CustomerReceiptsCopier::DEFAULT_ORG_LOOKUP,
    scan_count:           CustomerReceiptsCopier::DEFAULT_SCAN_COUNT,
    batch_size:           CustomerReceiptsCopier::DEFAULT_BATCH_SIZE,
    progress_every:       CustomerReceiptsCopier::DEFAULT_PROGRESS_EVERY,
    execute:              false,
    verbose:              false,
  }

  args.each do |arg|
    case arg
    when /\A--source-url=(.+)\z/         then options[:source_url]           = Regexp.last_match(1)
    when /\A--target-url=(.+)\z/         then options[:target_url]           = Regexp.last_match(1)
    when /\A--customer-lookup=(.+)\z/    then options[:customer_lookup_path] = Regexp.last_match(1)
    when /\A--org-lookup=(.+)\z/         then options[:org_lookup_path]      = Regexp.last_match(1)
    when /\A--scan-count=(\d+)\z/        then options[:scan_count]           = Regexp.last_match(1).to_i
    when /\A--batch-size=(\d+)\z/        then options[:batch_size]           = Regexp.last_match(1).to_i
    when /\A--progress-every=(\d+)\z/    then options[:progress_every]       = Regexp.last_match(1).to_i
    when '--execute'                     then options[:execute]              = true
    when '--verbose'                     then options[:verbose]              = true
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

  copier = CustomerReceiptsCopier.new(**options)
  result = copier.run
  exit(result[:errors].empty? ? 0 : 1)
end
