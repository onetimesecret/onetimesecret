# spec/unit/onetime/models/organization/with_organization_billing_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithOrganizationBilling module.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/with_organization_billing_spec.rb

require 'spec_helper'

# Load billing dependencies
require_relative '../../../../../apps/web/billing/metadata'
require_relative '../../../../../apps/web/billing/models/plan'
require_relative '../../../../../apps/web/billing/lib/plan_validator'
require_relative '../../../../../apps/web/billing/operations/apply_subscription_to_org'

RSpec.describe 'WithOrganizationBilling', billing: true do
  # Build a minimal Stripe::Subscription for testing
  def build_subscription(price_id: 'price_test', subscription_metadata: {}, price_metadata: {})
    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test',
      status: 'active',
      metadata: subscription_metadata,
      items: {
        data: [{
          price: {
            id: price_id,
            product: 'prod_test',
            metadata: price_metadata,
          },
          current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
        }],
      },
    })
  end

  # Mock a plan in the catalog for a given price_id
  def mock_catalog_plan(price_id:, plan_id:)
    mock_plan = instance_double(
      Billing::Plan,
      plan_id: plan_id,
      stripe_price_id: price_id
    )
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with(price_id)
      .and_return(mock_plan)
    mock_plan
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
                      :subscription_status, :subscription_period_end, :planid,
                      :complimentary

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
      # Mock catalog to return plan for price_test (catalog-first behavior)
      mock_plan = instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1',
        stripe_price_id: 'price_test'
      )
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with('price_test')
        .and_return(mock_plan)
      # Stub Phase 2 materialization (test class doesn't include WithMaterializedEntitlements)
      allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:materialize_entitlements_for_org)
        .and_return(true)
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

      it 'extracts and updates planid from catalog' do
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
      it 'raises CatalogMissError when price_id not in catalog (fail-closed)' do
        org.planid = 'existing_plan'

        # price_unknown is not in our mocked catalog
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_unknown')
          .and_return(nil)

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

        expect { org.update_from_stripe_subscription(subscription) }
          .to raise_error(Billing::CatalogMissError)
      end

      it 'updates planid from catalog when extraction succeeds' do
        subscription = build_valid_subscription
        org.update_from_stripe_subscription(subscription)
        # Plan resolved from catalog, not metadata
        expect(org.planid).to eq('identity_plus_v1')
      end
    end

    context 'complimentary metadata syncing' do
      it 'sets complimentary when subscription metadata has complimentary=true' do
        subscription = Stripe::Subscription.construct_from({
          id: 'sub_comp_123',
          object: 'subscription',
          customer: 'cus_test_456',
          status: 'active',
          metadata: {
            Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1',
            Billing::Metadata::FIELD_COMPLIMENTARY => 'true',
          },
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
        })

        org.update_from_stripe_subscription(subscription)
        expect(org.complimentary).to eq('true')
      end

      it 'clears complimentary when metadata does not have complimentary' do
        org.complimentary = 'true'
        subscription = build_valid_subscription
        org.update_from_stripe_subscription(subscription)
        expect(org.complimentary).to be_nil
      end
    end
  end

  # ==========================================================================
  # paid? and complimentary? canonical method tests
  # ==========================================================================
  describe '#paid?' do
    let(:billing_test_class) do
      Class.new do
        include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

        attr_accessor :subscription_status, :planid, :complimentary

        def initialize(status: nil, planid: nil, complimentary: nil)
          @subscription_status = status
          @planid = planid
          @complimentary = complimentary
        end
      end
    end

    it 'returns true for active subscription with paid plan' do
      org = billing_test_class.new(status: 'active', planid: 'identity_plus_v1')
      expect(org.paid?).to be true
    end

    it 'returns true for trialing subscription with paid plan' do
      org = billing_test_class.new(status: 'trialing', planid: 'identity_plus_v1')
      expect(org.paid?).to be true
    end

    it 'returns false for canceled subscription even with paid planid' do
      org = billing_test_class.new(status: 'canceled', planid: 'identity_plus_v1')
      expect(org.paid?).to be false
    end

    it 'returns false for past_due subscription' do
      org = billing_test_class.new(status: 'past_due', planid: 'identity_plus_v1')
      expect(org.paid?).to be false
    end

    it 'returns false for active subscription with free_v1 plan' do
      org = billing_test_class.new(status: 'active', planid: 'free_v1')
      expect(org.paid?).to be false
    end

    it 'returns false for active subscription with free plan' do
      org = billing_test_class.new(status: 'active', planid: 'free')
      expect(org.paid?).to be false
    end

    it 'returns false for active subscription with empty planid' do
      org = billing_test_class.new(status: 'active', planid: '')
      expect(org.paid?).to be false
    end

    it 'returns false for active subscription with nil planid' do
      org = billing_test_class.new(status: 'active', planid: nil)
      expect(org.paid?).to be false
    end

    it 'returns false when no subscription status' do
      org = billing_test_class.new(status: nil, planid: 'identity_plus_v1')
      expect(org.paid?).to be false
    end
  end

  describe '#complimentary?' do
    let(:billing_test_class) do
      Class.new do
        include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

        attr_accessor :subscription_status, :planid, :complimentary

        def initialize(status: nil, planid: nil, complimentary: nil)
          @subscription_status = status
          @planid = planid
          @complimentary = complimentary
        end
      end
    end

    it 'returns true for active subscription with complimentary marker' do
      org = billing_test_class.new(
        status: 'active',
        planid: 'identity_plus_v1',
        complimentary: 'true'
      )
      expect(org.complimentary?).to be true
    end

    it 'returns false for active subscription without complimentary marker' do
      org = billing_test_class.new(
        status: 'active',
        planid: 'identity_plus_v1',
        complimentary: nil
      )
      expect(org.complimentary?).to be false
    end

    it 'returns false for canceled subscription even with complimentary marker' do
      org = billing_test_class.new(
        status: 'canceled',
        planid: 'identity_plus_v1',
        complimentary: 'true'
      )
      expect(org.complimentary?).to be false
    end

    it 'returns false when complimentary is empty string' do
      org = billing_test_class.new(
        status: 'active',
        planid: 'identity_plus_v1',
        complimentary: ''
      )
      expect(org.complimentary?).to be false
    end

    it 'a complimentary org is also paid' do
      org = billing_test_class.new(
        status: 'active',
        planid: 'identity_plus_v1',
        complimentary: 'true'
      )
      expect(org.paid?).to be true
      expect(org.complimentary?).to be true
    end
  end
end
