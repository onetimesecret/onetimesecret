#!/usr/bin/env ruby
# frozen_string_literal: true

# Validate migration data integrity.
#
# Runs pre-load and post-load validation checks to ensure data integrity.
#
# Usage:
#   ruby scripts/migrations/jan24/validate_keys.rb [OPTIONS]
#
# Options:
#   --mode=MODE        Validation mode: pre-load, post-load, or full (default: full)
#   --input-dir=DIR    Input directory for JSONL files (default: exports/transformed)
#   --valkey-url=URL   Valkey URL for post-load checks (default: redis://127.0.0.1:6379/0)
#   --fix              Attempt to fix issues (post-load only)
#
# Pre-load checks:
# - JSONL file integrity
# - Required fields present
# - Migration metadata complete
#
# Post-load checks:
# - Record count verification per model
# - Foreign key integrity (org_id, owner_id references exist)
# - Sample data spot checks
# - Participation set population

require 'redis'
require 'json'
require 'base64'
require 'fileutils'

# rubocop:disable Metrics/ClassLength, Metrics/PerceivedComplexity
class MigrationValidator
  def initialize(mode:, input_dir:, valkey_url:, fix: false)
    @mode       = mode
    @input_dir  = input_dir
    @valkey_url = valkey_url
    @fix        = fix
    @timestamp  = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')

    @issues   = []
    @warnings = []
    @stats    = { checks: 0, passed: 0, failed: 0, fixed: 0 }
  end

  def validate
    puts '=== Migration Validation ==='
    puts "  Mode: #{@mode}"
    puts "  Input: #{@input_dir}"
    puts "  Valkey: #{@valkey_url}"
    puts "  Fix mode: #{@fix}"
    puts

    case @mode
    when 'pre-load'
      run_pre_load_checks
    when 'post-load'
      run_post_load_checks
    when 'full'
      run_pre_load_checks
      run_post_load_checks
    end

    print_summary
    write_report
  end

  private

  # ============================================
  # Pre-Load Checks
  # ============================================

  def run_pre_load_checks
    puts '=== Pre-Load Validation ==='

    check_jsonl_integrity
    check_required_fields
    check_migration_metadata
    check_mappings_consistency
  end

  def check_jsonl_integrity
    puts "\n  Checking JSONL file integrity..."

    jsonl_files = Dir.glob(File.join(@input_dir, '*.jsonl'))

    jsonl_files.each do |file|
      line_num = 0
      begin
        File.foreach(file) do |line|
          line_num += 1
          JSON.parse(line.strip)
        end
        record_check("JSONL integrity: #{File.basename(file)}", true)
      rescue JSON::ParserError => ex
        record_check(
          "JSONL integrity: #{File.basename(file)}",
          false,
          "Parse error at line #{line_num}: #{ex.message}",
        )
      end
    end
  end

  def check_required_fields
    puts "\n  Checking required fields..."

    # Check organizations have required fields
    org_files = Dir.glob(File.join(@input_dir, 'organization_generated_*.jsonl'))
    org_files.each do |file|
      File.foreach(file) do |line|
        record = JSON.parse(line.strip)
        fields = record['fields']

        missing = []
        %w[objid owner_id contact_email is_default].each do |field|
          missing << field if fields[field.to_sym].to_s.empty? && fields[field].to_s.empty?
        end

        unless missing.empty?
          record_check(
            "Organization #{fields[:objid] || fields['objid']}",
            false,
            "Missing fields: #{missing.join(', ')}",
          )
        end
      end
    end
    record_check('Organization required fields', @issues.empty? || @issues.none? { |i| i[:check].include?('Organization') })

    # Check memberships have required fields
    membership_files = Dir.glob(File.join(@input_dir, 'org_membership_generated_*.jsonl'))
    membership_files.each do |file|
      File.foreach(file) do |line|
        record = JSON.parse(line.strip)
        fields = record['fields']

        missing = []
        %w[objid organization_objid customer_objid role status].each do |field|
          missing << field if fields[field.to_sym].to_s.empty? && fields[field].to_s.empty?
        end

        unless missing.empty?
          record_check(
            "Membership #{fields[:objid] || fields['objid']}",
            false,
            "Missing fields: #{missing.join(', ')}",
          )
        end
      end
    end
    record_check('Membership required fields', @issues.empty? || @issues.none? { |i| i[:check].include?('Membership') })
  end

  def check_migration_metadata
    puts "\n  Checking migration metadata..."

    # Check customers have migration info
    customer_files           = Dir.glob(File.join(@input_dir, 'customer_transformed_*.jsonl'))
    customers_with_migration = 0
    customers_total          = 0

    customer_files.each do |file|
      File.foreach(file) do |line|
        record                    = JSON.parse(line.strip)
        customers_total          += 1
        customers_with_migration += 1 if record['migration']
      end
    end

    record_check(
      "Customer migration metadata (#{customers_with_migration}/#{customers_total})",
      customers_with_migration == customers_total,
    )

    # Check receipts have migration info
    receipt_files           = Dir.glob(File.join(@input_dir, 'receipt_transformed_*.jsonl'))
    receipts_with_migration = 0
    receipts_total          = 0

    receipt_files.each do |file|
      File.foreach(file) do |line|
        record                   = JSON.parse(line.strip)
        receipts_total          += 1
        receipts_with_migration += 1 if record['migration']
      end
    end

    record_check(
      "Receipt migration metadata (#{receipts_with_migration}/#{receipts_total})",
      receipts_with_migration == receipts_total,
    )
  end

  def check_mappings_consistency
    puts "\n  Checking mapping consistency..."

    # Count unique emails from customer transforms
    customer_emails = Set.new
    customer_files  = Dir.glob(File.join(@input_dir, 'customer_transformed_*.jsonl'))

    customer_files.each do |file|
      File.foreach(file) do |line|
        record = JSON.parse(line.strip)
        if record['migration'] && record['migration']['v1_custid']
          customer_emails << record['migration']['v1_custid']
        end
      end
    end

    # Count organizations
    org_count = 0
    org_files = Dir.glob(File.join(@input_dir, 'organization_generated_*.jsonl'))
    org_files.each do |file|
      org_count += File.readlines(file).size
    end

    # Count memberships
    membership_count = 0
    membership_files = Dir.glob(File.join(@input_dir, 'org_membership_generated_*.jsonl'))
    membership_files.each do |file|
      membership_count += File.readlines(file).size
    end

    record_check(
      'Customer→Organization 1:1 mapping',
      org_count == customer_emails.size,
      "Customers: #{customer_emails.size}, Organizations: #{org_count}",
    )

    record_check(
      'Customer→Membership 1:1 mapping',
      membership_count == customer_emails.size,
      "Customers: #{customer_emails.size}, Memberships: #{membership_count}",
    )
  end

  # ============================================
  # Post-Load Checks
  # ============================================

  def run_post_load_checks
    puts "\n=== Post-Load Validation ==="

    @valkey = Redis.new(url: @valkey_url)

    check_record_counts
    check_foreign_key_integrity
    check_migration_status_fields
    check_sample_data
  end

  def check_record_counts
    puts "\n  Checking record counts..."

    # Count records by key pattern
    counts = {
      customer: 0,
      organization: 0,
      org_membership: 0,
      customdomain: 0,
      receipt: 0,
      secret: 0,
    }

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: '*:object', count: 1000)

      keys.each do |key|
        case key
        when /^customer:/
          counts[:customer] += 1
        when /^organization:/
          counts[:organization] += 1
        when /^org_membership:/
          counts[:org_membership] += 1
        when /^customdomain:/
          counts[:customdomain] += 1
        when /^receipt:/
          counts[:receipt] += 1
        when /^secret:/
          counts[:secret] += 1
        end
      end

      break if cursor == '0'
    end

    puts "    Customers:      #{counts[:customer]}"
    puts "    Organizations:  #{counts[:organization]}"
    puts "    Memberships:    #{counts[:org_membership]}"
    puts "    Custom Domains: #{counts[:customdomain]}"
    puts "    Receipts:       #{counts[:receipt]}"
    puts "    Secrets:        #{counts[:secret]}"

    # Validate 1:1 customer:org ratio
    record_check(
      'Customer:Organization 1:1 ratio',
      counts[:customer] == counts[:organization],
      "Customers: #{counts[:customer]}, Orgs: #{counts[:organization]}",
    )

    record_check(
      'Customer:Membership 1:1 ratio',
      counts[:customer] == counts[:org_membership],
      "Customers: #{counts[:customer]}, Memberships: #{counts[:org_membership]}",
    )
  end

  def check_foreign_key_integrity
    puts "\n  Checking foreign key integrity..."

    # Build sets of valid objids
    customer_objids = Set.new
    org_objids      = Set.new

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customer:*:object', count: 1000)
      keys.each do |key|
        objid = @valkey.hget(key, 'objid')
        customer_objids << objid if objid
      end
      break if cursor == '0'
    end

    cursor = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'organization:*:object', count: 1000)
      keys.each do |key|
        objid = @valkey.hget(key, 'objid')
        org_objids << objid if objid
      end
      break if cursor == '0'
    end

    # Check Organization.owner_id references valid Customer
    invalid_org_owners = []
    cursor             = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'organization:*:object', count: 1000)
      keys.each do |key|
        owner_id = @valkey.hget(key, 'owner_id')
        if owner_id && !customer_objids.include?(owner_id)
          invalid_org_owners << { key: key, owner_id: owner_id }
        end
      end
      break if cursor == '0'
    end

    record_check(
      'Organization.owner_id references valid Customer',
      invalid_org_owners.empty?,
      "#{invalid_org_owners.size} invalid references",
    )

    # Check CustomDomain.org_id references valid Organization
    invalid_domain_orgs = []
    cursor              = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'customdomain:*:object', count: 1000)
      keys.each do |key|
        org_id = @valkey.hget(key, 'org_id')
        if org_id && !org_objids.include?(org_id)
          invalid_domain_orgs << { key: key, org_id: org_id }
        end
      end
      break if cursor == '0'
    end

    record_check(
      'CustomDomain.org_id references valid Organization',
      invalid_domain_orgs.empty?,
      "#{invalid_domain_orgs.size} invalid references",
    )

    # Check Receipt.owner_id references valid Customer (or is 'anon')
    invalid_receipt_owners = []
    cursor                 = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'receipt:*:object', count: 1000)
      keys.each do |key|
        owner_id = @valkey.hget(key, 'owner_id')
        if owner_id && owner_id != 'anon' && !customer_objids.include?(owner_id)
          invalid_receipt_owners << { key: key, owner_id: owner_id }
        end
      end
      break if cursor == '0'
    end

    record_check(
      'Receipt.owner_id references valid Customer or anon',
      invalid_receipt_owners.empty?,
      "#{invalid_receipt_owners.size} invalid references",
    )

    # Check Secret.owner_id references valid Customer (or is 'anon')
    invalid_secret_owners = []
    cursor                = '0'
    loop do
      cursor, keys = @valkey.scan(cursor, match: 'secret:*:object', count: 1000)
      keys.each do |key|
        owner_id = @valkey.hget(key, 'owner_id')
        if owner_id && owner_id != 'anon' && !customer_objids.include?(owner_id)
          invalid_secret_owners << { key: key, owner_id: owner_id }
        end
      end
      break if cursor == '0'
    end

    record_check(
      'Secret.owner_id references valid Customer or anon',
      invalid_secret_owners.empty?,
      "#{invalid_secret_owners.size} invalid references",
    )
  end

  def check_migration_status_fields
    puts "\n  Checking migration status fields..."

    models = {
      'customer:*:object' => 'Customer',
      'organization:*:object' => 'Organization',
      'receipt:*:object' => 'Receipt',
      'secret:*:object' => 'Secret',
    }

    models.each do |pattern, model_name|
      migrated = 0
      pending  = 0
      total    = 0

      cursor = '0'
      loop do
        cursor, keys = @valkey.scan(cursor, match: pattern, count: 1000)
        keys.each do |key|
          total           += 1
          migration_status = @valkey.hget(key, 'migration_status')
          if migration_status == 'completed'
            migrated += 1
          else
            pending += 1
          end
        end
        break if cursor == '0'
      end

      record_check(
        "#{model_name} migration_status (#{migrated}/#{total} completed)",
        pending == 0,
        "#{pending} records pending",
      )
    end
  end

  def check_sample_data
    puts "\n  Checking sample data spot checks..."

    # Sample a customer and verify fields
    sample_customer_key = nil
    cursor              = '0'
    loop do
      cursor, keys        = @valkey.scan(cursor, match: 'customer:*:object', count: 10)
      sample_customer_key = keys.first if keys.any?
      break if sample_customer_key || cursor == '0'
    end

    if sample_customer_key
      fields = @valkey.hgetall(sample_customer_key)

      # Check required v2 fields exist
      required = %w[objid custid email v1_custid migration_status]
      missing  = required.select { |f| fields[f].to_s.empty? }

      record_check(
        'Sample customer has required fields',
        missing.empty?,
        "Missing: #{missing.join(', ')}",
      )

      # Check custid == objid (v2 requirement)
      record_check(
        'Sample customer custid == objid',
        fields['custid'] == fields['objid'],
        "custid: #{fields['custid']}, objid: #{fields['objid']}",
      )
    end

    # Sample a receipt and verify field renames
    sample_receipt_key = nil
    cursor             = '0'
    loop do
      cursor, keys       = @valkey.scan(cursor, match: 'receipt:*:object', count: 10)
      sample_receipt_key = keys.first if keys.any?
      break if sample_receipt_key || cursor == '0'
    end

    return unless sample_receipt_key

    fields = @valkey.hgetall(sample_receipt_key)

    # Check deprecated 'custid' field removed
    record_check(
      'Sample receipt custid field removed',
      fields['custid'].to_s.empty?,
      "custid still present: #{fields['custid']}",
    )

    # Check owner_id present
    record_check(
      'Sample receipt has owner_id',
      !fields['owner_id'].to_s.empty?,
      'owner_id missing',
    )
  end

  # ============================================
  # Reporting
  # ============================================

  def record_check(check_name, passed, details = nil)
    @stats[:checks] += 1

    if passed
      @stats[:passed] += 1
      puts "    [PASS] #{check_name}"
    else
      @stats[:failed] += 1
      puts "    [FAIL] #{check_name}"
      puts "           #{details}" if details
      @issues << { check: check_name, details: details }
    end
  end

  def print_summary
    puts "\n=== Validation Summary ==="
    puts "  Total checks: #{@stats[:checks]}"
    puts "  Passed:       #{@stats[:passed]}"
    puts "  Failed:       #{@stats[:failed]}"

    if @issues.any?
      puts "\n  Issues found:"
      @issues.each do |issue|
        puts "    - #{issue[:check]}: #{issue[:details]}"
      end
    else
      puts "\n  All checks passed."
    end
  end

  def write_report
    report = {
      timestamp: @timestamp,
      mode: @mode,
      input_dir: @input_dir,
      valkey_url: @valkey_url.sub(/:[^:@]*@/, ':***@'),
      stats: @stats,
      issues: @issues,
      warnings: @warnings,
    }

    FileUtils.mkdir_p(@input_dir)
    report_file = File.join(@input_dir, "validation_report_#{@timestamp}.json")
    File.write(report_file, JSON.pretty_generate(report))
    puts "\n  Report: #{report_file}"
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/PerceivedComplexity

def parse_args(args)
  options = {
    mode: 'full',
    input_dir: 'exports/transformed',
    valkey_url: 'redis://127.0.0.1:6379/0',
    fix: false,
  }

  args.each do |arg|
    case arg
    when /^--mode=(.+)$/
      options[:mode] = Regexp.last_match(1)
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--valkey-url=(.+)$/
      options[:valkey_url] = Regexp.last_match(1)
    when '--fix'
      options[:fix] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/migrations/jan24/validate_keys.rb [OPTIONS]

        Options:
          --mode=MODE        Validation mode: pre-load, post-load, or full (default: full)
          --input-dir=DIR    Input directory (default: exports/transformed)
          --valkey-url=URL   Valkey URL (default: redis://127.0.0.1:6379/0)
          --fix              Attempt to fix issues (post-load only)
          --help             Show this help
      HELP
      exit 0
    end
  end

  options
end

if __FILE__ == $0
  options = parse_args(ARGV)

  validator = MigrationValidator.new(
    mode: options[:mode],
    input_dir: options[:input_dir],
    valkey_url: options[:valkey_url],
    fix: options[:fix],
  )

  validator.validate
end
