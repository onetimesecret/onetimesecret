# try/unit/domain_validation/parallel_dns_verification_try.rb
#
# frozen_string_literal: true

# Tests for parallel DNS verification in BaseStrategy#verify_all_records
#
# Validates:
# 1. Results match input count and order
# 2. Error isolation (one failure doesn't crash batch)
# 3. Concurrent::Promises futures used correctly
# 4. Error field populated on individual failures
# 5. Performance improvement from parallelization

require_relative '../../support/test_helpers'
require 'concurrent'
require 'resolv'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/strategy'

# Test strategy that exposes verify_all_records for direct testing
class TestableParallelStrategy < Onetime::DomainValidation::SenderStrategies::BaseStrategy
  attr_accessor :mock_records, :lookup_delays, :lookup_errors

  def initialize
    @mock_records = []
    @lookup_delays = {}   # host -> delay_seconds
    @lookup_errors = {}   # host -> exception
    @lookup_calls = []
    @resolver_instances = []
  end

  def required_dns_records(_mailer_config)
    @mock_records
  end

  def verify_dns_records(mailer_config)
    verify_all_records(mailer_config)
  end

  def strategy_name
    'testable_parallel'
  end

  private

  # Override lookup methods to use mock data
  def lookup_cname_records(hostname, resolver: nil, bypass_cache: false)
    @resolver_instances << resolver.object_id if resolver
    @lookup_calls << [:cname, hostname, Thread.current.object_id]
    sleep(@lookup_delays[hostname]) if @lookup_delays[hostname]
    raise @lookup_errors[hostname] if @lookup_errors[hostname]
    ["#{hostname}.mock.result"]
  end

  def lookup_txt_records(hostname, resolver: nil, bypass_cache: false)
    @resolver_instances << resolver.object_id if resolver
    @lookup_calls << [:txt, hostname, Thread.current.object_id]
    sleep(@lookup_delays[hostname]) if @lookup_delays[hostname]
    raise @lookup_errors[hostname] if @lookup_errors[hostname]
    ["v=spf1 include:mock.com ~all"]
  end

  def lookup_mx_records(hostname, resolver: nil, bypass_cache: false)
    @resolver_instances << resolver.object_id if resolver
    @lookup_calls << [:mx, hostname, Thread.current.object_id]
    sleep(@lookup_delays[hostname]) if @lookup_delays[hostname]
    raise @lookup_errors[hostname] if @lookup_errors[hostname]
    ["mx.mock.com"]
  end
end

# Test strategy that returns exact expected values for successful records
# Used for error isolation tests where we need verified=true for non-erroring records
class ErrorIsolationStrategy < Onetime::DomainValidation::SenderStrategies::BaseStrategy
  attr_accessor :mock_records, :lookup_errors

  def initialize
    @mock_records = []
    @lookup_errors = {}
  end

  def required_dns_records(_mailer_config)
    @mock_records
  end

  def verify_dns_records(mailer_config)
    verify_all_records(mailer_config)
  end

  def strategy_name
    'error_isolation'
  end

  private

  # Return the expected value from the record for successful lookups
  def lookup_cname_records(hostname, resolver: nil, bypass_cache: false)
    raise @lookup_errors[hostname] if @lookup_errors[hostname]
    # Find the record for this hostname and return its expected value
    record = @mock_records.find { |r| r[:host] == hostname }
    record ? [record[:value]] : []
  end
end

# Test strategy that tracks bypass_cache parameter (for #2841 verification)
class BypassCacheTrackingStrategy < Onetime::DomainValidation::SenderStrategies::BaseStrategy
  attr_accessor :mock_records
  attr_reader :bypass_cache_calls

  def initialize
    @mock_records = []
    @bypass_cache_calls = []
  end

  def required_dns_records(_mailer_config)
    @mock_records
  end

  def verify_dns_records(mailer_config, bypass_cache: false)
    verify_all_records(mailer_config, bypass_cache: bypass_cache)
  end

  def strategy_name
    'bypass_cache_tracking'
  end

  private

  def lookup_cname_records(hostname, resolver: nil, bypass_cache: false)
    @bypass_cache_calls << { hostname: hostname, bypass_cache: bypass_cache }
    ['target.example.com']
  end
end

# Setup shared fixtures
@mock_custom_domain = Struct.new(:display_domain, :identifier).new(
  'parallel.example.com', 'cd:parallel123'
)
@mock_mailer_config = Struct.new(:custom_domain, :domain_id, :provider).new(
  @mock_custom_domain, 'cd:parallel123', 'ses'
)

# Pre-run setup for all tests
@strategy = TestableParallelStrategy.new
@strategy.mock_records = [
  { type: 'CNAME', host: 'sel1._domainkey.parallel.example.com', value: 'sel1.dkim.amazonses.com', purpose: 'DKIM 1' },
  { type: 'CNAME', host: 'sel2._domainkey.parallel.example.com', value: 'sel2.dkim.amazonses.com', purpose: 'DKIM 2' },
  { type: 'CNAME', host: 'sel3._domainkey.parallel.example.com', value: 'sel3.dkim.amazonses.com', purpose: 'DKIM 3' },
  { type: 'TXT', host: 'parallel.example.com', value: 'v=spf1 include:amazonses.com ~all', purpose: 'SPF' },
  { type: 'MX', host: 'parallel.example.com', value: 'inbound-smtp.us-east-1.amazonaws.com', purpose: 'MX' },
]
@results = @strategy.verify_dns_records(@mock_mailer_config)

# Pre-setup error isolation tests
@error_strategy = ErrorIsolationStrategy.new
@error_strategy.mock_records = [
  { type: 'CNAME', host: 'good1.example.com', value: 'target1.com', purpose: 'Record 1' },
  { type: 'CNAME', host: 'bad.example.com', value: 'target2.com', purpose: 'Record 2 (fails)' },
  { type: 'CNAME', host: 'good2.example.com', value: 'target3.com', purpose: 'Record 3' },
]
@error_strategy.lookup_errors = {
  'bad.example.com' => Resolv::ResolvError.new('DNS query failed'),
}
@error_results = @error_strategy.verify_dns_records(@mock_mailer_config)

## verify_all_records returns same number of results as input records
@results.size
#=> 5

## Results preserve original record order (DKIM 1 first)
@results.first[:purpose]
#=> 'DKIM 1'

## Results preserve original record order (MX last)
@results.last[:purpose]
#=> 'MX'

## Each result has required keys
@required_keys = [:type, :host, :expected, :actual, :verified, :purpose]
@results.all? { |r| @required_keys.all? { |k| r.key?(k) } }
#=> true

## Result type matches input record type
@results.map { |r| r[:type] }
#=> ['CNAME', 'CNAME', 'CNAME', 'TXT', 'MX']

## Successful lookup populates :actual with non-empty array
@results.first[:actual].is_a?(Array) && !@results.first[:actual].empty?
#=> true

## Error isolation: all 3 results returned despite one failure
@error_results.size
#=> 3

## Error isolation: first record verified successfully
@error_results[0][:verified]
#=> true

## Error isolation: failed record has verified=false
@error_results[1][:verified]
#=> false

## Error isolation: failed record has :error key
@error_results[1].key?(:error)
#=> true

## Error isolation: error message captured in failed record
@error_results[1][:error].include?('DNS query failed')
#=> true

## Error isolation: third record verified successfully despite prior failure
@error_results[2][:verified]
#=> true

## Error isolation: failed record actual is empty array
@error_results[1][:actual]
#=> []

## Parallel execution is faster than sequential (within 2x single lookup time)
@timed_strategy = TestableParallelStrategy.new
@timed_strategy.mock_records = [
  { type: 'CNAME', host: 'slow1.example.com', value: 'target.com', purpose: 'Slow 1' },
  { type: 'CNAME', host: 'slow2.example.com', value: 'target.com', purpose: 'Slow 2' },
  { type: 'CNAME', host: 'slow3.example.com', value: 'target.com', purpose: 'Slow 3' },
]
@timed_strategy.lookup_delays = {
  'slow1.example.com' => 0.1,
  'slow2.example.com' => 0.1,
  'slow3.example.com' => 0.1,
}
@start = Time.now
@timed_results = @timed_strategy.verify_dns_records(@mock_mailer_config)
@duration = Time.now - @start
# Sequential would be ~0.3s, parallel should be ~0.1s; allow 0.25s tolerance
@duration < 0.25
#=> true

## Parallel timing: all results returned
@timed_results.size
#=> 3

## Mixed timing: total time dominated by slowest
@mixed_strategy = TestableParallelStrategy.new
@mixed_strategy.mock_records = [
  { type: 'CNAME', host: 'fast1.example.com', value: 'target.com', purpose: 'Fast 1' },
  { type: 'CNAME', host: 'slow.example.com', value: 'target.com', purpose: 'Slow' },
  { type: 'CNAME', host: 'fast2.example.com', value: 'target.com', purpose: 'Fast 2' },
]
@mixed_strategy.lookup_delays = { 'slow.example.com' => 0.15 }
@start_mixed = Time.now
@mixed_results = @mixed_strategy.verify_dns_records(@mock_mailer_config)
@duration_mixed = Time.now - @start_mixed
@duration_mixed < 0.25
#=> true

## Mixed timing: results in original order despite timing differences
@mixed_results.map { |r| r[:purpose] }
#=> ['Fast 1', 'Slow', 'Fast 2']

## Empty records array returns empty results
@empty_strategy = TestableParallelStrategy.new
@empty_strategy.mock_records = []
@empty_strategy.verify_dns_records(@mock_mailer_config)
#=> []

## Single record works correctly
@single_strategy = TestableParallelStrategy.new
@single_strategy.mock_records = [
  { type: 'TXT', host: 'single.example.com', value: 'v=spf1', purpose: 'Single' },
]
@single_results = @single_strategy.verify_dns_records(@mock_mailer_config)
@single_results.size
#=> 1

## Single record result has correct purpose
@single_results.first[:purpose]
#=> 'Single'

## All-fail: all results returned
@all_fail_strategy = TestableParallelStrategy.new
@all_fail_strategy.mock_records = [
  { type: 'CNAME', host: 'fail1.example.com', value: 'target.com', purpose: 'Fail 1' },
  { type: 'CNAME', host: 'fail2.example.com', value: 'target.com', purpose: 'Fail 2' },
]
@all_fail_strategy.lookup_errors = {
  'fail1.example.com' => Resolv::ResolvTimeout.new('Timeout'),
  'fail2.example.com' => Resolv::ResolvError.new('NXDOMAIN'),
}
@all_fail_results = @all_fail_strategy.verify_dns_records(@mock_mailer_config)
@all_fail_results.size
#=> 2

## All-fail: all have verified=false
@all_fail_results.all? { |r| r[:verified] == false }
#=> true

## All-fail: all have error messages
@all_fail_results.all? { |r| r[:error].is_a?(String) && !r[:error].empty? }
#=> true

## All-fail: first error is Timeout
@all_fail_results[0][:error].include?('Timeout')
#=> true

## All-fail: second error is NXDOMAIN
@all_fail_results[1][:error].include?('NXDOMAIN')
#=> true

# --- bypass_cache propagation through verify_all_records (#2841 fix) ---

## verify_all_records with bypass_cache: false passes false to lookup methods
@bypass_strategy = BypassCacheTrackingStrategy.new
@bypass_strategy.mock_records = [
  { type: 'CNAME', host: 'record1.example.com', value: 'target.example.com', purpose: 'Record 1' },
  { type: 'CNAME', host: 'record2.example.com', value: 'target.example.com', purpose: 'Record 2' },
]
@bypass_strategy.verify_dns_records(@mock_mailer_config, bypass_cache: false)
@bypass_strategy.bypass_cache_calls.all? { |c| c[:bypass_cache] == false }
#=> true

## verify_all_records with bypass_cache: true passes true to lookup methods
@bypass_strategy = BypassCacheTrackingStrategy.new
@bypass_strategy.mock_records = [
  { type: 'CNAME', host: 'record1.example.com', value: 'target.example.com', purpose: 'Record 1' },
  { type: 'CNAME', host: 'record2.example.com', value: 'target.example.com', purpose: 'Record 2' },
]
@bypass_strategy.verify_dns_records(@mock_mailer_config, bypass_cache: true)
@bypass_strategy.bypass_cache_calls.all? { |c| c[:bypass_cache] == true }
#=> true

## All records receive the bypass_cache parameter (2 records total)
@bypass_strategy = BypassCacheTrackingStrategy.new
@bypass_strategy.mock_records = [
  { type: 'CNAME', host: 'record1.example.com', value: 'target.example.com', purpose: 'Record 1' },
  { type: 'CNAME', host: 'record2.example.com', value: 'target.example.com', purpose: 'Record 2' },
]
@bypass_strategy.verify_dns_records(@mock_mailer_config, bypass_cache: true)
@bypass_strategy.bypass_cache_calls.size
#=> 2

# No Redis teardown needed for this test
