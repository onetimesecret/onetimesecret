# apps/web/billing/spec/support/shared_contexts/with_organization.rb
#
# frozen_string_literal: true

# Shared context for organization with owner
#
# Purpose: Reduce duplication in controller specs that require organizations.
# Creates organization owned by authenticated customer with cleanup.
#
# Usage:
#   RSpec.describe 'BillingController' do
#     include Rack::Test::Methods
#     include_context 'with_authenticated_customer'
#     include_context 'with_organization'
#
#     it 'accesses organization data' do
#       get "/billing/api/org/#{organization.extid}"
#       expect(last_response.status).to eq(200)
#     end
#   end
#
# Provides:
#   - organization: Onetime::Organization instance owned by customer
#   - Automatic cleanup in after hook
#
# Requirements:
#   - Must be used with 'with_authenticated_customer' context
#
RSpec.shared_context 'with_organization' do
  let(:created_organizations) { [] }

  let(:organization) do
    org = Onetime::Organization.create!('Test Organization', customer, customer.email)
    created_organizations << org
    org
  end

  before do
    organization.save
  end

  after do
    # Clean up created organizations
    created_organizations.each(&:destroy!)
  end

  # Helper: Create organization member (non-owner)
  #
  # Adds a customer as member to the organization without owner privileges.
  # Useful for testing owner-only authorization.
  #
  # @param email [String] Optional custom email
  # @return [Onetime::Customer] Member customer
  def create_organization_member(email: nil)
    member = create_other_customer(email: email)

    # Add as member but not owner
    organization.add_members_instance(member)

    member
  end

  # Helper: Create additional organization
  #
  # @param name [String] Organization name
  # @param owner [Onetime::Customer] Owner customer (defaults to authenticated customer)
  # @return [Onetime::Organization]
  def create_other_organization(name: 'Other Organization', owner: customer)
    org = Onetime::Organization.create!(name, owner, owner.email)
    created_organizations << org
    org.save
    org
  end

  # Helper: Set Stripe customer ID on organization
  #
  # @param stripe_customer_id [String] Stripe customer ID
  def set_stripe_customer(stripe_customer_id)
    organization.stripe_customer_id = stripe_customer_id
    organization.save
  end

  # Helper: Update organization from Stripe subscription
  #
  # Note: Requires valid Stripe::Subscription object (use in VCR tests)
  #
  # @param subscription [Stripe::Subscription] Stripe subscription object
  def update_from_subscription(subscription)
    organization.update_from_stripe_subscription(subscription)
    organization.save
  end
end
