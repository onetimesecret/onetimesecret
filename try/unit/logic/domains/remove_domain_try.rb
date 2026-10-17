# try/unit/logic/domains/remove_domain_try.rb
#
# frozen_string_literal: true

# Tests for sender cleanup through RemoveDomain#process and shared teardown.
#
# Removal dispatches sender cleanup using the config's effective provider
# before destroying the domain, and proceeds when provider cleanup fails.
#
# Covers:
#   1. No mailer_config -> strategy never called
#   2. Non-lettermint provider (ses) -> delete_sender_identity dispatched
#   3. Provider == 'lettermint' -> delete_sender_identity called once
#   4. Strategy raises StandardError -> error swallowed, no propagation
#
# Run:
#   tests/lanes/run unit --only try/unit/logic/domains/remove_domain_try.rb

require_relative '../../../support/test_logic'
require 'securerandom'

OT.boot! :test

# Load DomainsAPI logic classes
require 'api/domains/logic/base'
require 'api/domains/logic/domains/remove_domain'
require 'onetime/mail/sender_strategies'

Familia.dbclient.flushdb
OT.info "Cleaned Redis for RemoveDomain test run"

@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# --- Spy strategy that records calls ---

class SpySenderStrategy
  attr_reader :delete_calls

  def initialize(should_raise: false)
    @delete_calls = []
    @should_raise = should_raise
  end

  def delete_sender_identity(mailer_config, credentials:)
    @delete_calls << { mailer_config: mailer_config, credentials: credentials }
    raise StandardError, 'Lettermint API timeout' if @should_raise

    { deleted: true, message: 'Domain deleted' }
  end

  def strategy_name
    'spy'
  end
end

# --- Test fixtures ---

@owner = Onetime::Customer.create!(email: "rd_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("RD Org #{@timestamp}", @owner, "rd_#{@timestamp}@test.com")

# Enable standalone mode so entitlements grant custom_domains
@org.define_singleton_method(:billing_enabled?) { false }
Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)&.materialize_for_role!(@org)

# Exercise public removal while isolating the external sender provider.
def remove_domain_with_spy(domain, spy)
  session = MockSession.new
  strategy_result = MockStrategyResult.new(
    session: session,
    user: @owner,
    metadata: { organization_context: { organization: @org } },
  )
  params = { 'extid' => domain.extid }
  logic = DomainsAPI::Logic::Domains::RemoveDomain.new(strategy_result, params)
  # Wire internal state directly (bypasses raise_concerns which needs HTTP context)
  logic.instance_variable_set(:@custom_domain, domain)
  logic.instance_variable_set(:@display_domain, domain.display_domain)
  logic.instance_variable_set(:@cust, @owner)

  # Stub SenderStrategies.for_provider to return the spy
  original_for_provider = Onetime::Mail::SenderStrategies.method(:for_provider)
  Onetime::Mail::SenderStrategies.define_singleton_method(:for_provider) do |provider, config = {}|
    spy
  end

  # Stub Mailer.provider_credentials to return fake credentials
  original_provider_creds = Onetime::Mail::Mailer.method(:provider_credentials)
  Onetime::Mail::Mailer.define_singleton_method(:provider_credentials) do |provider|
    { 'team_token' => 'fake-test-token' }
  end

  logic.process
ensure
  Onetime::Mail::SenderStrategies.define_singleton_method(:for_provider, original_for_provider) if original_for_provider
  Onetime::Mail::Mailer.define_singleton_method(:provider_credentials, original_provider_creds) if original_provider_creds
end

# ===================================================================
# Case 1: No mailer_config -> strategy never called
# ===================================================================

## Removal skips sender cleanup when domain has no mailer_config
@domain_1 = Onetime::CustomDomain.create!("rd-no-mc-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@spy_1 = SpySenderStrategy.new
remove_domain_with_spy(@domain_1, @spy_1)
@spy_1.delete_calls.size
#=> 0

# ===================================================================
# Case 2: Non-lettermint provider (ses) -> delete_sender_identity dispatched
# ===================================================================

## Removal dispatches sender deletion for non-lettermint providers
@domain_2 = Onetime::CustomDomain.create!("rd-ses-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_2 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_2.identifier,
  from_address: "noreply@rd-ses-#{@timestamp}.example.com",
  provider: 'ses',
)
@spy_2 = SpySenderStrategy.new
remove_domain_with_spy(@domain_2, @spy_2)
@spy_2.delete_calls.size
#=> 1

# ===================================================================
# Case 3: Provider == 'lettermint' -> delete_sender_identity called
# ===================================================================

## Sender config resolves the lettermint provider
@domain_3 = Onetime::CustomDomain.create!("rd-lm-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_3 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_3.identifier,
  from_address: "noreply@rd-lm-#{@timestamp}.example.com",
  provider: 'lettermint',
)
# Verify effective_provider resolves correctly
@mc_3.effective_provider
#=> 'lettermint'

## Strategy receives the mailer_config in the delete call
@spy_3 = SpySenderStrategy.new
remove_domain_with_spy(@domain_3, @spy_3)
@spy_3.delete_calls.size
#=> 1

## Strategy received correct mailer_config domain_id
@spy_3.delete_calls.first[:mailer_config].identifier
#=> @mc_3.identifier

## Strategy received credentials hash
@spy_3.delete_calls.first[:credentials].is_a?(Hash)
#=> true

# ===================================================================
# Case 4: Strategy raises -> error swallowed, no propagation
# ===================================================================

## Removal proceeds after StandardError from sender strategy
@domain_4 = Onetime::CustomDomain.create!("rd-err-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_4 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_4.identifier,
  from_address: "noreply@rd-err-#{@timestamp}.example.com",
  provider: 'lettermint',
)
@spy_4 = SpySenderStrategy.new(should_raise: true)
result = begin
  remove_domain_with_spy(@domain_4, @spy_4)
  :no_error
rescue StandardError
  :error_raised
end
result
#=> :no_error

## Strategy was still called before the error
@spy_4.delete_calls.size
#=> 1

## Domain destruction completes despite the provider error
@domain_4.exists?
#=> false

# --- Cleanup ---
Familia.dbclient.flushdb
OT.info "Cleaned Redis after RemoveDomain test run"
