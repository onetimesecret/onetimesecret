# spec/unit/onetime/models/organization/with_organization_billing_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithOrganizationBilling module.
#
# Tests the extract_plan_id_from_subscription method which extracts planid
# from Stripe subscription metadata with fallback to price metadata and
# finally plan catalog lookup by price_id.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/with_organization_billing_spec.rb

require 'spec_helper'

# Load billing metadata and plan for constants and catalog lookup
require_relative '../../../../../apps/web/billing/metadata'
require_relative '../../../../../apps/web/billing/models/plan'

RSpec.describe 'WithOrganizationBilling', billing: true do
  # Test class that includes the module under test
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

      attr_accessor :objid

      def initialize
        @objid = 'test-org-123'
      end

      # Make private method accessible for testing
      def test_extract_plan_id(subscription)
        extract_plan_id_from_subscription(subscription)
      end
    end
  end

  let(:org) { test_class.new }

  # Build a minimal Stripe::Subscription for testing
  def build_subscription(subscription_metadata: {}, price_metadata: {})
    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test',
      status: 'active',
      metadata: subscription_metadata,
      items: {
        data: [{
          price: {
            id: 'price_test',
            product: 'prod_test',
            metadata: price_metadata,
          },
          current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
        }],
      },
    })
  end

  describe '#extract_plan_id_from_subscription' do
    context 'when plan_id is in subscription metadata' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1' }
        )
      end

      it 'extracts planid from subscription metadata' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1')
      end

      it 'prefers subscription metadata over price metadata' do
        sub = build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_subscription' },
          price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_price' }
        )
        expect(org.test_extract_plan_id(sub)).to eq('from_subscription')
      end
    end

    context 'when plan_id is only in price metadata' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: {},
          price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'multi_team_v1' }
        )
      end

      it 'falls back to price metadata' do
        expect(org.test_extract_plan_id(subscription)).to eq('multi_team_v1')
      end
    end

    context 'when plan_id is only found via price_id catalog lookup' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: {},
          price_metadata: {}
        )
      end

      before do
        # Create a mock plan in the catalog that matches our test price_id
        mock_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_test'
        )
        allow(Billing::Plan).to receive(:list_plans).and_return([mock_plan])
      end

      it 'falls back to plan catalog lookup by price_id' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_monthly')
      end

      it 'logs an info message about the fallback resolution' do
        expect(OT).to receive(:info).with(
          '[Organization.resolve_plan_from_price_id] Resolved plan from price_id (metadata fallback)',
          hash_including(
            plan_id: 'identity_plus_v1_monthly',
            price_id: 'price_test',
            subscription_id: 'sub_test_123',
            orgid: 'test-org-123'
          )
        )
        org.test_extract_plan_id(subscription)
      end
    end

    context 'when plan_id is not found anywhere (metadata or catalog)' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: {},
          price_metadata: {}
        )
      end

      before do
        # Empty catalog - no matching plan
        allow(Billing::Plan).to receive(:list_plans).and_return([])
      end

      it 'returns nil' do
        expect(org.test_extract_plan_id(subscription)).to be_nil
      end

      it 'logs a warning about missing plan in catalog' do
        expect(OT).to receive(:lw).with(
          '[Organization.resolve_plan_from_price_id] No plan found for price_id',
          hash_including(
            price_id: 'price_test',
            subscription_id: 'sub_test_123',
            orgid: 'test-org-123'
          )
        )
        expect(OT).to receive(:lw).with(
          '[Organization.extract_plan_id_from_subscription] No plan_id in metadata or catalog',
          hash_including(subscription_id: 'sub_test_123', orgid: 'test-org-123')
        )
        org.test_extract_plan_id(subscription)
      end
    end

    context 'when subscription has nil metadata' do
      it 'falls back to price metadata' do
        sub = Stripe::Subscription.construct_from({
          id: 'sub_nil_meta',
          object: 'subscription',
          customer: 'cus_test',
          status: 'active',
          metadata: nil,
          items: {
            data: [{
              price: {
                id: 'price_test',
                product: 'prod_test',
                metadata: { Billing::Metadata::FIELD_PLAN_ID => 'fallback_plan' },
              },
              current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
            }],
          },
        })
        expect(org.test_extract_plan_id(sub)).to eq('fallback_plan')
      end
    end

    context 'with different plan_id values' do
      %w[free_v1 identity_plus_v1 multi_team_v1 enterprise_v1].each do |plan_id|
        it "correctly extracts '#{plan_id}'" do
          sub = build_subscription(
            subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => plan_id }
          )
          expect(org.test_extract_plan_id(sub)).to eq(plan_id)
        end
      end
    end

    context 'when catalog has multiple plans' do
      let(:subscription) do
        # Subscription with price_id that matches the second plan in catalog
        Stripe::Subscription.construct_from({
          id: 'sub_multi_plan',
          object: 'subscription',
          customer: 'cus_test',
          status: 'active',
          metadata: {},
          items: {
            data: [{
              price: {
                id: 'price_yearly_456',
                product: 'prod_test',
                metadata: {},
              },
              current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
            }],
          },
        })
      end

      before do
        # Multiple plans in catalog - only one matches the price_id
        monthly_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_monthly_123'
        )
        yearly_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_yearly',
          stripe_price_id: 'price_yearly_456'
        )
        allow(Billing::Plan).to receive(:list_plans).and_return([monthly_plan, yearly_plan])
      end

      it 'finds the correct plan by matching price_id' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_yearly')
      end
    end
  end
end
