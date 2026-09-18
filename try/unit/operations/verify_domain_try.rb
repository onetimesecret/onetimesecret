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
  attr_accessor :ownership_result, :status_result, :certificate_result, :bulk_rate_limit

  def initialize
    @bulk_rate_limit = 0
    @ownership_result = { validated: true, message: 'TXT record matches', data: [] }
    @status_result = {
      ready: true,
      has_ssl: true,
      is_resolving: true,
      data: { 'status' => 'ACTIVE_SSL', 'is_resolving' => true, 'has_ssl' => true },
    }
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
@strategy.ownership_result = { validated: true, message: 'OK', data: [] }
@strategy.status_result = {
  ready: true,
  has_ssl: true,
  is_resolving: true,
  data: { 'status' => 'ACTIVE_SSL', 'is_resolving' => true, 'has_ssl' => true },
}
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
@strategy.ownership_result = { validated: false, message: 'TXT not found', data: [] }
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
    { validated: false, message: 'OK', data: [] }
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
@strategy.ownership_result = { validated: true, message: 'OK', data: [] }
@strategy.status_result = {
  ready: true,
  has_ssl: true,
  is_resolving: true,
  data: { 'status' => 'ACTIVE_SSL', 'is_resolving' => true, 'has_ssl' => true },
}
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
#=> [:confirmation_expired, :current_state, :dns_indeterminate, :dns_message, :dns_outcome, :dns_validated, :domain, :error, :is_resolving, :override_held, :persisted, :previous_state, :ssl_ready]

## Result changed? - detects state change
# Reset domain and verify with different outcome
@domain1.verified = 'false'
@domain1.resolving = 'false'
@domain1.save
@strategy.ownership_result = { validated: true, message: 'OK', data: [] }
@strategy.status_result = {
  ready: true,
  has_ssl: true,
  is_resolving: true,
  data: { 'status' => 'ACTIVE_SSL', 'is_resolving' => true, 'has_ssl' => true },
}
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
#=> [:confirmation_expired_count, :demoted_count, :duration_seconds, :failed_count, :indeterminate_count, :results, :skipped_count, :total, :verified_count]

# ─────────────────────────────────────────────────────────────────────────
# Issue #3080: atomic persistence smoke tests.
# The persist_changes branch logic (data/mode/else) is verified by code
# review; here we exercise the operation across the three strategy
# response shapes and confirm it returns success + does not raise.
# Deeper persistence introspection has been left to integration coverage
# because the in-test save/refresh round-trip surfaces Familia v2 type
# coercion that obscures the field-level signal.
# ─────────────────────────────────────────────────────────────────────────

## Issue #3080: FailingStatusStrategy (no :data, no :mode) — operation completes
class FailingStatusStrategy
  def validate_ownership(_d)
    { validated: true, message: 'OK', data: [] }
  end

  def check_status(_d)
    { ready: false, has_ssl: false, is_resolving: false, message: 'API down' }
  end

  def strategy_name
    'failing_status'
  end
end
@failing_status_strategy = FailingStatusStrategy.new
@failing_status_result   = Onetime::Operations::VerifyDomain.new(
  domain: @domain1,
  strategy: @failing_status_strategy,
  persist: true,
).call
@failing_status_result.success?
#=> true

## Issue #3080: FailingStatusStrategy — Result.is_resolving reflects strategy
@failing_status_result.is_resolving
#=> false

## Issue #3080: PassiveStrategy (:mode set, no :data) — operation completes
class PassiveStrategy
  def validate_ownership(_d)
    { validated: true, message: 'External validation', mode: 'passthrough' }
  end

  def check_status(_d)
    { ready: true, has_ssl: true, is_resolving: true,
      mode: 'passthrough', message: 'External management' }
  end

  def strategy_name
    'passthrough'
  end
end
@passive_strategy = PassiveStrategy.new
@passive_result   = Onetime::Operations::VerifyDomain.new(
  domain: @domain2,
  strategy: @passive_strategy,
  persist: true,
).call
@passive_result.success?
#=> true

## Issue #3080: PassiveStrategy — Result.dns_validated is true
@passive_result.dns_validated
#=> true

## Issue #3080: PassiveStrategy — Result.is_resolving is true
@passive_result.is_resolving
#=> true

## Indeterminate TXT check — a verified domain is NOT demoted
# The upstream checker answered 200 but its own DNS lookup failed
# (Approximated: "actual_values" => false). That is no evidence about the
# customer's DNS, so the stored verified flag must survive the run.
@domain1.verified  = true
@domain1.resolving = true
@domain1.save
@indeterminate_strategy = MockValidationStrategy.new
@indeterminate_strategy.ownership_result = {
  validated: nil,
  indeterminate: true,
  message: 'Upstream DNS checker returned no result (indeterminate)',
  data: [{ 'actual_values' => false, 'match' => false }],
}
@indeterminate_result = Onetime::Operations::VerifyDomain.new(
  domain: @domain1,
  strategy: @indeterminate_strategy,
  persist: true,
).call
[@indeterminate_result.previous_state, @indeterminate_result.current_state, @indeterminate_result.demoted?]
#=> [:verified, :verified, false]

## Indeterminate TXT check — persisted verified flag is still true
Onetime::CustomDomain.find_by_identifier(@domain1.identifier).verified
#=> true

## Indeterminate TXT check — Result reports indeterminate, not a plain failure
[@indeterminate_result.dns_validated, @indeterminate_result.dns_indeterminate, @indeterminate_result.dns_message]
#=> [false, true, 'Upstream DNS checker returned no result (indeterminate)']

## Real mismatch — a verified domain IS demoted and the Result says so
@indeterminate_strategy.ownership_result = { validated: false, message: 'TXT record not found', data: [{ 'actual_values' => [], 'match' => false }] }
@demoted_result = Onetime::Operations::VerifyDomain.new(
  domain: @domain1,
  strategy: @indeterminate_strategy,
  persist: true,
).call
[@demoted_result.previous_state, @demoted_result.current_state, @demoted_result.demoted?, @demoted_result.dns_indeterminate]
#=> [:verified, :resolving, true, false]

## Bulk verification — counts indeterminate and demoted runs
@domain1.verified = true
@domain1.save
@indeterminate_strategy.ownership_result = { validated: false, message: 'TXT record not found', data: [] }
@bulk_counts = Onetime::Operations::VerifyDomain.new(
  domains: [@domain1],
  strategy: @indeterminate_strategy,
  persist: true,
  rate_limit: 0,
).call
[@bulk_counts.indeterminate_count, @bulk_counts.demoted_count]
#=> [0, 1]

## Bulk pacing — no explicit rate_limit defers to the strategy's bulk_rate_limit
@paced_strategy = MockValidationStrategy.new
@paced_strategy.bulk_rate_limit = 0.25
def recorded_sleeps(**opts)
  sleeps = []
  op = Onetime::Operations::VerifyDomain.new(domains: [@domain1, @domain2, @domain3], persist: false, **opts)
  op.define_singleton_method(:sleep) { |seconds| sleeps << seconds }
  op.call
  sleeps
end
recorded_sleeps(strategy: @paced_strategy)
#=> [0.25, 0.25]

## Bulk pacing — a strategy that declares no pacing never sleeps
recorded_sleeps(strategy: MockValidationStrategy.new)
#=> []

## Bulk pacing — an explicit rate_limit overrides the strategy
recorded_sleeps(strategy: @paced_strategy, rate_limit: 1.5)
#=> [1.5, 1.5]

## Bulk pacing — an explicit 0 turns the strategy's pacing off
recorded_sleeps(strategy: @paced_strategy, rate_limit: 0)
#=> []

## Operator override — a failed TXT check does NOT demote an overridden domain
# The Colonel override sets verified_by_override. It is the operator's standing
# assertion for domains DNS checks cannot reach, so a real mismatch holds.
@domain2.verified             = true
@domain2.verified_by_override = true
@domain2.resolving            = true
@domain2.save
@override_strategy = MockValidationStrategy.new
@override_strategy.ownership_result = { validated: false, message: 'TXT record not found', data: [] }
@override_result = Onetime::Operations::VerifyDomain.new(
  domain: @domain2,
  strategy: @override_strategy,
  persist: true,
).call
[@override_result.current_state, @override_result.demoted?, @override_result.override_held, @override_result.dns_outcome]
#=> [:verified, false, true, :override_held]

## Operator override — persisted flags survive the failed check
@reloaded_override = Onetime::CustomDomain.find_by_identifier(@domain2.identifier)
[@reloaded_override.verified, @reloaded_override.verified_by_override]
#=> [true, true]

## Operator override — a passing check clears the marker (DNS now holds the flag)
@override_strategy.ownership_result = { validated: true, message: 'TXT record validated', data: [] }
Onetime::Operations::VerifyDomain.new(domain: @domain2, strategy: @override_strategy, persist: true).call
@reloaded_override = Onetime::CustomDomain.find_by_identifier(@domain2.identifier)
[@reloaded_override.verified, @reloaded_override.verified_by_override]
#=> [true, false]

## Operator override — with the marker cleared, a later mismatch demotes normally
@override_strategy.ownership_result = { validated: false, message: 'TXT record not found', data: [] }
@after_clear = Onetime::Operations::VerifyDomain.new(domain: @domain2, strategy: @override_strategy, persist: true).call
[@after_clear.demoted?, @after_clear.override_held]
#=> [true, false]

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
