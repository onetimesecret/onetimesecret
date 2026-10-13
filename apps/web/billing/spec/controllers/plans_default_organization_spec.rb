# apps/web/billing/spec/controllers/plans_default_organization_spec.rb
#
# frozen_string_literal: true

# The billing target Plans#checkout_redirect and #customer_portal_redirect
# resolve, on the shared lookup fixture (another owner's default listed
# first, the customer's archived default second, their live owned default
# third). The explicit target (default_org_id) is honoured whoever owns it —
# the controllers' ownership gates then deny, never swap in another
# workspace — and the implicit fallback is restricted to the default
# workspace the caller owns. The gates themselves are covered by
# plans_controller_spec.rb (appsec H-2).
#
# Run: tests/lanes/run billing --only apps/web/billing/spec/controllers/plans_default_organization_spec.rb
require_relative '../support/billing_spec_helper'
require 'billing/controllers/plans'

RSpec.describe Billing::Controllers::Plans do
  include_context 'default workspace lookup fixture'

  let(:controller) { described_class.allocate }
  let(:default_org_id) { '' }
  let(:memberships) { lookup_fixture_orgs }
  let(:customer) do
    double(
      'Customer',
      objid: 'cust_billing',
      extid: 'ur_billing',
      email: 'billing@example.com',
      anonymous?: false,
      default_org_id: default_org_id,
      organization_instances: memberships,
    )
  end

  before do
    stub_workspace_ownership(customer)
    allow(Onetime::Organization).to receive(:create!)
    allow(controller).to receive(:billing_logger).and_return(double('billing_logger', info: nil, warn: nil))
  end

  describe '#default_organization_for' do
    it 'selects the owned default, not the foreign default listed first' do
      expect(controller.send(:default_organization_for, customer)).to be(owned_default)
    end

    context 'when default_org_id names a joined organization' do
      let(:default_org_id) { foreign_default.objid }

      it 'returns that explicit target for the ownership gate to deny, instead of billing the owned default' do
        expect(controller.send(:default_organization_for, customer)).to be(foreign_default)
      end
    end

    context 'when the caller owns no live default workspace' do
      let(:memberships) { [foreign_default, archived_default] }

      it 'returns nil rather than a joined organization' do
        expect(controller.send(:default_organization_for, customer)).to be_nil
      end
    end
  end

  describe '#find_or_create_default_organization' do
    it 'returns the owned default without creating' do
      expect(controller.send(:find_or_create_default_organization, customer)).to be(owned_default)
      expect(Onetime::Organization).not_to have_received(:create!)
    end

    context 'when the caller has organizations but owns no live default' do
      let(:memberships) { [foreign_default, archived_default] }

      it 'returns nil and does not mint a workspace next to their memberships' do
        expect(controller.send(:find_or_create_default_organization, customer)).to be_nil
        expect(Onetime::Organization).not_to have_received(:create!)
      end
    end

    context 'when the caller has no live organization at all' do
      let(:memberships) { [archived_default] }
      let(:created) { instance_double(Onetime::Organization, extid: 'or_created') }

      it 'self-heals by creating a default workspace' do
        allow(Onetime::Organization).to receive(:create!).and_return(created)

        expect(controller.send(:find_or_create_default_organization, customer)).to be(created)
        expect(Onetime::Organization).to have_received(:create!)
          .with("#{customer.email}'s Workspace", customer, customer.email, is_default: true)
      end
    end
  end
end
