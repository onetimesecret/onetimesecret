# try/unit/operations/validate_sender_domain_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Operations::ValidateSenderDomain
#
# Validates:
# 1. Operation with mock strategy returns correct Result
# 2. Result is immutable (Data.define)
# 3. Result has all expected fields
# 4. success? semantics (true when no error, even if DNS fails)
# 5. Error handling: operation rescues strategy errors gracefully
# 6. required_records class method
# 7. Status transitions: verified vs failed
# 8. persist: false prevents model writes

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/validate_sender_domain'

# Mock sender strategy that returns configurable verification results
# without making real DNS lookups.
class MockSenderStrategy
  attr_accessor :records, :verify_results

  def initialize(all_verified: true, record_count: 3)
    domain = 'mock.example.com'
    @records = record_count.times.map do |i|
      {
        type: 'CNAME',
        host: "selector#{i + 1}._domainkey.#{domain}",
        value: "selector#{i + 1}.dkim.provider.com",
        purpose: "DKIM signature #{i + 1} of #{record_count}",
      }
    end

    @verify_results = @records.map do |r|
      {
        type: r[:type],
        host: r[:host],
        expected: r[:value],
        actual: all_verified ? [r[:value]] : [],
        verified: all_verified,
        purpose: r[:purpose],
      }
    end
  end

  def required_dns_records(_mailer_config)
    @records
  end

  def verify_dns_records(_mailer_config)
    @verify_results
  end

  def strategy_name
    'mock'
  end
end

# Strategy that raises during verification to test error handling
class ExplodingSenderStrategy
  def required_dns_records(_mailer_config)
    raise StandardError, 'DNS provider unreachable'
  end

  def verify_dns_records(_mailer_config)
    raise StandardError, 'DNS provider unreachable'
  end

  def strategy_name
    'exploding'
  end
end

# Setup test fixtures
@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "vsd_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("VSD Test Org #{@timestamp}", @owner, "vsd_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("vsd-test-#{@timestamp}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Test Sender',
  from_address: "noreply@vsd-test-#{@timestamp}.example.com",
)

# Pre-build mock strategies in setup
@mock_all_pass = MockSenderStrategy.new(all_verified: true)
@mock_all_fail = MockSenderStrategy.new(all_verified: false, record_count: 4)
@exploding = ExplodingSenderStrategy.new

# Pre-run the three primary operations in setup so results are available
@result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: @config,
  strategy: @mock_all_pass,
  persist: false,
).call

@fail_result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: @config,
  strategy: @mock_all_fail,
  persist: false,
).call

@error_result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: @config,
  strategy: @exploding,
  persist: false,
).call

# --- Result is a Data.define ---

## Result class is a Data subclass
Onetime::Operations::ValidateSenderDomain::Result.ancestors.include?(Data)
#=> true

## Result instances are frozen (immutable)
@result.frozen?
#=> true

# --- All-pass verification ---

## Result has domain field matching the custom domain
@result.domain
#=> @domain.display_domain

## Result has provider field
@result.provider
#=> 'ses'

## Result dns_records is an array with 3 entries
@result.dns_records.size
#=> 3

## Result all_verified is true when all records pass
@result.all_verified
#=> true

## Result verification_status is 'verified' when all pass
@result.verification_status
#=> 'verified'

## Result verified_at is a Time when all pass
@result.verified_at.is_a?(Time)
#=> true

## Result error is nil on success
@result.error
#=> nil

## success? is true when no exception occurred
@result.success?
#=> true

## Result persisted is false when persist: false
@result.persisted
#=> false

# --- Failed verification (some records fail) ---

## Failed verification: all_verified is false
@fail_result.all_verified
#=> false

## Failed verification: verification_status is 'failed'
@fail_result.verification_status
#=> 'failed'

## Failed verification: verified_at is nil
@fail_result.verified_at
#=> nil

## Failed verification: success? is still true (no exception)
@fail_result.success?
#=> true

## Failed verification: dns_records has 4 entries from mock
@fail_result.dns_records.size
#=> 4

## Failed verification: each record has verified: false
@fail_result.dns_records.all? { |r| r[:verified] == false }
#=> true

# --- Error handling: strategy raises exception ---

## Error result: success? is false when exception occurred
@error_result.success?
#=> false

## Error result: error contains the exception message
@error_result.error
#=> 'DNS provider unreachable'

## Error result: all_verified is false
@error_result.all_verified
#=> false

## Error result: verification_status is 'failed'
@error_result.verification_status
#=> 'failed'

## Error result: dns_records is empty array
@error_result.dns_records
#=> []

## Error result: persisted is false
@error_result.persisted
#=> false

# --- Persistence: verified ---

## Persistence: persisted is true and status becomes verified
@config.verification_status = 'pending'
@config.verified_at = nil
@config.save
@persist_result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: @config,
  strategy: MockSenderStrategy.new(all_verified: true),
  persist: true,
).call
@persist_result.persisted
#=> true

## Persistence: mailer_config verification_status updated to 'verified'
@reloaded = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded.verification_status
#=> 'verified'

## Persistence: mailer_config verified_at is set (non-empty)
@reloaded.verified_at.to_s.empty?
#=> false

# --- Persistence on failure ---

## Failed persist: verification_status updated to 'failed'
@config.verification_status = 'pending'
@config.verified_at = nil
@config.save
@fail_persist_result = Onetime::Operations::ValidateSenderDomain.new(
  mailer_config: @config,
  strategy: MockSenderStrategy.new(all_verified: false),
  persist: true,
).call
@reloaded_fail = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded_fail.verification_status
#=> 'failed'

## Failed persist: verified_at remains empty
@reloaded_fail.verified_at.to_s.empty?
#=> true

# --- required_records class method ---

## required_records returns array of DNS record hashes
@req_records = Onetime::Operations::ValidateSenderDomain.required_records(
  mailer_config: @config,
  strategy: @mock_all_pass,
)
@req_records.is_a?(Array)
#=> true

## required_records returns records with correct keys
@required_keys = [:type, :host, :value, :purpose]
Onetime::Operations::ValidateSenderDomain.required_records(
  mailer_config: @config,
  strategy: @mock_all_pass,
).all? { |r| @required_keys.all? { |k| r.key?(k) } }
#=> true

## required_records returns 3 records from mock strategy
Onetime::Operations::ValidateSenderDomain.required_records(
  mailer_config: @config,
  strategy: @mock_all_pass,
).size
#=> 3

# --- Result to_h ---

## to_h returns a Hash
@result.to_h.is_a?(Hash)
#=> true

## to_h contains all expected keys
@expected_keys = [:domain, :provider, :dns_records, :all_verified,
                  :verification_status, :verified_at, :persisted, :error]
(@expected_keys - @result.to_h.keys).empty?
#=> true

## to_h verified_at is ISO 8601 string when present
@result.to_h[:verified_at].is_a?(String) && @result.to_h[:verified_at].match?(/\d{4}-\d{2}-\d{2}T/)
#=> true

## to_h verified_at is nil when verification failed
@fail_result.to_h[:verified_at]
#=> nil

# Teardown
Familia.dbclient.flushdb
