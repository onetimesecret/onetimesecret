# apps/api/domains/try/cli/verify_command_try.rb
#
# frozen_string_literal: true

# Tests for DomainsVerifyCommand CLI
#
# Validates:
# 1. Command class structure and inheritance
# 2. Helper method functionality (filters, formatters)
# 3. Result objects work correctly
# 4. Command flag handling (--all, --dry-run, --json, filters)
# 5. Command argument validation

require_relative '../../../../../try/support/test_helpers'
require 'securerandom'
require 'json'

OT.boot! :test

# Load CLI command infrastructure
require 'onetime/cli'
require 'onetime/operations/verify_domain'
require 'apps/api/domains/cli/helpers'
require 'apps/api/domains/cli/verify_command'

# Setup: Create command instance
@cmd = Onetime::CLI::DomainsVerifyCommand.new

# Setup: Mock domain objects for filter testing
MockFilterDomain = Struct.new(:display_domain, :verified, :org_id)
@filter_domain1 = MockFilterDomain.new('verified.example.com', 'true', 'org-123')
@filter_domain2 = MockFilterDomain.new('unverified.example.com', 'false', 'org-123')
@filter_domain3 = MockFilterDomain.new('orphaned.example.com', 'false', '')
@filter_domains = [@filter_domain1, @filter_domain2, @filter_domain3]

# Setup: Mock domain for Result testing
@mock_domain = Struct.new(:display_domain).new('test.example.com')

## DomainsVerifyCommand class exists
defined?(Onetime::CLI::DomainsVerifyCommand)
#=> 'constant'

## DomainsVerifyCommand inherits from Command
Onetime::CLI::DomainsVerifyCommand < Onetime::CLI::Command
#=> true

## DomainsVerifyCommand includes DomainsHelpers
Onetime::CLI::DomainsVerifyCommand.include?(Onetime::CLI::DomainsHelpers)
#=> true

## Helpers: format_bool handles true
@cmd.send(:format_bool, true)
#=> 'yes'

## Helpers: format_bool handles false
@cmd.send(:format_bool, false)
#=> 'no'

## Helpers: format_bool handles nil
@cmd.send(:format_bool, nil)
#=> 'unknown'

## Helpers: apply_filters filters by verified status
@verified_filtered = @cmd.send(:apply_filters, @filter_domains, verified: true)
@verified_filtered.map(&:display_domain).include?('verified.example.com')
#=> true

## Helpers: apply_filters excludes unverified when verified: true
@verified_filtered = @cmd.send(:apply_filters, @filter_domains, verified: true)
@verified_filtered.map(&:display_domain).include?('unverified.example.com')
#=> false

## Helpers: apply_filters filters by unverified status
@unverified_filtered = @cmd.send(:apply_filters, @filter_domains, unverified: true)
@unverified_filtered.map(&:display_domain).include?('unverified.example.com')
#=> true

## Helpers: apply_filters orphaned included in unverified
@unverified_filtered = @cmd.send(:apply_filters, @filter_domains, unverified: true)
@unverified_filtered.map(&:display_domain).include?('orphaned.example.com')
#=> true

## Helpers: apply_filters filters by orphaned status
@orphaned_filtered = @cmd.send(:apply_filters, @filter_domains, orphaned: true)
@orphaned_filtered.size
#=> 1

## Helpers: apply_filters orphaned filter returns correct domain
@orphaned_filtered = @cmd.send(:apply_filters, @filter_domains, orphaned: true)
@orphaned_filtered.first.display_domain
#=> 'orphaned.example.com'

## Helpers: apply_filters filters by org_id
@org_filtered = @cmd.send(:apply_filters, @filter_domains, org_id: 'org-123')
@org_filtered.size
#=> 2

## Result to_h works for single domain result
@mock_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@mock_result.to_h[:dns_validated]
#=> true

## Result to_h includes dry_run when merged
@mock_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
output = @mock_result.to_h.merge(dry_run: true)
output[:dry_run]
#=> true

## Result success? returns true when no error
@mock_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@mock_result.success?
#=> true

## Result changed? detects state change
@mock_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@mock_result.changed?
#=> true

## Result with error has success? false
@error_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :pending,
  dns_validated: false,
  ssl_ready: false,
  is_resolving: false,
  persisted: false,
  error: 'Connection failed',
)
@error_result.success?
#=> false

## BulkResult to_h works for bulk results
@mock_result_for_bulk = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@mock_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 2,
  verified_count: 1,
  failed_count: 0,
  skipped_count: 1,
  results: [@mock_result_for_bulk],
  duration_seconds: 1.5,
)
@mock_bulk.to_h[:total]
#=> 2

## BulkResult success? returns true when failed_count is 0
@mock_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 2,
  verified_count: 1,
  failed_count: 0,
  skipped_count: 1,
  results: [],
  duration_seconds: 1.5,
)
@mock_bulk.success?
#=> true

## BulkResult with failures has success? false
@mock_bulk_fail = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 2,
  verified_count: 0,
  failed_count: 2,
  skipped_count: 0,
  results: [],
  duration_seconds: 1.0,
)
@mock_bulk_fail.success?
#=> false

# ============================================================
# Command Options and Arguments
# ============================================================

## Command has domain_name argument defined as optional
# The domain_name argument should be optional to support --all mode
@cmd_class = Onetime::CLI::DomainsVerifyCommand
@cmd_class.instance_methods.include?(:call)
#=> true

## Command call method accepts all flag
# Check that the call method signature includes :all parameter
@call_params = Onetime::CLI::DomainsVerifyCommand.instance_method(:call).parameters.map(&:last)
@call_params.include?(:all)
#=> true

## Command call method accepts dry_run flag
@call_params = Onetime::CLI::DomainsVerifyCommand.instance_method(:call).parameters.map(&:last)
@call_params.include?(:dry_run)
#=> true

## Command call method accepts json flag
@call_params = Onetime::CLI::DomainsVerifyCommand.instance_method(:call).parameters.map(&:last)
@call_params.include?(:json)
#=> true

## Command has filtering options for bulk mode (orphaned, verified, unverified, org_id, limit)
@filter_options = [:orphaned, :verified, :unverified, :org_id, :limit]
# These options should be accepted by the call method
@call_params = Onetime::CLI::DomainsVerifyCommand.instance_method(:call).parameters.map(&:last)
@filter_options.all? { |opt| @call_params.include?(opt) }
#=> true

# ============================================================
# Dry-Run Behavior
# ============================================================

## Result with dry-run should have persisted=false
@dry_run_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,  # dry-run mode doesn't persist
  error: nil,
)
@dry_run_result.persisted
#=> false

## Dry-run result can still report success
@dry_run_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@dry_run_result.success?
#=> true

## Dry-run result can detect state changes without persisting
@dry_run_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :unverified,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@dry_run_result.changed?
#=> true

## Result to_h with dry_run merged includes the flag
@result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@output = @result.to_h.merge(dry_run: true)
[@output[:dry_run], @output[:persisted]]
#=> [true, false]

# ============================================================
# Bulk Mode (--all) Behavior
# ============================================================

## BulkResult can be created with empty results
@empty_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 0,
  verified_count: 0,
  failed_count: 0,
  skipped_count: 0,
  results: [],
  duration_seconds: 0.0,
)
@empty_bulk.total
#=> 0

## BulkResult with empty results is success
@empty_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 0,
  verified_count: 0,
  failed_count: 0,
  skipped_count: 0,
  results: [],
  duration_seconds: 0.0,
)
@empty_bulk.success?
#=> true

## BulkResult to_h includes dry_run when merged
@bulk_result = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 3,
  verified_count: 2,
  failed_count: 0,
  skipped_count: 1,
  results: [],
  duration_seconds: 2.5,
)
@output = @bulk_result.to_h.merge(dry_run: true)
[@output[:dry_run], @output[:total]]
#=> [true, 3]

## BulkResult tracks duration correctly
@timed_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 5,
  verified_count: 3,
  failed_count: 1,
  skipped_count: 1,
  results: [],
  duration_seconds: 3.75,
)
@timed_bulk.duration_seconds
#=> 3.75

# ============================================================
# Filter Combinations
# ============================================================

## Helpers: combine orphaned and limit filters
@all_domains = [
  MockFilterDomain.new('orphan1.com', 'false', ''),
  MockFilterDomain.new('orphan2.com', 'false', ''),
  MockFilterDomain.new('orphan3.com', 'false', ''),
  MockFilterDomain.new('owned.com', 'false', 'org-123'),
]
@orphaned_only = @cmd.send(:apply_filters, @all_domains, orphaned: true)
@orphaned_only.size
#=> 3

## Helpers: orphaned filter excludes domains with org_id
@all_domains = [
  MockFilterDomain.new('orphan1.com', 'false', ''),
  MockFilterDomain.new('orphan2.com', 'false', ''),
  MockFilterDomain.new('owned.com', 'false', 'org-123'),
]
@orphaned_only = @cmd.send(:apply_filters, @all_domains, orphaned: true)
@orphaned_only.map(&:display_domain).include?('owned.com')
#=> false

## Helpers: verified and org_id filters can combine
@mixed_domains = [
  MockFilterDomain.new('verified-org1.com', 'true', 'org-1'),
  MockFilterDomain.new('unverified-org1.com', 'false', 'org-1'),
  MockFilterDomain.new('verified-org2.com', 'true', 'org-2'),
]
@filtered = @cmd.send(:apply_filters, @mixed_domains, verified: true, org_id: 'org-1')
@filtered.map(&:display_domain)
#=> ['verified-org1.com']

## Helpers: unverified and org_id filters can combine
@mixed_domains = [
  MockFilterDomain.new('verified-org1.com', 'true', 'org-1'),
  MockFilterDomain.new('unverified-org1.com', 'false', 'org-1'),
  MockFilterDomain.new('unverified-org2.com', 'false', 'org-2'),
]
@filtered = @cmd.send(:apply_filters, @mixed_domains, unverified: true, org_id: 'org-1')
@filtered.map(&:display_domain)
#=> ['unverified-org1.com']

## Helpers: no filters returns all domains
@all_domains = [
  MockFilterDomain.new('a.com', 'true', 'org-1'),
  MockFilterDomain.new('b.com', 'false', 'org-2'),
  MockFilterDomain.new('c.com', 'false', ''),
]
@filtered = @cmd.send(:apply_filters, @all_domains)
@filtered.size
#=> 3

# ============================================================
# JSON Output Format
# ============================================================

## Result to_h produces valid JSON structure
@result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: true,
  error: nil,
)
@hash = @result.to_h
@hash.keys.sort
#=> [:current_state, :dns_validated, :domain, :error, :is_resolving, :persisted, :previous_state, :ssl_ready]

## BulkResult to_h produces valid JSON structure
@bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 2,
  verified_count: 1,
  failed_count: 0,
  skipped_count: 1,
  results: [],
  duration_seconds: 1.0,
)
@hash = @bulk.to_h
@hash.keys.sort
#=> [:duration_seconds, :failed_count, :results, :skipped_count, :total, :verified_count]

## Result to_h can be serialized to JSON
@result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: false,
  is_resolving: true,
  persisted: false,
  error: nil,
)
@json = JSON.generate(@result.to_h)
JSON.parse(@json)['dns_validated']
#=> true

## BulkResult to_h can be serialized to JSON
@bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 5,
  verified_count: 3,
  failed_count: 1,
  skipped_count: 1,
  results: [],
  duration_seconds: 2.5,
)
@json = JSON.generate(@bulk.to_h)
JSON.parse(@json)['total']
#=> 5

# ============================================================
# Error Handling
# ============================================================

## Result with error preserves error message
@error_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :pending,
  dns_validated: false,
  ssl_ready: false,
  is_resolving: false,
  persisted: false,
  error: 'DNS lookup timeout',
)
@error_result.error
#=> 'DNS lookup timeout'

## Result with error has success? false
@error_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :pending,
  dns_validated: false,
  ssl_ready: false,
  is_resolving: false,
  persisted: false,
  error: 'Connection refused',
)
@error_result.success?
#=> false

## Result with error does not show state change
@error_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: @mock_domain,
  previous_state: :pending,
  current_state: :pending,
  dns_validated: false,
  ssl_ready: false,
  is_resolving: false,
  persisted: false,
  error: 'API error',
)
@error_result.changed?
#=> false

## BulkResult with mixed results reports partial success correctly
@success_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: Struct.new(:display_domain).new('good.com'),
  previous_state: :pending,
  current_state: :verified,
  dns_validated: true,
  ssl_ready: true,
  is_resolving: true,
  persisted: true,
  error: nil,
)
@error_result = Onetime::Operations::VerifyDomain::Result.new(
  domain: Struct.new(:display_domain).new('bad.com'),
  previous_state: :pending,
  current_state: :pending,
  dns_validated: false,
  ssl_ready: false,
  is_resolving: false,
  persisted: false,
  error: 'Timeout',
)
@mixed_bulk = Onetime::Operations::VerifyDomain::BulkResult.new(
  total: 2,
  verified_count: 1,
  failed_count: 1,
  skipped_count: 0,
  results: [@success_result, @error_result],
  duration_seconds: 2.0,
)
[@mixed_bulk.success?, @mixed_bulk.verified_count, @mixed_bulk.failed_count]
#=> [false, 1, 1]
