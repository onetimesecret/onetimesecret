# try/unit/logic/account/get_permissions_try.rb
#
# frozen_string_literal: true

#
# Tests for GetPermissions logic class.
#
# Tests cover:
# 1. Bulk mode - returns all orgs with memberships and domain permissions
# 2. Single-resource mode - returns permissions for specific domain/org
# 3. Role-based permission calculation
# 4. Error cases (not found, not member)

require_relative '../../../support/test_logic'
require 'securerandom'

OT.boot! :test, false

# Helper to create unique identifiers
@unique_id = -> { SecureRandom.hex(8) }
@unique_email = -> { "test_#{SecureRandom.uuid}@example.com" }

# Setup: Create owner, org, and domain
@owner = Onetime::Customer.new(email: @unique_email.call)
@owner.save

@org = Onetime::Organization.create!("Test Org #{@unique_id.call}", @owner, @owner.email)
@org.save

@domain = Onetime::CustomDomain.new
@domain.display_domain = "test-#{@unique_id.call}.example.com"
@domain.org_id = @org.objid
@domain.save
@org.domains.add(@domain.objid)

# Helper to create authenticated strategy result
def create_auth_result(customer)
  Otto::Security::Authentication::StrategyResult.new(
    session: { 'authenticated' => true, 'external_id' => customer.extid },
    user: customer,
    auth_method: 'sessionauth',
    strategy_name: 'sessionauth',
    metadata: { ip: '127.0.0.1' }
  )
end

## Bulk mode: Owner sees org with owner permissions
@auth_result = create_auth_result(@owner)
@params = {}
@logic = AccountAPI::Logic::Account::GetPermissions.new(@auth_result, @params, 'en')
@logic.process_params
@logic.raise_concerns
@result = @logic.process
[
  @result[:organizations].length >= 1,
  @result[:organizations].any? { |o| o[:extid] == @org.extid },
]
#=> [true, true]

## Bulk mode: Owner has correct permissions on their org
@org_data = @result[:organizations].find { |o| o[:extid] == @org.extid }
[
  @org_data[:membership][:role],
  @org_data[:permissions][:can_view],
  @org_data[:permissions][:can_edit],
  @org_data[:permissions][:can_manage_settings],
]
#=> ['owner', true, true, true]

## Bulk mode: Domains included with permissions
@org_data[:domains].any? { |d| d[:extid] == @domain.extid }
#=> true

## Single-resource mode: Domain lookup returns correct org
@params2 = { 'resource_type' => 'domain', 'resource_id' => @domain.extid }
@logic2 = AccountAPI::Logic::Account::GetPermissions.new(@auth_result, @params2, 'en')
@logic2.process_params
@logic2.raise_concerns
@result2 = @logic2.process
[
  @result2[:resource_type],
  @result2[:organization][:extid],
  @result2[:permissions][:can_view],
]
#=> ['domain', @org.extid, true]

## Single-resource mode: Org lookup works
@params3 = { 'resource_type' => 'organization', 'resource_id' => @org.extid }
@logic3 = AccountAPI::Logic::Account::GetPermissions.new(@auth_result, @params3, 'en')
@logic3.process_params
@logic3.raise_concerns
@result3 = @logic3.process
[
  @result3[:resource_type],
  @result3[:membership][:role],
]
#=> ['organization', 'owner']

## Member role: Create member with limited permissions
@member = Onetime::Customer.new(email: @unique_email.call)
@member.save
@membership = @org.add_members_instance(@member, through_attrs: { role: 'member', status: 'active' })
@membership.materialize_for_role!(@org)

@member_auth = create_auth_result(@member)
@params4 = { 'resource_type' => 'domain', 'resource_id' => @domain.extid }
@logic4 = AccountAPI::Logic::Account::GetPermissions.new(@member_auth, @params4, 'en')
@logic4.process_params
@logic4.raise_concerns
@result4 = @logic4.process
[
  @result4[:membership][:role],
  @result4[:permissions][:can_view],
  @result4[:permissions][:can_edit],
  @result4[:permissions][:can_manage_settings],
]
#=> ['member', true, false, false]

## Non-member cannot access domain
@outsider = Onetime::Customer.new(email: @unique_email.call)
@outsider.save
@outsider_auth = create_auth_result(@outsider)
@params5 = { 'resource_type' => 'domain', 'resource_id' => @domain.extid }
@logic5 = AccountAPI::Logic::Account::GetPermissions.new(@outsider_auth, @params5, 'en')
@logic5.process_params
begin
  @logic5.raise_concerns
  'no_error'
rescue OT::Unauthorized => e
  e.message
end
#=> 'You are not a member of this organization'

## Invalid resource_type rejected
@params6 = { 'resource_type' => 'secret', 'resource_id' => 'abc123' }
@logic6 = AccountAPI::Logic::Account::GetPermissions.new(@auth_result, @params6, 'en')
@logic6.process_params
begin
  @logic6.raise_concerns
  'no_error'
rescue OT::FormError => e
  e.message.include?('resource_type must be one of')
end
#=> true

## Domain not found
@params7 = { 'resource_type' => 'domain', 'resource_id' => 'nonexistent123' }
@logic7 = AccountAPI::Logic::Account::GetPermissions.new(@auth_result, @params7, 'en')
@logic7.process_params
begin
  @logic7.raise_concerns
  'no_error'
rescue OT::Problem => e
  e.message
end
#=> 'Domain not found'
