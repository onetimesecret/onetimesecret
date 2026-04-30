#!/usr/bin/env ruby
# frozen_string_literal: true

# Post-migration end-to-end validator for the v0.24.5 OneTimeSecret upgrade.
#
# Runs AFTER load_keys.rb has restored transformed records and indexes into the
# live Valkey/Redis dataset. Verifies the integrity of the v2 keyspace so an
# operator can sign off (or know what's broken) in a single pass.
#
# DESIGN NOTES
#
# - The load-bearing check is the customer -> organization -> membership ->
#   org_customer_lookup chain. PR #3041 fixed a bug where the loader silently
#   produced organizations without their owner OrganizationMembership records,
#   leaving find_by_org_customer broken for every migrated owner. This
#   validator's primary job is to prove that chain is intact for a sample.
#
# - The customer_objid -> org_objid mapping is read from the JSONL artifact
#   produced by 02-organization/generate.rb:
#     data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json
#   (NOTE: PR review brief referred to this as customer_org_map.json - the
#   actual filename is customer_objid_to_org_objid.json.)
#   If absent, we fall back to scanning organization:objid_lookup HKEYS and
#   reading owner_id off each org hash. That fallback is O(orgs) per check
#   and slow on 400k records - use --sample=N to bound it.
#
# - For the custom-domain exclusivity and owner-objects-exist checks we
#   delegate to the existing sibling validators rather than reimplementing
#   their logic. Their exit codes are rolled up into our own.
#
# - Familia v2 stores HashKey/HSET-index values JSON-encoded (e.g. an objid
#   like "01h7..." is stored as "\"01h7...\""). All lookups in this script
#   normalize HGET results through JSON.parse before comparing.
#
# Usage:
#   ruby scripts/upgrades/v0.24.5/validate_post_migration.rb [OPTIONS]
#
# Options:
#   --valkey-url=URL    Valkey/Redis URL (also --redis-url; env: VALKEY_URL or REDIS_URL)
#   --sample=N          Customers/orgs to spot-check (default 100; 0 = all)
#   --model=NAME        Restrict to one cohort: customer, organization,
#                       membership (alias org_membership), customdomain,
#                       receipt, secret
#   --data-dir=DIR      Migration artifact directory (default: data/upgrades/v0.24.5)
#   --verbose           Print every failing case, not just totals
#   --help              Show this help
#
# Exit codes:
#   0  All checks passed
#   1  One or more validation checks failed
#   2  Connection error or unrecoverable hard error

require 'json'
require 'redis'
require 'rbconfig'
require 'set'
require 'uri'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.5'
SAMPLE_FAILURES_CAP = 50         # max failing cases retained per check
SAMPLE_FAILURES_PRINT = 5        # printed by default; --verbose prints all

VALID_MODELS = %w[customer organization membership org_membership customdomain receipt secret].freeze

COHORTS = [
  { label: 'customer',        scan: 'customer:*:object' },
  { label: 'organization',    scan: 'organization:*:object' },
  { label: 'org_membership',  scan: 'org_membership:*:object' },
  { label: 'customdomain',    scan: 'custom_domain:*:object' },
  { label: 'receipt',         scan: 'receipt:*:object' },
  { label: 'secret',          scan: 'secret:*:object' },
].freeze

# Familia HashKey/HSET-index values are JSON-encoded ("\"objid\"").
# Sorted-set members are raw. This handles both transparently.
def normalize_indexed_value(raw)
  return nil if raw.nil?
  return raw unless raw.is_a?(String)
  return raw if raw.empty?

  JSON.parse(raw)
rescue JSON::ParserError
  raw
end

class CheckResult
  STATUS = %i[pass fail skip].freeze

  attr_reader :name, :status, :sample_size, :fail_count, :failures, :note

  def initialize(name)
    @name        = name
    @status      = :pass
    @sample_size = 0
    @fail_count  = 0
    @failures    = []
    @note        = nil
  end

  def mark_pass(sample_size)
    @sample_size = sample_size
    @status = :pass
  end

  def mark_fail(sample_size, fail_count, failures)
    @sample_size = sample_size
    @fail_count  = fail_count
    @failures    = failures
    @status      = :fail
  end

  def mark_skip(note)
    @note   = note
    @status = :skip
  end

  def passed?; @status == :pass; end
  def skipped?; @status == :skip; end
end

class PostMigrationValidator
  def initialize(valkey_url:, sample:, model:, data_dir:, verbose:)
    @valkey_url = valkey_url
    @sample     = sample
    @model      = model
    @data_dir   = data_dir
    @verbose    = verbose

    @redis = nil
    @cohort_counts = {}
    @check_results = []
  end

  def run
    connect_redis

    cohort_population

    selected = filter_for_model

    selected.each do |check_id|
      result = case check_id
               when :customer_chain
                 check_customer_to_membership_chain
               when :org_indexes
                 check_organization_indexes
               when :domain_exclusivity
                 check_via_external('Custom domain -> org exclusivity', 'validate_domain_org_exclusivity.rb')
               when :owner_objects
                 check_via_external('Owner customer objects exist',     'validate_owners_objects_exist.rb')
               end
      @check_results << result if result
    end

    print_summary
    exit_code
  ensure
    @redis&.close
  end

  private

  def connect_redis
    uri = URI.parse(@valkey_url)
    uri.path = '/0'
    @redis = Redis.new(url: uri.to_s)
    @redis.ping
  rescue Redis::CannotConnectError, URI::InvalidURIError, Redis::CommandError => ex
    warn "ERROR: Cannot connect to Valkey/Redis: #{ex.class}: #{ex.message}"
    exit 2
  end

  def filter_for_model
    return %i[customer_chain org_indexes domain_exclusivity owner_objects] unless @model

    case @model
    when 'customer'                       then %i[customer_chain]
    when 'organization'                   then %i[org_indexes owner_objects]
    when 'membership', 'org_membership'   then %i[customer_chain]
    when 'customdomain'                   then %i[domain_exclusivity]
    when 'receipt', 'secret'              then []
    end
  end

  # ------------------------------------------------------------------
  # Cohort population
  # ------------------------------------------------------------------

  def cohort_population
    COHORTS.each do |cohort|
      @cohort_counts[cohort[:label]] = scan_count(cohort[:scan])
    end
  end

  def scan_count(pattern)
    count = 0
    cursor = '0'
    loop do
      cursor, keys = @redis.scan(cursor, match: pattern, count: 1000)
      count += keys.size
      break if cursor == '0'
    end
    count
  end

  # ------------------------------------------------------------------
  # Check 1: customer -> org -> membership -> lookup chain
  # ------------------------------------------------------------------

  def check_customer_to_membership_chain
    result = CheckResult.new('Customer -> Org -> Membership chain')

    customer_keys = sample_keys('customer:*:object')
    if customer_keys.empty?
      result.mark_skip('no customer records found')
      return result
    end

    customer_to_org = load_customer_to_org_map

    failures = []
    fail_count = 0

    customer_keys.each do |customer_key|
      customer_objid = customer_key.split(':')[1]

      # Resolve org_objid via map artifact, with fallback scan if absent.
      org_objid = customer_to_org[customer_objid]
      org_objid ||= fallback_org_lookup(customer_objid)

      unless org_objid
        fail_count += 1
        failures << { stage: 'customer->org', customer_objid: customer_objid, reason: 'no org_objid found via map or fallback' } if failures.size < SAMPLE_FAILURES_CAP
        next
      end

      composite_field = "#{org_objid}:#{customer_objid}"
      raw = @redis.hget('org_membership:org_customer_lookup', composite_field)
      membership_objid = normalize_indexed_value(raw)

      unless membership_objid
        fail_count += 1
        if failures.size < SAMPLE_FAILURES_CAP
          failures << {
            stage: 'lookup_hget',
            customer_objid: customer_objid,
            org_objid: org_objid,
            composite_field: composite_field,
            raw_value: raw.inspect,
            reason: 'org_membership:org_customer_lookup HGET returned nil',
          }
        end
        next
      end

      # The membership Redis key is org_membership:{membership_objid}:object
      # where membership_objid is the composite path
      # "organization:{org}:customer:{cust}:org_membership".
      membership_key = "org_membership:#{membership_objid}:object"
      unless @redis.exists(membership_key) > 0
        fail_count += 1
        if failures.size < SAMPLE_FAILURES_CAP
          failures << {
            stage: 'membership_object',
            customer_objid: customer_objid,
            org_objid: org_objid,
            membership_objid: membership_objid,
            membership_key: membership_key,
            reason: 'membership object key does not exist',
          }
        end
        next
      end

      # Verify the membership hash's stored ids match. Values are JSON-encoded.
      stored_org  = normalize_indexed_value(@redis.hget(membership_key, 'organization_objid'))
      stored_cust = normalize_indexed_value(@redis.hget(membership_key, 'customer_objid'))

      if stored_org != org_objid || stored_cust != customer_objid
        fail_count += 1
        if failures.size < SAMPLE_FAILURES_CAP
          failures << {
            stage: 'membership_field_mismatch',
            customer_objid: customer_objid,
            org_objid: org_objid,
            membership_objid: membership_objid,
            stored_organization_objid: stored_org,
            stored_customer_objid: stored_cust,
            reason: 'membership object fields do not match expected ids',
          }
        end
      end
    end

    if fail_count.zero?
      result.mark_pass(customer_keys.size)
    else
      result.mark_fail(customer_keys.size, fail_count, failures)
    end
    result
  end

  def load_customer_to_org_map
    map_file = File.join(@data_dir, 'organization', 'customer_objid_to_org_objid.json')
    return {} unless File.exist?(map_file)

    JSON.parse(File.read(map_file))
  rescue JSON::ParserError, Errno::ENOENT
    {}
  end

  # Slow-path: scan organization:objid_lookup, read each org hash's owner_id,
  # build a reverse {customer_objid => org_objid}. Cached per run on first call.
  def fallback_org_lookup(customer_objid)
    @fallback_index ||= build_fallback_index
    @fallback_index[customer_objid]
  end

  def build_fallback_index
    warn 'NOTE: customer_objid_to_org_objid.json not found - falling back to ' \
         'scanning organization:objid_lookup. This is O(orgs) and slow on large datasets.'
    index = {}
    org_objids = @redis.hkeys('organization:objid_lookup')
    org_objids.each do |org_objid|
      owner = normalize_indexed_value(@redis.hget("organization:#{org_objid}:object", 'owner_id'))
      index[owner] = org_objid if owner
    end
    index
  end

  # ------------------------------------------------------------------
  # Check 2: organization indexes resolve back
  # ------------------------------------------------------------------

  def check_organization_indexes
    result = CheckResult.new('Organization lookup indexes')

    org_keys = sample_keys('organization:*:object')
    if org_keys.empty?
      result.mark_skip('no organization records found')
      return result
    end

    failures = []
    fail_count = 0

    org_keys.each do |org_key|
      org_objid = org_key.split(':')[1]

      org_fields = @redis.hgetall(org_key)
      org_extid     = normalize_indexed_value(org_fields['extid'])
      contact_email = normalize_indexed_value(org_fields['contact_email'])
      billing_email = normalize_indexed_value(org_fields['billing_email'])

      checks = [
        ['organization:objid_lookup', org_objid,    org_objid, true],
        ['organization:extid_lookup', org_extid,    org_objid, true],
        ['organization:contact_email_index', contact_email, org_objid, false],
        ['organization:billing_email_index', billing_email, org_objid, false],
      ]

      checks.each do |hkey, field, expected, required|
        if field.nil? || field.to_s.empty?
          if required
            fail_count += 1
            if failures.size < SAMPLE_FAILURES_CAP
              failures << { stage: hkey, org_objid: org_objid, reason: 'lookup field missing on org hash' }
            end
          end
          next
        end

        raw = @redis.hget(hkey, field.to_s)
        actual = normalize_indexed_value(raw)
        next if actual == expected

        fail_count += 1
        next unless failures.size < SAMPLE_FAILURES_CAP
        failures << {
          stage: hkey,
          org_objid: org_objid,
          field: field,
          expected: expected,
          actual: actual,
          raw_value: raw.inspect,
        }
      end
    end

    if fail_count.zero?
      result.mark_pass(org_keys.size)
    else
      result.mark_fail(org_keys.size, fail_count, failures)
    end
    result
  end

  # ------------------------------------------------------------------
  # External validators
  # ------------------------------------------------------------------

  def check_via_external(name, script_basename)
    result = CheckResult.new(name)
    script_path = File.expand_path("../#{script_basename}", __FILE__)

    unless File.exist?(script_path)
      result.mark_skip("delegated validator missing: #{script_path}")
      return result
    end

    cmd = [RbConfig.ruby, script_path, "--redis-url=#{@valkey_url}"]
    puts "  -> delegating to #{script_basename}..."
    success = system(*cmd)

    if success
      result.mark_pass(0)
    else
      child_exit = $?&.exitstatus || 1
      if child_exit == 2
        warn "WARN: #{script_basename} exited 2 (hard error) - propagating"
      end
      result.mark_fail(0, 0, [{ stage: 'delegated', script: script_basename, exit_code: child_exit }])
    end
    result
  end

  # ------------------------------------------------------------------
  # Sampling
  # ------------------------------------------------------------------

  def sample_keys(pattern)
    keys = []
    cursor = '0'
    loop do
      cursor, batch = @redis.scan(cursor, match: pattern, count: 1000)
      keys.concat(batch)
      break if cursor == '0'
    end

    return keys if @sample.zero? || keys.size <= @sample

    keys.sample(@sample)
  end

  # ------------------------------------------------------------------
  # Reporting
  # ------------------------------------------------------------------

  def print_summary
    puts
    puts '=' * 60
    puts 'POST-MIGRATION VALIDATION SUMMARY'
    puts '=' * 60
    puts
    puts 'Cohort populations:'
    label_w = COHORTS.map { |c| c[:label].size }.max
    COHORTS.each do |cohort|
      printf "  %-#{label_w + 1}s %s\n", "#{cohort[:label]}:", format_int(@cohort_counts[cohort[:label]])
    end
    puts

    puts 'Checks:'
    @check_results.each { |r| print_check(r) }
    puts

    failed = @check_results.count { |r| r.status == :fail }
    skipped = @check_results.count(&:skipped?)
    total = @check_results.size

    if failed.zero?
      puts "Result: #{total - skipped} checks passed, #{skipped} skipped, 0 failed."
    else
      puts "Result: #{failed} of #{total} checks failed (#{skipped} skipped)."
    end
  end

  def print_check(result)
    case result.status
    when :pass
      printf "  [PASS] %-44s (sample=%d, fail=0)\n", result.name, result.sample_size
    when :skip
      printf "  [SKIP] %-44s (%s)\n", result.name, result.note
    when :fail
      printf "  [FAIL] %-44s (sample=%d, fail=%d)\n", result.name, result.sample_size, result.fail_count
      to_print = @verbose ? result.failures : result.failures.first(SAMPLE_FAILURES_PRINT)
      to_print.each do |f|
        puts "    - #{f.inspect}"
      end
      if !@verbose && result.failures.size > SAMPLE_FAILURES_PRINT
        puts "    ... and #{result.failures.size - SAMPLE_FAILURES_PRINT} more (use --verbose to see all)"
      end
    end
  end

  def format_int(n)
    return '0' if n.nil?

    n.to_s.reverse.scan(/.{1,3}/).join(',').reverse
  end

  def exit_code
    # Promote to exit 2 if any delegated validator hit a hard error (its
    # failures carry exit_code: 2 per check_via_external). Otherwise exit 1
    # for soft validation failures, 0 clean.
    hard = @check_results.any? do |r|
      r.status == :fail && r.failures.any? { |f| f.is_a?(Hash) && f[:exit_code] == 2 }
    end
    return 2 if hard

    @check_results.any? { |r| r.status == :fail } ? 1 : 0
  end
end

def parse_args(args)
  options = {
    valkey_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
    sample: 100,
    model: nil,
    data_dir: DEFAULT_DATA_DIR,
    verbose: false,
  }

  args.each do |arg|
    case arg
    when /^--valkey-url=(.+)$/, /^--redis-url=(.+)$/
      options[:valkey_url] = Regexp.last_match(1)
    when /^--sample=(\d+)$/
      options[:sample] = Regexp.last_match(1).to_i
    when /^--model=(.+)$/
      m = Regexp.last_match(1)
      unless VALID_MODELS.include?(m)
        warn "Invalid --model=#{m} (valid: #{VALID_MODELS.join(', ')})"
        exit 1
      end
      options[:model] = m
    when /^--data-dir=(.+)$/
      options[:data_dir] = Regexp.last_match(1)
    when '--verbose'
      options[:verbose] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby #{__FILE__} [OPTIONS]

        Post-migration end-to-end validator for the v0.24.5 OneTimeSecret upgrade.
        Verifies the customer -> organization -> membership -> lookup-index chain
        and other key invariants in the live Valkey/Redis dataset after load_keys.rb.

        Options:
          --valkey-url=URL    Valkey/Redis URL (also --redis-url; env: VALKEY_URL or REDIS_URL)
          --sample=N          Customers/orgs to spot-check (default 100; 0 = all)
          --model=NAME        Restrict to one cohort:
                                customer, organization,
                                membership (alias org_membership),
                                customdomain, receipt, secret
          --data-dir=DIR      Migration artifact directory (default: #{DEFAULT_DATA_DIR})
          --verbose           Print every failing case, not just the first #{SAMPLE_FAILURES_PRINT}
          --help              Show this help

        Exit codes:
          0  All checks passed
          1  One or more validation checks failed
          2  Connection error or unrecoverable hard error

        Checks:
          1. Cohort population counts (customer/org/membership/customdomain/receipt/secret)
          2. Customer -> Organization -> Membership chain (sample)
          3. Organization lookup indexes resolve (sample)
          4. Custom domain -> org exclusivity (delegates to validate_domain_org_exclusivity.rb)
          5. Owner customer objects exist (delegates to validate_owners_objects_exist.rb)
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

  validator = PostMigrationValidator.new(
    valkey_url: options[:valkey_url],
    sample: options[:sample],
    model: options[:model],
    data_dir: options[:data_dir],
    verbose: options[:verbose],
  )

  exit validator.run
end
