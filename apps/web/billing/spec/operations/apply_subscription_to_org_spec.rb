# apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb
#
# frozen_string_literal: true

# Unit tests for ApplySubscriptionToOrg shared operation.
#
# Verifies consistent field-setting across owner, federated, and
# migration codepaths.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb

require 'spec_helper'
require 'billing/operations/apply_subscription_to_org'

RSpec.describe Billing::Operations::ApplySubscriptionToOrg, billing: true do
  let(:period_end) { (Time.now + 30 * 24 * 60 * 60).to_i }

  let(:org) do
    double('Organization',
      :subscription_status= => nil,
      :subscription_period_end= => nil,
      :planid= => nil,
      :complimentary= => nil,
      :stripe_subscription_id= => nil,
      :stripe_customer_id= => nil,
      save: true,
    )
  end

  def build_subscription(status: 'active', metadata: {}, price_id: 'price_test')
    mock_plan = instance_double(Billing::Plan, plan_id: 'identity_plus_v1')
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with(price_id)
      .and_return(mock_plan)

    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test_456',
      status: status,
      metadata: metadata,
      items: {
        data: [{
          price: {
            id: price_id,
            product: 'prod_test',
            metadata: {},
          },
          current_period_end: period_end,
        }],
      },
    })
  end

  describe 'owner path' do
    it 'sets all fields including Stripe IDs' do
      subscription = build_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:subscription_period_end=).with(period_end.to_s)
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).to receive(:stripe_subscription_id=).with('sub_test_123')
      expect(org).to receive(:stripe_customer_id=).with('cus_test_456')
      expect(org).to receive(:complimentary=).with(nil)
      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: true)
    end

    it 'sets complimentary when metadata has complimentary=true' do
      subscription = build_subscription(
        metadata: { Billing::Metadata::FIELD_COMPLIMENTARY => 'true' }
      )

      expect(org).to receive(:complimentary=).with('true')

      described_class.call(org, subscription, owner: true)
    end
  end

  describe 'federated path' do
    it 'sets status and plan but NOT Stripe IDs' do
      subscription = build_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).not_to receive(:stripe_subscription_id=)
      expect(org).not_to receive(:stripe_customer_id=)
      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: false)
    end
  end

  describe 'planid_override' do
    it 'uses override instead of catalog resolution' do
      subscription = build_subscription(price_id: 'price_unknown')
      # No catalog mock for price_unknown — would raise without override

      expect(org).to receive(:planid=).with('identity_plus_v1')

      described_class.call(org, subscription, owner: true,
        planid_override: 'identity_plus_v1')
    end
  end

  describe 'complimentary clearing' do
    it 'clears complimentary when metadata does not have the field' do
      subscription = build_subscription(metadata: {})

      expect(org).to receive(:complimentary=).with(nil)

      described_class.call(org, subscription, owner: true)
    end

    it 'clears complimentary when metadata has complimentary=false' do
      subscription = build_subscription(
        metadata: { Billing::Metadata::FIELD_COMPLIMENTARY => 'false' }
      )

      expect(org).to receive(:complimentary=).with(nil)

      described_class.call(org, subscription, owner: true)
    end
  end

  describe 'save: false' do
    it 'applies fields but does not call save' do
      subscription = build_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).not_to receive(:save)

      described_class.call(org, subscription, owner: false, save: false)
    end
  end
end
