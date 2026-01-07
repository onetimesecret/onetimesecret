# spec/unit/onetime/models/organization/with_organization_billing_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithOrganizationBilling module.
#
# Tests the extract_plan_id_from_subscription method which uses catalog-first
# approach via BillingService:
# 1. Catalog lookup by price_id (most authoritative)
# 2. Price-level metadata['plan_id']
# 3. Subscription-level metadata['plan_id'] (may be stale)
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
    context 'when plan_id is in subscription metadata (no catalog match)' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1' }
        )
      end

      it 'extracts planid from subscription metadata as fallback' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1')
      end

      it 'prefers price metadata over subscription metadata (catalog-first order)' do
        # With catalog-first approach, price metadata is preferred over subscription metadata
        # because subscription metadata may be stale from checkout
        sub = build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_subscription' },
          price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_price' }
        )
        expect(org.test_extract_plan_id(sub)).to eq('from_price')
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

      it 'logs an info message about catalog resolution' do
        expect(OT).to receive(:info).with(
          '[BillingService.resolve_plan_id_from_subscription] Resolved via catalog',
          hash_including(
            plan_id: 'identity_plus_v1_monthly',
            price_id: 'price_test',
            subscription_id: 'sub_test_123'
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

      it 'logs a warning about unresolvable plan' do
        expect(OT).to receive(:lw).with(
          '[BillingService.resolve_plan_id_from_subscription] Unable to resolve plan_id',
          hash_including(
            price_id: 'price_test',
            subscription_id: 'sub_test_123'
          )
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

  # ==========================================================================
  # update_from_stripe_subscription tests
  # ==========================================================================
  describe '#update_from_stripe_subscription' do
    # Full test class that includes save behavior
    let(:saveable_test_class) do
      Class.new do
        include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

        attr_accessor :objid, :stripe_subscription_id, :stripe_customer_id,
                      :subscription_status, :subscription_period_end, :planid

        def initialize
          @objid = 'test-org-123'
        end

        def save
          @saved = true
        end

        def saved?
          @saved == true
        end
      end
    end

    let(:org) { saveable_test_class.new }
    let(:period_end) { (Time.now + 30 * 24 * 60 * 60).to_i }

    def build_valid_subscription(overrides = {})
      Stripe::Subscription.construct_from({
        id: 'sub_test_123',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1' },
        items: {
          data: [{
            price: {
              id: 'price_test',
              product: 'prod_test',
              metadata: {},
            },
            current_period_end: period_end,
          }],
        },
      }.merge(overrides))
    end

    before do
      # Stub Organization.find_by_stripe_customer_id to return nil (no collision)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).and_return(nil)
      # Empty catalog for these tests
      allow(Billing::Plan).to receive(:list_plans).and_return([])
    end

    context 'with valid subscription' do
      let(:subscription) { build_valid_subscription }

      it 'updates stripe_subscription_id' do
        org.update_from_stripe_subscription(subscription)
        expect(org.stripe_subscription_id).to eq('sub_test_123')
      end

      it 'updates stripe_customer_id' do
        org.update_from_stripe_subscription(subscription)
        expect(org.stripe_customer_id).to eq('cus_test_456')
      end

      it 'updates subscription_status' do
        org.update_from_stripe_subscription(subscription)
        expect(org.subscription_status).to eq('active')
      end

      it 'updates subscription_period_end' do
        org.update_from_stripe_subscription(subscription)
        expect(org.subscription_period_end).to eq(period_end.to_s)
      end

      it 'extracts and updates planid from metadata' do
        org.update_from_stripe_subscription(subscription)
        expect(org.planid).to eq('identity_plus_v1')
      end

      it 'calls save' do
        org.update_from_stripe_subscription(subscription)
        expect(org.saved?).to be true
      end
    end

    context 'with different subscription statuses' do
      %w[active trialing past_due canceled unpaid incomplete incomplete_expired paused].each do |status|
        it "accepts valid status '#{status}'" do
          subscription = build_valid_subscription(status: status)
          expect { org.update_from_stripe_subscription(subscription) }.not_to raise_error
          expect(org.subscription_status).to eq(status)
        end
      end

      it 'logs warning for unknown status but does not raise' do
        subscription = build_valid_subscription(status: 'unknown_status')
        # Allow any OT log calls (BillingService may also log)
        allow(OT).to receive(:lw)
        allow(OT).to receive(:info)

        expect(OT).to receive(:lw).with(
          '[Organization.update_from_stripe_subscription] Unknown subscription status',
          hash_including(status: 'unknown_status')
        )
        expect { org.update_from_stripe_subscription(subscription) }.not_to raise_error
      end
    end

    context 'input validation' do
      it 'raises ArgumentError for non-Stripe::Subscription object' do
        expect { org.update_from_stripe_subscription({}) }
          .to raise_error(ArgumentError, /Expected Stripe::Subscription/)
      end

      it 'raises ArgumentError for nil' do
        expect { org.update_from_stripe_subscription(nil) }
          .to raise_error(ArgumentError, /Expected Stripe::Subscription/)
      end

      it 'raises ArgumentError for string' do
        expect { org.update_from_stripe_subscription('sub_123') }
          .to raise_error(ArgumentError, /Expected Stripe::Subscription/)
      end

      it 'raises ArgumentError when subscription id is missing' do
        subscription = Stripe::Subscription.construct_from({
          object: 'subscription',
          customer: 'cus_test',
          status: 'active',
          items: { data: [{ price: { id: 'price_test' }, current_period_end: period_end }] },
        })
        expect { org.update_from_stripe_subscription(subscription) }
          .to raise_error(ArgumentError, /missing required fields/)
      end

      it 'raises ArgumentError when customer is missing' do
        subscription = Stripe::Subscription.construct_from({
          id: 'sub_test',
          object: 'subscription',
          status: 'active',
          items: { data: [{ price: { id: 'price_test' }, current_period_end: period_end }] },
        })
        expect { org.update_from_stripe_subscription(subscription) }
          .to raise_error(ArgumentError, /missing required fields/)
      end

      it 'raises ArgumentError when status is missing' do
        subscription = Stripe::Subscription.construct_from({
          id: 'sub_test',
          object: 'subscription',
          customer: 'cus_test',
          items: { data: [{ price: { id: 'price_test' }, current_period_end: period_end }] },
        })
        expect { org.update_from_stripe_subscription(subscription) }
          .to raise_error(ArgumentError, /missing required fields/)
      end
    end

    context 'customer ID collision prevention' do
      let(:subscription) { build_valid_subscription }

      it 'allows update when customer_id is already assigned to this org' do
        org.stripe_customer_id = 'cus_test_456'
        expect { org.update_from_stripe_subscription(subscription) }.not_to raise_error
      end

      it 'raises OT::Problem when customer_id belongs to different org' do
        other_org = double('Organization', objid: 'other-org-999', extid: 'org_other')
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with('cus_test_456')
          .and_return(other_org)

        expect { org.update_from_stripe_subscription(subscription) }
          .to raise_error(OT::Problem, /already linked to org/)
      end

      it 'allows assignment when no org has the customer_id yet' do
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with('cus_test_456')
          .and_return(nil)

        expect { org.update_from_stripe_subscription(subscription) }.not_to raise_error
      end
    end

    context 'planid extraction' do
      it 'does not update planid when extraction returns nil' do
        org.planid = 'existing_plan'

        # Empty metadata and no catalog match
        subscription = Stripe::Subscription.construct_from({
          id: 'sub_no_plan',
          object: 'subscription',
          customer: 'cus_test',
          status: 'active',
          metadata: {},
          items: {
            data: [{
              price: { id: 'price_unknown', product: 'prod_test', metadata: {} },
              current_period_end: period_end,
            }],
          },
        })

        org.update_from_stripe_subscription(subscription)
        expect(org.planid).to eq('existing_plan')
      end

      it 'updates planid when extraction succeeds' do
        subscription = build_valid_subscription
        org.update_from_stripe_subscription(subscription)
        expect(org.planid).to eq('identity_plus_v1')
      end
    end
  end
end
