# spec/unit/onetime/models/organization/with_organization_billing_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithOrganizationBilling module.
#
# Tests the catalog-first extract_plan_id_from_subscription method which:
# 1. Resolves plan_id from price_id via catalog lookup (authoritative)
# 2. Raises Billing::CatalogMissError on cache miss (fail-closed)
# 3. Logs drift when metadata differs from catalog value (auto-healing)
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/with_organization_billing_spec.rb

require 'spec_helper'

# Load billing dependencies
require_relative '../../../../../apps/web/billing/metadata'
require_relative '../../../../../apps/web/billing/models/plan'
require_relative '../../../../../apps/web/billing/lib/plan_validator'

RSpec.describe 'WithOrganizationBilling', billing: true do
  # Test class that includes the module under test
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

      attr_accessor :objid

      def initialize
        @objid = 'test-org-123'
      end

      # Make private methods accessible for testing
      def test_extract_plan_id(subscription)
        extract_plan_id_from_subscription(subscription)
      end

      def test_extract_metadata_plan_id(subscription)
        extract_metadata_plan_id(subscription)
      end
    end
  end

  let(:org) { test_class.new }

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

  describe '#extract_plan_id_from_subscription' do
    describe 'catalog-first resolution' do
      context 'when price_id exists in catalog' do
        before do
          mock_catalog_plan(price_id: 'price_test', plan_id: 'identity_plus_v1_monthly')
        end

        let(:subscription) { build_subscription }

        it 'returns plan_id from catalog' do
          expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_monthly')
        end

        it 'logs successful resolution' do
          expect(OT).to receive(:info).with(
            '[Organization.extract_plan_id_from_subscription] Resolved plan from catalog',
            hash_including(
              plan_id: 'identity_plus_v1_monthly',
              price_id: 'price_test',
              subscription_id: 'sub_test_123'
            )
          )
          org.test_extract_plan_id(subscription)
        end
      end

      context 'when catalog returns different plan_id than metadata (drift)' do
        before do
          mock_catalog_plan(price_id: 'price_test', plan_id: 'identity_plus_v1_monthly')
        end

        let(:subscription) do
          build_subscription(
            subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus' } # stale value
          )
        end

        it 'uses catalog value (not metadata)' do
          expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_monthly')
        end

        it 'logs drift warning' do
          expect(OT).to receive(:lw).with(
            '[Organization.extract_plan_id_from_subscription] Drift detected - using catalog value',
            hash_including(
              catalog_plan_id: 'identity_plus_v1_monthly',
              metadata_plan_id: 'identity_plus',
              price_id: 'price_test'
            )
          )
          allow(OT).to receive(:info) # Allow the success log
          org.test_extract_plan_id(subscription)
        end
      end

      context 'when metadata matches catalog (no drift)' do
        before do
          mock_catalog_plan(price_id: 'price_test', plan_id: 'identity_plus_v1_monthly')
        end

        let(:subscription) do
          build_subscription(
            subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1_monthly' }
          )
        end

        it 'does not log drift warning' do
          expect(OT).not_to receive(:lw)
          allow(OT).to receive(:info)
          org.test_extract_plan_id(subscription)
        end
      end
    end

    describe 'fail-closed behavior' do
      context 'when price_id is not in catalog' do
        before do
          allow(Billing::Plan).to receive(:find_by_stripe_price_id)
            .with('price_unknown')
            .and_return(nil)
        end

        let(:subscription) { build_subscription(price_id: 'price_unknown') }

        it 'raises Billing::CatalogMissError' do
          expect {
            org.test_extract_plan_id(subscription)
          }.to raise_error(Billing::CatalogMissError, /price_unknown/)
        end

        it 'does NOT fall back to metadata' do
          sub = build_subscription(
            price_id: 'price_unknown',
            subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'stale_plan' }
          )
          expect {
            org.test_extract_plan_id(sub)
          }.to raise_error(Billing::CatalogMissError)
        end
      end

      context 'when subscription has no price_id' do
        let(:subscription) do
          Stripe::Subscription.construct_from({
            id: 'sub_no_price',
            object: 'subscription',
            customer: 'cus_test',
            status: 'active',
            metadata: {},
            items: {
              data: [{
                price: nil,
                current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
              }],
            },
          })
        end

        it 'raises ArgumentError' do
          expect {
            org.test_extract_plan_id(subscription)
          }.to raise_error(ArgumentError, /no price_id/)
        end
      end
    end

    describe 'multiple plans in catalog' do
      before do
        # Only mock the specific price_id lookup
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_yearly_456')
          .and_return(
            instance_double(Billing::Plan, plan_id: 'identity_plus_v1_yearly', stripe_price_id: 'price_yearly_456')
          )
      end

      let(:subscription) { build_subscription(price_id: 'price_yearly_456') }

      it 'finds correct plan by price_id' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_yearly')
      end
    end
  end

  describe '#extract_metadata_plan_id' do
    context 'when plan_id is in subscription metadata' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_subscription' }
        )
      end

      it 'returns subscription metadata value' do
        expect(org.test_extract_metadata_plan_id(subscription)).to eq('from_subscription')
      end
    end

    context 'when plan_id is only in price metadata' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: {},
          price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_price' }
        )
      end

      it 'returns price metadata value' do
        expect(org.test_extract_metadata_plan_id(subscription)).to eq('from_price')
      end
    end

    context 'when both subscription and price metadata have plan_id' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_subscription' },
          price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_price' }
        )
      end

      it 'prefers subscription metadata' do
        expect(org.test_extract_metadata_plan_id(subscription)).to eq('from_subscription')
      end
    end

    context 'when no metadata has plan_id' do
      let(:subscription) { build_subscription }

      it 'returns nil' do
        expect(org.test_extract_metadata_plan_id(subscription)).to be_nil
      end
    end

    context 'when subscription metadata is nil' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
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
                metadata: { Billing::Metadata::FIELD_PLAN_ID => 'from_price' },
              },
              current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
            }],
          },
        })
      end

      it 'falls back to price metadata' do
        expect(org.test_extract_metadata_plan_id(subscription)).to eq('from_price')
      end
    end
  end
end
