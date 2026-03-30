# try/unit/operations/provision_sender_domain_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Operations::ProvisionSenderDomain
#
# Validates:
# 1. Operation returns success Result when strategy succeeds
# 2. Extracts dns_records correctly from strategy (normalized for display)
# 3. Extracts provider_data correctly from strategy (raw response)
# 4. Persists both provider_dns_data AND dns_records to mailer_config
# 5. Does not persist when persist=false
# 6. Returns failure when mailer_config is nil
# 7. Returns failure when provider is empty
# 8. Returns failure for unsupported provider (smtp)
# 9. Handles SES provider (Array dns_records from dkim_tokens)
# 10. Handles SendGrid provider (Array dns_records)
# 11. Handles Lettermint provider (Hash dns_records)
# 12. Wraps errors in failure result

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/operations/provision_sender_domain'

# Mock sender strategy that returns configurable provisioning results
# without making real provider API calls.
#
# The strategy interface returns:
#   - success: true/false
#   - message: Human-readable status message
#   - dns_records: Array of normalized DNS records for UI display
#   - provider_data: Hash of raw provider response for storage
#   - identity_id: Provider's identity ID (optional)
#
class MockProvisionStrategy
  attr_accessor :provision_result

  def initialize(success: true, dns_records: nil, provider_data: nil, error_message: nil, identity_id: nil)
    # Default SES-style response
    default_dns_records = [
      { type: 'CNAME', name: 'token1._domainkey.example.com', value: 'token1.dkim.amazonses.com' },
      { type: 'CNAME', name: 'token2._domainkey.example.com', value: 'token2.dkim.amazonses.com' },
      { type: 'CNAME', name: 'token3._domainkey.example.com', value: 'token3.dkim.amazonses.com' },
    ]
    default_provider_data = {
      dkim_tokens: %w[token1 token2 token3],
      region: 'us-east-1',
      identity: 'example.com',
      dkim_status: 'PENDING',
    }

    @provision_result = if success
      {
        success: true,
        message: 'Provisioned sender identity',
        dns_records: dns_records || default_dns_records,
        provider_data: provider_data || default_provider_data,
        identity_id: identity_id || 'test-identity-123',
      }
    else
      {
        success: false,
        error: error_message || 'Provisioning failed',
        dns_records: [],
        provider_data: nil,
      }
    end
  end

  def provision_dns_records(_mailer_config, credentials:)
    @provision_result
  end

  def strategy_name
    'mock'
  end
end

# Strategy that raises during provisioning to test error handling
class ExplodingProvisionStrategy
  def provision_dns_records(_mailer_config, credentials:)
    raise StandardError, 'Provider API connection failed'
  end

  def strategy_name
    'exploding'
  end
end

# Strategy for NotImplementedError testing
class UnimplementedProvisionStrategy
  def provision_dns_records(_mailer_config, credentials:)
    raise NotImplementedError, 'Provisioning not supported for this provider'
  end

  def strategy_name
    'unimplemented'
  end
end

# Setup test fixtures
@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "psd_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("PSD Test Org #{@timestamp}", @owner, "psd_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("psd-test-#{@timestamp}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Test Sender',
  from_address: "noreply@psd-test-#{@timestamp}.example.com",
  api_key: 'test-api-key-value',
)

# Pre-build mock strategies in setup
@mock_success = MockProvisionStrategy.new(success: true)
@mock_failure = MockProvisionStrategy.new(success: false, error_message: 'DKIM limit exceeded')
@exploding = ExplodingProvisionStrategy.new
@unimplemented = UnimplementedProvisionStrategy.new

# Mock credentials loading at the operation level
# We patch the instance method to avoid needing Mailer module loaded
class Onetime::Operations::ProvisionSenderDomain
  private

  def load_credentials(_provider)
    { api_key: 'mock-platform-credentials', region: 'us-east-1' }
  end
end

# --- Result is a Data.define ---

## Result class is a Data subclass
Onetime::Operations::ProvisionSenderDomain::Result.ancestors.include?(Data)
#=> true

## Result instances are frozen (immutable)
@result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @config,
  strategy: @mock_success,
  persist: false,
).call
@result.frozen?
#=> true

# --- Success Result structure ---

## Result success? returns true when strategy succeeds
@result.success?
#=> true

## Result failed? returns false when strategy succeeds
@result.failed?
#=> false

## Result error is nil on success
@result.error
#=> nil

## Result dns_records is an array (normalized for display)
@result.dns_records.is_a?(Array)
#=> true

## Result dns_records contains CNAME records from SES normalization
@result.dns_records.all? { |r| r[:type] == 'CNAME' }
#=> true

## Result provider_data contains raw provider response (regression for bug #1)
@result.provider_data.is_a?(Hash)
#=> true

## Result provider_data has dkim_tokens key (raw SES format)
@result.provider_data.key?(:dkim_tokens)
#=> true

# --- SES provider normalization (Array dns_records) ---

## SES dns_records have correct count (3 DKIM tokens)
@ses_dns_data = {
  dkim_tokens: %w[abc123 def456 ghi789],
  region: 'us-west-2',
}
@ses_strategy = MockProvisionStrategy.new(success: true, dns_records: @ses_dns_data)
@ses_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @config,
  strategy: @ses_strategy,
  persist: false,
).call
@ses_result.dns_records.size
#=> 3

## SES dns_records have CNAME type
@ses_result.dns_records.first[:type]
#=> 'CNAME'

## SES dns_records name includes _domainkey suffix
@ses_result.dns_records.first[:name].include?('_domainkey')
#=> true

## SES dns_records value ends with dkim.amazonses.com
@ses_result.dns_records.first[:value].end_with?('.dkim.amazonses.com')
#=> true

# --- SendGrid provider normalization (Array dns_records) ---

## SendGrid dns_records passthrough when dns_records array present
# Actual SendGrid strategy returns Array directly in :dns_records
@sendgrid_dns_data = [
  { type: 'CNAME', name: 'em1234.example.com', value: 'u1234.wl.sendgrid.net' },
  { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none' },
]
@sendgrid_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_sendgrid',
  provider: 'sendgrid',
  from_address: "noreply@sendgrid-#{@timestamp}.example.com",
  api_key: 'sendgrid-api-key',
)
# Mock strategy returns Array directly like actual SendGrid strategy
@sendgrid_strategy = MockProvisionStrategy.new(success: true, dns_records: @sendgrid_dns_data)

# Manually test the normalization logic via the operation
# First, stub the supports_provisioning? for our config's provider
allow_provisioning = ->(provider) { %w[ses sendgrid lettermint].include?(provider.to_s.downcase) }
Onetime::Mail::SenderStrategies.define_singleton_method(:supports_provisioning?, allow_provisioning)

# SendGrid strategy returns Array directly, operation passes through
@sendgrid_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @sendgrid_config,
  strategy: @sendgrid_strategy,
  persist: false,
).call
@sendgrid_result.dns_records.size
#=> 2

# --- Lettermint provider normalization (Hash dns_records) ---

## Lettermint dns_records from records key
@lettermint_dns_data = {
  records: [
    { type: 'CNAME', name: 'sel1._domainkey.example.com', value: 'sel1.dkim.lettermint.io' },
  ],
}
@lettermint_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_lettermint',
  provider: 'lettermint',
  from_address: "noreply@lettermint-#{@timestamp}.example.com",
  api_key: 'lettermint-api-key',
)
@lettermint_strategy = MockProvisionStrategy.new(success: true, dns_records: @lettermint_dns_data)
@lettermint_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @lettermint_config,
  strategy: @lettermint_strategy,
  persist: false,
).call
@lettermint_result.dns_records.size
#=> 1

# --- Persistence behavior ---

## persist: false does NOT save provider_dns_data
@no_persist_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_nopersist',
  provider: 'ses',
  from_address: "nopersist-#{@timestamp}@example.com",
  api_key: 'nopersist-key',
)
@no_persist_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @no_persist_config,
  strategy: @mock_success,
  persist: false,
).call
# Reload and check provider_dns_data is empty
@reloaded_no_persist = Onetime::CustomDomain::MailerConfig.load(@no_persist_config.identifier)
@reloaded_no_persist.provider_dns_data&.value.to_a.empty? || @reloaded_no_persist.provider_dns_data.nil?
#=> true

## persist: true DOES save provider_dns_data to mailer_config
@persist_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_persist',
  provider: 'ses',
  from_address: "persist-#{@timestamp}@example.com",
  api_key: 'persist-key',
)
@persist_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @persist_config,
  strategy: @mock_success,
  persist: true,
).call
# Reload and check provider_dns_data is populated
@reloaded_persist = Onetime::CustomDomain::MailerConfig.load(@persist_config.identifier)
@reloaded_persist.provider_dns_data&.value.is_a?(Hash)
#=> true

## persist: true saves dkim_tokens in provider_dns_data (jsonkey uses string keys)
data = @reloaded_persist.provider_dns_data.value
(data[:dkim_tokens] || data['dkim_tokens']).is_a?(Array)
#=> true

## persist: true saves dns_records jsonkey as Array with records
@reloaded_persist.dns_records.value.is_a?(Array)
#=> true

## persist: true dns_records contains expected number of records
@reloaded_persist.dns_records.value.size
#=> 3

# --- Normalization of nil dns_records ---

## Strategy returning dns_records: nil produces empty array in result
@nil_dns_strategy = MockProvisionStrategy.new(success: true)
@nil_dns_strategy.provision_result[:dns_records] = nil
@nil_dns_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_nildns',
  provider: 'ses',
  from_address: "nildns-#{@timestamp}@example.com",
  api_key: 'nildns-key',
)
@nil_dns_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @nil_dns_config,
  strategy: @nil_dns_strategy,
  persist: false,
).call
@nil_dns_result.dns_records
#=> []

# --- Failure conditions ---

## Returns failure when mailer_config is nil
@nil_config_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: nil,
  strategy: @mock_success,
  persist: false,
).call
@nil_config_result.success?
#=> false

## Nil mailer_config error message is descriptive
@nil_config_result.error
#=> 'mailer_config is required'

## Returns failure when provider is empty
@empty_provider_config = Onetime::CustomDomain::MailerConfig.new(
  domain_id: @domain.identifier + '_emptyprovider',
)
@empty_provider_config.provider = ''
@empty_provider_config.from_address = "empty-provider-#{@timestamp}@example.com"
@empty_provider_config.save
@empty_provider_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @empty_provider_config,
  strategy: @mock_success,
  persist: false,
).call
@empty_provider_result.success?
#=> false

## Empty provider error message mentions provider
@empty_provider_result.error.include?('provider')
#=> true

## Returns failure when from_address is empty
@empty_from_config = Onetime::CustomDomain::MailerConfig.new(
  domain_id: @domain.identifier + '_emptyfrom',
)
@empty_from_config.provider = 'ses'
@empty_from_config.from_address = ''
@empty_from_config.save
@empty_from_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @empty_from_config,
  strategy: @mock_success,
  persist: false,
).call
@empty_from_result.success?
#=> false

## Empty from_address error message mentions from_address
@empty_from_result.error.include?('from_address')
#=> true

## Returns failure for unsupported provider (smtp)
@smtp_config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier + '_smtp',
  provider: 'smtp',
  from_address: "smtp-#{@timestamp}@example.com",
  api_key: 'smtp-credentials',
)
@smtp_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @smtp_config,
  strategy: @mock_success,
  persist: false,
).call
@smtp_result.success?
#=> false

## SMTP failure message mentions manual DNS configuration
@smtp_result.error.include?('manually')
#=> true

# --- Strategy failure handling ---

## Returns failure when strategy returns success: false
@strategy_fail_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @config,
  strategy: @mock_failure,
  persist: false,
).call
@strategy_fail_result.success?
#=> false

## Strategy failure preserves error message
@strategy_fail_result.error
#=> 'DKIM limit exceeded'

## Strategy failure returns empty dns_records
@strategy_fail_result.dns_records
#=> []

## Strategy failure returns nil provider_data
@strategy_fail_result.provider_data
#=> nil

# --- Error handling: exceptions wrapped in Result ---

## StandardError is caught and wrapped in failure result
@error_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @config,
  strategy: @exploding,
  persist: false,
).call
@error_result.success?
#=> false

## StandardError message appears in error field
@error_result.error.include?('Provider API connection failed')
#=> true

## NotImplementedError is caught and wrapped in failure result
@not_impl_result = Onetime::Operations::ProvisionSenderDomain.new(
  mailer_config: @config,
  strategy: @unimplemented,
  persist: false,
).call
@not_impl_result.success?
#=> false

## NotImplementedError includes helpful message
@not_impl_result.error.include?('not yet implemented')
#=> true

# --- Result to_h ---

## to_h returns a Hash
@result.to_h.is_a?(Hash)
#=> true

## to_h contains all expected keys
@expected_keys = [:success, :dns_records, :provider_data, :error]
(@expected_keys - @result.to_h.keys).empty?
#=> true

## to_h success matches success?
@result.to_h[:success] == @result.success?
#=> true

# Teardown
Familia.dbclient.flushdb
