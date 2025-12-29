# spec/unit/onetime/models/organization/with_organization_billing_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithOrganizationBilling module.
#
# Tests the extract_plan_id_from_subscription method which extracts planid
# from Stripe subscription metadata with fallback to price metadata.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/with_organization_billing_spec.rb

require 'spec_helper'

# Load billing metadata for FIELD_PLAN_ID constant
require_relative '../../../../../apps/web/billing/metadata'

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

    context 'when plan_id is not found anywhere' do
      let(:subscription) do
        build_subscription(
          subscription_metadata: {},
          price_metadata: {}
        )
      end

      it 'returns nil' do
        expect(org.test_extract_plan_id(subscription)).to be_nil
      end

      it 'logs a warning' do
        expect(OT).to receive(:lw).with(
          '[Organization.extract_plan_id_from_subscription] No plan_id in metadata',
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
  end
end
