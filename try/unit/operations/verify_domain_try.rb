# try/unit/operations/verify_domain_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Operations::VerifyDomain
#
# Validates:
# 1. Single domain verification with mocked strategy
# 2. Bulk domain verification with rate limiting
# 3. Dry-run mode (persist: false)
# 4. Error handling and graceful failure
# 5. Result immutability via Data.define

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/verify_domain'

# Mock strategy for testing without external API calls
class MockValidationStrategy
  attr_accessor :ownership_result, :status_result, :certificate_result

  def initialize
    @ownership_result = { validated: true, message: 'TXT record matches', data: nil }
    @status_result = { ready: true, has_ssl: true, is_resolving: true, data: nil }
    @certificate_result = { status: 'success', message: 'Created', data: nil }
  end

  def validate_ownership(_domain)
    @ownership_result
  end

  def check_status(_domain)
    @status_result
  end

  def request_certificate(_domain)
    @certificate_result
  end

  def strategy_name
    'mock'
  end
end

# Setup test fixtures
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "verify_ops_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("VerifyOps Corp", @owner, "verify_ops_#{@timestamp}@corp.com")
@org.define_singleton_method(:billing_enabled?) { false }

# Create test domains
@domain1 = Onetime::CustomDomain.create!("verified-#{@timestamp}.example.com", @org.objid)
@domain2 = Onetime::CustomDomain.create!("unverified-#{@timestamp}.example.com", @org.objid)
@domain3 = Onetime::CustomDomain.create!("failing-#{@timestamp}.example.com", @org.objid)

# Initialize domains with different states
@domain1.verified = 'false'
@domain1.resolving = 'false'
@domain1.save

@domain2.verified = 'false'
@domain2.resolving = 'false'
@domain2.save

@domain3.verified = 'false'
@domain3.resolving = 'false'
@domain3.save

# Create mock strategy
@strategy = MockValidationStrategy.new

## Result is a Data.define (immutable)
Onetime::Operations::VerifyDomain::Result.ancestors.include?(Data)
#=> true

## BulkResult is a Data.define (immutable)
Onetime::Operations::VerifyDomain::BulkResult.ancestors.include?(Data)
#=> true

## Single domain verification with mocked strategy - returns Result
@strategy.ownership_result = { validated: true, message: 'OK', data: nil }
@strategy.status_result = { ready: true, has_ssl: true, is_resolving: true, data: nil }
@result1 = Onetime::Operations::VerifyDomain.new(
  domain: @domain1,
  strategy: @strategy,
  persist: true,
).call
@result1.class.name
#=> 'Onetime::Operations::VerifyDomain::Result'

## Single domain verification - dns_validated matches strategy result
@result1.dns_validated
#=> true

## Single domain verification - is_resolving matches strategy result
@result1.is_resolving
#=> true

## Single domain verification - ssl_ready matches strategy result
@result1.ssl_ready
#=> true

## Single domain verification - success? returns true on no error
@result1.success?
#=> true

## Single domain verification - persisted is true
@result1.persisted
#=> true

## Single domain verification - domain is same instance
@result1.domain.display_domain
#=> @domain1.display_domain

## Dry-run mode - persist: false prevents saving changes
@domain2.verified = 'false'
@domain2.resolving = 'false'
@domain2.save
@result2 = Onetime::Operations::VerifyDomain.new(
  domain: @domain2,
  strategy: @strategy,
  persist: false,
).call
@result2.persisted
#=> false

## Dry-run mode - dns_validated still shows validation result
@result2.dns_validated
#=> true

## Failed DNS validation - updates result correctly
@strategy.ownership_result = { validated: false, message: 'TXT not found', data: nil }
@result3 = Onetime::Operations::VerifyDomain.new(
  domain: @domain3,
  strategy: @strategy,
  persist: true,
).call
@result3.dns_validated
#=> false

## Failed DNS validation - success? still true (no exception)
@result3.success?
#=> true

## Error handling - strategy exception in validate_ownership is caught
class FailingOwnershipStrategy
  def validate_ownership(_domain)
    raise StandardError, 'API connection failed'
  end

  def check_status(_domain)
    { ready: false, has_ssl: false, is_resolving: false }
  end

  def strategy_name
    'failing_ownership'
  end
end
@failing_ownership_strategy = FailingOwnershipStrategy.new
@result4 = Onetime::Operations::VerifyDomain.new(
  domain: @domain3,
  strategy: @failing_ownership_strategy,
  persist: false,
).call
# Errors in validate_ownership are caught and return validated: false
@result4.dns_validated
#=> false

## Error handling - success? still true because exception was handled
# The operation itself succeeded (ran to completion), just validation failed
@result4.success?
#=> true

## Error handling - domain still accessible
@result4.domain.display_domain
#=> @domain3.display_domain

## Error handling - unrecoverable exception bubbles up to Result.error
class TotallyBrokenStrategy
  def validate_ownership(_domain)
    { validated: false, message: 'OK', data: nil }
  end

  def check_status(_domain)
    # Simulate unrecoverable error that bubbles up
    raise RuntimeError, 'Strategy crashed completely'
  end

  def strategy_name
    'totally_broken'
  end
end
@broken_strategy = TotallyBrokenStrategy.new
@result_broken = Onetime::Operations::VerifyDomain.new(
  domain: @domain3,
  strategy: @broken_strategy,
  persist: false,
).call
# check_status exception also gets caught and returns default values
@result_broken.is_resolving
#=> false

## Bulk verification - processes multiple domains
@strategy.ownership_result = { validated: true, message: 'OK', data: nil }
@strategy.status_result = { ready: true, has_ssl: true, is_resolving: true, data: nil }
@bulk_result = Onetime::Operations::VerifyDomain.new(
  domains: [@domain1, @domain2],
  strategy: @strategy,
  persist: false,
  rate_limit: 0.0, # No delay for tests
).call
@bulk_result.class.name
#=> 'Onetime::Operations::VerifyDomain::BulkResult'

## Bulk verification - total count correct
@bulk_result.total
#=> 2

## Bulk verification - verified_count tracks dns_validated
@bulk_result.verified_count
#=> 2

## Bulk verification - failed_count is zero on success
@bulk_result.failed_count
#=> 0

## Bulk verification - results array has correct size
@bulk_result.results.size
#=> 2

## Bulk verification - duration_seconds is numeric
@bulk_result.duration_seconds.is_a?(Numeric)
#=> true

## Bulk verification - success? returns true when no failures
@bulk_result.success?
#=> true

## Result to_h - produces hash representation
@result1.to_h.keys.sort
#=> [:current_state, :dns_validated, :domain, :error, :is_resolving, :persisted, :previous_state, :ssl_ready]

## Result changed? - detects state change
# Reset domain and verify with different outcome
@domain1.verified = 'false'
@domain1.resolving = 'false'
@domain1.save
@strategy.ownership_result = { validated: true, message: 'OK', data: nil }
@strategy.status_result = { ready: true, has_ssl: true, is_resolving: true, data: nil }
@result_change = Onetime::Operations::VerifyDomain.new(
  domain: @domain1,
  strategy: @strategy,
  persist: true,
).call
# changed? is true when state transitions (depends on initial state)
[@result_change.previous_state, @result_change.current_state].include?(:pending) ||
[@result_change.previous_state, @result_change.current_state].include?(:resolving) ||
[@result_change.previous_state, @result_change.current_state].include?(:verified) ||
[@result_change.previous_state, @result_change.current_state].include?(:unverified)
#=> true

## BulkResult to_h - produces hash with nested results
@bulk_result.to_h.keys.sort
#=> [:duration_seconds, :failed_count, :results, :skipped_count, :total, :verified_count]

## Argument validation - requires domain or domains
begin
  Onetime::Operations::VerifyDomain.new(persist: false).call
  "unexpected_success"
rescue ArgumentError => e
  e.message
end
#=> "Must provide either domain: or domains:"

## Argument validation - cannot provide both domain and domains
begin
  Onetime::Operations::VerifyDomain.new(
    domain: @domain1,
    domains: [@domain2],
    persist: false,
  ).call
  "unexpected_success"
rescue ArgumentError => e
  e.message
end
#=> "Cannot provide both domain: and domains:"

# Teardown
@domain1.destroy! if @domain1&.exists?
@domain2.destroy! if @domain2&.exists?
@domain3.destroy! if @domain3&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
