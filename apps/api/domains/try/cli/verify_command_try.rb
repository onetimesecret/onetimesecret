# apps/api/domains/try/cli/verify_command_try.rb
#
# frozen_string_literal: true

# Tests for DomainsVerifyCommand CLI
#
# Validates:
# 1. Command class structure and inheritance
# 2. Helper method functionality (filters, formatters)
# 3. Result objects work correctly

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
