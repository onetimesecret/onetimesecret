# try/billing/self_healing_workspace_try.rb
#
# frozen_string_literal: true

#
# Billing Self-Healing Workspace Test Suite
#

# Setup - Load the real application
ENV['RACK_ENV'] = 'test'
ENV['AUTHENTICATION_MODE'] = 'basic'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '..', '..')).freeze

require_relative '../support/test_helpers'

require 'onetime'

OT.boot! :test, false

require_relative '../../apps/web/auth/operations/create_default_workspace'
require_relative '../../apps/web/billing/controllers/billing'

# Setup: Create test customer
@customer = Onetime::Customer.create!(email: "selfheal_#{Familia.now.to_i}@example.com")
@customer.verified = true
@customer.role = :customer

## Can detect when customer has no organizations
@customer.organization_instances.empty?
#=> true

## Can check CreateDefaultWorkspace operation directly
result = Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
@org = result[:organization]
@team = result[:team]
[@org.class.name, @team.class.name]
#=> ['Onetime::Organization', 'Onetime::Team']

## Verifies organization is marked as default
@org.is_default
#=> true

## Verifies team is marked as default
@team.is_default
#=> true

## Verifies customer now has organization
@customer.organization_instances.any?
#=> true

## Verifies workspace creation is idempotent (doesn't create duplicates)
before_count = @customer.organization_instances.size
Auth::Operations::CreateDefaultWorkspace.new(customer: @customer).call
after_count = @customer.organization_instances.size
before_count == after_count
#=> true

# Teardown
begin
  # Clean up test data
  @team.delete! if @team
  @org.delete! if @org
  @customer.delete! if @customer
rescue => e
  puts "Cleanup error (non-fatal): #{e.message}"
end
