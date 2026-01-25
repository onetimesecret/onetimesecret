# apps/web/billing/spec/logic/welcome/process_checkout_session_spec.rb
#
# frozen_string_literal: true

# Unit tests for ProcessCheckoutSession logic class.
#
# Tests the checkout session processing flow that handles redirects
# from Stripe after successful checkout (GET /billing/welcome?session_id=...).
#
# Run: pnpm run test:rspec apps/web/billing/spec/logic/welcome/process_checkout_session_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative '../../operations/process_webhook_event/shared_examples'
require_relative '../../../logic/welcome'

RSpec.describe 'Billing::Logic::Welcome::ProcessCheckoutSession', :billing do
  include BillingSpecHelper
  include ProcessWebhookEventHelpers

  let(:test_email) { "checkout-#{SecureRandom.hex(4)}@example.com" }
  let(:session_id) { "cs_test_session_#{SecureRandom.hex(4)}" }
  let(:stripe_customer_id) { "cus_test_#{SecureRandom.hex(4)}" }
  let(:stripe_subscription_id) { "sub_test_#{SecureRandom.hex(4)}" }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  # Mock session hash (Familia::Horreum session)
  let(:mock_session) do
    sess = {}
    sess['authenticated'] = true
    sess
  end

  # Mock strategy_result that logic classes expect
  # Logic::Base calls strategy_result.session and strategy_result.user
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: mock_session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'session_id' => session_id } }
  let(:locale) { 'en' }

  describe '#raise_concerns' do
    let!(:customer) { create_test_customer(email: test_email) }

    context 'without session_id' do
      let(:params) { {} }

      it 'raises form error' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)

        expect { logic.raise_concerns }.to raise_error(OT::FormError, /No session_id provided/)
      end
    end

    context 'with valid session_id' do
      let(:checkout_session) do
        Stripe::Checkout::Session.construct_from({
          id: session_id,
          object: 'checkout.session',
          customer: stripe_customer_id,
          subscription: stripe_subscription_id,
        })
      end

      before do
        allow(Stripe::Checkout::Session).to receive(:retrieve)
          .with(hash_including(id: session_id))
          .and_return(checkout_session)
      end

      it 'retrieves checkout session from Stripe' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)

        expect(Stripe::Checkout::Session).to receive(:retrieve)
          .with(hash_including(id: session_id, expand: %w[subscription customer]))
          .and_return(checkout_session)

        logic.raise_concerns
      end

      it 'extracts subscription from session' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns

        expect(logic.subscription).to eq(stripe_subscription_id)
      end
    end

    context 'with invalid session_id' do
      before do
        allow(Stripe::Checkout::Session).to receive(:retrieve)
          .and_raise(Stripe::InvalidRequestError.new('No such session', :id))
      end

      it 'raises Stripe error' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)

        expect { logic.raise_concerns }.to raise_error(Stripe::InvalidRequestError)
      end
    end
  end

  describe '#process' do
    let!(:customer) { create_test_customer(email: test_email) }

    context 'with subscription checkout' do
      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            'customer_extid' => customer.extid,
            Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1',
          },
        )
      end

      let(:checkout_session) do
        Stripe::Checkout::Session.construct_from({
          id: session_id,
          object: 'checkout.session',
          customer: stripe_customer_id,
          subscription: subscription,
        })
      end

      before do
        allow(Stripe::Checkout::Session).to receive(:retrieve)
          .with(hash_including(id: session_id))
          .and_return(checkout_session)
      end

      it 'finds or creates default organization' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns

        expect { logic.process }.to change {
          customer.organization_instances.to_a.length
        }.by(1)
      end

      it 'uses existing default organization if present' do
        existing_org = create_test_organization(customer: customer, default: true)

        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns

        expect { logic.process }.not_to(change { customer.organization_instances.to_a.length })

        existing_org.refresh!
        expect(existing_org.stripe_subscription_id).to eq(stripe_subscription_id)
      end

      it 'calls update_from_stripe_subscription on organization' do
        org = create_test_organization(customer: customer, default: true)

        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns
        logic.process

        org.refresh!
        # Catalog-first: plan_id resolved from catalog, not metadata
        expect(org.planid).to eq('test_plan_v1_monthly')
        expect(org.stripe_subscription_id).to eq(stripe_subscription_id)
        expect(org.subscription_status).to eq('active')
      end

      it 'returns success data' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns
        result = logic.process

        expect(result).to include(session_id: session_id, success: true)
      end
    end

    context 'with one-time payment (no subscription)' do
      let(:checkout_session) do
        Stripe::Checkout::Session.construct_from({
          id: session_id,
          object: 'checkout.session',
          customer: stripe_customer_id,
          subscription: nil,
        })
      end

      before do
        allow(Stripe::Checkout::Session).to receive(:retrieve)
          .with(hash_including(id: session_id))
          .and_return(checkout_session)
      end

      it 'returns success without updating org' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns
        result = logic.process

        expect(result).to include(session_id: session_id, success: true)
        expect(customer.organization_instances.to_a).to be_empty
      end
    end
  end
end
