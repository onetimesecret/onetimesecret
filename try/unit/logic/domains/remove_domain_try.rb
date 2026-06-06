# try/unit/logic/domains/remove_domain_try.rb
#
# frozen_string_literal: true

# Tests for RemoveDomain#delete_sender_domain
#
# The method loads mailer_config from the custom domain, checks if the
# effective provider is 'lettermint', calls strategy.delete_sender_identity,
# and swallows any errors so domain removal always proceeds.
#
# Covers:
#   1. No mailer_config -> strategy never called
#   2. Provider != 'lettermint' -> strategy never called
#   3. Provider == 'lettermint' -> delete_sender_identity called once
#   4. Strategy raises StandardError -> error swallowed, no propagation
#
# Run:
#   try try/unit/logic/domains/remove_domain_try.rb --agent

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

# Helper to build a RemoveDomain instance wired to a specific domain
def build_remove_domain(domain, spy)
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

  [logic, original_for_provider, original_provider_creds]
end

def restore_stubs(original_for_provider, original_provider_creds)
  Onetime::Mail::SenderStrategies.define_singleton_method(:for_provider, original_for_provider)
  Onetime::Mail::Mailer.define_singleton_method(:provider_credentials, original_provider_creds)
end

# ===================================================================
# Case 1: No mailer_config -> strategy never called
# ===================================================================

## delete_sender_domain does nothing when domain has no mailer_config
@domain_1 = Onetime::CustomDomain.create!("rd-no-mc-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@spy_1 = SpySenderStrategy.new
@logic_1, @ofp_1, @opc_1 = build_remove_domain(@domain_1, @spy_1)
@logic_1.send(:delete_sender_domain)
restore_stubs(@ofp_1, @opc_1)
@spy_1.delete_calls.size
#=> 0

# ===================================================================
# Case 2: Provider != 'lettermint' -> strategy never called
# ===================================================================

## delete_sender_domain skips non-lettermint providers
@domain_2 = Onetime::CustomDomain.create!("rd-ses-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_2 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_2.identifier,
  from_address: "noreply@rd-ses-#{@timestamp}.example.com",
  provider: 'ses',
)
@spy_2 = SpySenderStrategy.new
@logic_2, @ofp_2, @opc_2 = build_remove_domain(@domain_2, @spy_2)
@logic_2.send(:delete_sender_domain)
restore_stubs(@ofp_2, @opc_2)
@spy_2.delete_calls.size
#=> 0

# ===================================================================
# Case 3: Provider == 'lettermint' -> delete_sender_identity called
# ===================================================================

## delete_sender_domain calls strategy for lettermint provider
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
@logic_3, @ofp_3, @opc_3 = build_remove_domain(@domain_3, @spy_3)
@logic_3.send(:delete_sender_domain)
restore_stubs(@ofp_3, @opc_3)
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

## delete_sender_domain swallows StandardError from strategy
@domain_4 = Onetime::CustomDomain.create!("rd-err-#{@timestamp}-#{@entropy}.example.com", @org.objid)
@mc_4 = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain_4.identifier,
  from_address: "noreply@rd-err-#{@timestamp}.example.com",
  provider: 'lettermint',
)
@spy_4 = SpySenderStrategy.new(should_raise: true)
@logic_4, @ofp_4, @opc_4 = build_remove_domain(@domain_4, @spy_4)
result = begin
  @logic_4.send(:delete_sender_domain)
  :no_error
rescue StandardError
  :error_raised
end
restore_stubs(@ofp_4, @opc_4)
result
#=> :no_error

## Strategy was still called before the error
@spy_4.delete_calls.size
#=> 1

# --- Cleanup ---
Familia.dbclient.flushdb
OT.info "Cleaned Redis after RemoveDomain test run"
