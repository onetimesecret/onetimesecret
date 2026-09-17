# apps/web/auth/try/operations/ensure_default_workspace_try.rb
#
# frozen_string_literal: true

# EnsureDefaultWorkspace Operation Test Suite
#

# Setup - Load the real application
ENV['RACK_ENV']            = 'test'
ENV['AUTHENTICATION_MODE'] = 'simple'

require_relative '../../../../../try/support/test_helpers'

require 'onetime'

OT.boot! :test, false

require_relative '../../operations/ensure_default_workspace'
require_relative '../../../billing/controllers/billing'

# Setup: Create test customer
@customer          = Onetime::Customer.create!(email: generate_unique_test_email("selfheal"))
@customer.verified = true
@customer.role     = :customer

# Setup: a second org-less customer for the concurrent-creation case. Two
# callers race through the real Familia::Lock on Customer.org_creation_lock_key;
# without it the loser classified the winner's half-built org as a collision.
@racer          = Onetime::Customer.create!(email: generate_unique_test_email("racer"))
@racer.verified = true
@racer.role     = :customer

## Can detect when customer has no organizations
@customer.organization_instances.empty?
#=> true

## Can check EnsureDefaultWorkspace operation directly
result = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call
@org   = result[:organization]
@org.class.name
#=> 'Onetime::Organization'

## Verifies organization is marked as default
@org.is_default
#=> true

## Verifies customer now has organization
@customer.organization_instances.any?
#=> true

## Verifies workspace creation is idempotent (doesn't create duplicates)
@customer.organization_instances.size
Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call
@customer.organization_instances.size
#=> 1

## Two concurrent callers for one org-less customer mint exactly one workspace
# Each thread loads its own Customer instance, as two requests would. A caller
# either returns the workspace (winner, or contender that saw it appear), or
# fails retryable (contender whose wait ran out); never a collision, never a
# latch.
@racer_results = Array.new(2)
@racer_errors  = Array.new(2)
threads        = 2.times.map do |i|
  Thread.new do
    cust              = Onetime::Customer.load(@racer.objid)
    @racer_results[i] = Auth::Operations::EnsureDefaultWorkspace.new(customer: cust).call
  rescue Onetime::AccountProvisioningUnavailable => ex
    @racer_errors[i] = ex
  end
end
threads.each(&:join)
@racer_orgs = Onetime::Customer.load(@racer.objid).organization_instances.to_a
@racer_orgs.size
#=> 1

## Every caller that returned observed that same org; any other caller failed retryable
observed = @racer_results.compact.map { |result| result[:organization].objid }.uniq
[
  observed.size >= 1,
  observed == [@racer_orgs.first.objid],
  @racer_errors.compact.all? { |error| error.reason == :provisioning_in_progress },
  @racer_results.compact.size + @racer_errors.compact.size,
]
#=> [true, true, true, 2]

## The racing customer was never latched
Onetime::Customer.load(@racer.objid).provisioning_failed?
#=> false

## The contact_email_index holds exactly the one workspace that was created
Onetime::Organization.contact_email_index[@racer.email]
#=> @racer_orgs.first.identifier

## The creation lock was released, not left for the TTL
Familia::Lock.new(Onetime::Customer.org_creation_lock_key(@racer.objid)).locked?
#=> false

# Teardown
begin
  # Clean up test data
  @org.delete! if @org
  @customer.delete! if @customer
  @racer_orgs.to_a.each(&:delete!)
  @racer.delete! if @racer
rescue StandardError => ex
  puts "Cleanup error (non-fatal): #{ex.message}"
end
