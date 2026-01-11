# apps/api/organizations/spec/logic/organizations/update_organization_spec.rb
#
# frozen_string_literal: true

# Tests for UpdateOrganization logic, focusing on billing email sync.
#
# Run: pnpm run test:rspec apps/api/organizations/spec/logic/organizations/update_organization_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Organizations::UpdateOrganization do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-123',
      custid: 'cust-123',
      extid: 'ext-cust-123',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer'
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Org',
      description: 'Test description',
      billing_email: 'billing@example.com',
      contact_email: 'billing@example.com',
      stripe_customer_id: nil,
      is_default: true,
      created: Time.now.to_i,
      updated: Time.now.to_i,
      member_count: 1,
      save: true
    )
  end

  let(:owner_customer) do
    instance_double(Onetime::Customer, extid: 'ext-cust-123')
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) do
    {
      'extid' => 'ext-org-123',
      'display_name' => 'Updated Org',
      'description' => 'Updated description',
      'billing_email' => 'new-billing@example.com'
    }
  end

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:lw)
    allow(OT).to receive(:le)

    # Stub WebhookSyncFlag to not skip Stripe sync (default behavior for OTS-initiated changes)
    stub_const('Billing::WebhookSyncFlag', Class.new do
      def self.skip_stripe_sync?(_org_extid)
        false
      end
    end)

    allow(Onetime::Organization).to receive(:find_by_extid)
      .with('ext-org-123')
      .and_return(organization)
    allow(organization).to receive(:owner?).with(customer).and_return(true)
    allow(organization).to receive(:owner).and_return(owner_customer)
    allow(organization).to receive(:display_name=)
    allow(organization).to receive(:description=)
    allow(organization).to receive(:billing_email=)
    allow(organization).to receive(:contact_email=)
    allow(organization).to receive(:updated=)
    allow(organization).to receive(:safe_dump).and_return({
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Updated Org',
      description: 'Updated description',
      billing_email: 'new-billing@example.com',
      contact_email: 'new-billing@example.com',
      is_default: true,
      created: Time.now.to_i,
      updated: Time.now.to_i,
      member_count: 1
    })
  end

  # Helper to run full logic flow (raise_concerns sets @organization, then process uses it)
  def run_logic
    logic.raise_concerns
    logic.process
  end

  describe '#process' do
    context 'when organization has no Stripe customer' do
      before do
        allow(organization).to receive(:stripe_customer_id).and_return(nil)
      end

      it 'updates billing_email locally' do
        expect(organization).to receive(:billing_email=).with('new-billing@example.com')
        expect(organization).to receive(:contact_email=).with('new-billing@example.com')
        expect(organization).to receive(:save)
        run_logic
      end

      it 'does not attempt Stripe sync' do
        expect(Stripe::Customer).not_to receive(:update)
        run_logic
      end

      it 'returns success data' do
        result = run_logic
        expect(result).to have_key(:user_id)
        expect(result).to have_key(:record)
      end
    end

    context 'when organization has Stripe customer' do
      let(:stripe_customer_id) { 'cus_test123' }

      before do
        allow(organization).to receive(:stripe_customer_id).and_return(stripe_customer_id)
        allow(organization).to receive(:billing_email).and_return('old-billing@example.com')
      end

      it 'syncs billing_email to Stripe' do
        expect(Stripe::Customer).to receive(:update)
          .with(stripe_customer_id, { email: 'new-billing@example.com' })
        run_logic
      end

      it 'logs the sync operation' do
        allow(Stripe::Customer).to receive(:update)
        expect(OT).to receive(:info).with(/Syncing billing email to Stripe/, anything)
        run_logic
      end
    end

    context 'when Stripe sync fails' do
      let(:stripe_customer_id) { 'cus_test123' }

      before do
        allow(organization).to receive(:stripe_customer_id).and_return(stripe_customer_id)
        allow(organization).to receive(:billing_email).and_return('old-billing@example.com')
      end

      it 'logs error but local update succeeds' do
        allow(Stripe::Customer).to receive(:update)
          .and_raise(Stripe::StripeError.new('API error'))

        expect(OT).to receive(:le).with(/Failed to sync billing email/, anything)

        # Should not raise - local update still succeeds
        result = run_logic
        expect(result).to have_key(:record)
      end

      it 'handles Stripe customer not found gracefully' do
        allow(Stripe::Customer).to receive(:update)
          .and_raise(Stripe::InvalidRequestError.new('No such customer', nil))

        expect(OT).to receive(:lw).with(/Stripe customer not found/, anything)

        # Should not raise
        result = run_logic
        expect(result).to have_key(:record)
      end
    end

    context 'when billing_email unchanged' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'display_name' => 'Updated Org',
          'description' => 'Updated description',
          'billing_email' => 'billing@example.com' # Same as current
        }
      end

      before do
        allow(organization).to receive(:stripe_customer_id).and_return('cus_test123')
        allow(organization).to receive(:billing_email).and_return('billing@example.com')
      end

      it 'skips Stripe sync when email unchanged' do
        expect(Stripe::Customer).not_to receive(:update)
        run_logic
      end
    end

    context 'when billing_email is empty' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'display_name' => 'Updated Org',
          'description' => '',
          'billing_email' => ''
        }
      end

      before do
        allow(organization).to receive(:stripe_customer_id).and_return('cus_test123')
      end

      it 'does not update billing_email' do
        expect(organization).not_to receive(:billing_email=)
        expect(Stripe::Customer).not_to receive(:update)
        run_logic
      end
    end
  end
end
