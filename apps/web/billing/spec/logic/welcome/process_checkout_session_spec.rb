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
        expect(org.planid).to eq('test_plan_v1')
        expect(org.stripe_subscription_id).to eq(stripe_subscription_id)
        expect(org.subscription_status).to eq('active')
      end

      it 'returns success data' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns
        result = logic.process

        expect(result).to include(session_id: session_id, success: true)
      end

      # =====================================================================
      # Regression: appsec H-2 residue — step 3 must not select an org the
      # customer merely BELONGS to.
      #
      # Reachable state: the customer's own workspace is archived and their
      # default_org_id points at a shared tenant org they joined as a member
      # (JoinDomainOrganization does exactly this on custom-domain SSO
      # sign-in). A checkout carrying no orgid then resolved through
      # default_org_id to the tenant org, and update_from_stripe_subscription
      # overwrote the tenant's stripe_customer_id — detaching it from its own
      # billing customer.
      # =====================================================================
      context 'when the customer only belongs to (does not own) their default org' do
        let(:tenant_owner) do
          create_test_customer(email: "tenant-owner-#{SecureRandom.hex(4)}@example.com")
        end

        let!(:tenant_org) do
          org                    = create_test_organization(customer: tenant_owner, name: 'Tenant Org', default: false)
          org.stripe_customer_id = 'cus_tenant_billing_root'
          org.save
          org.add_members_instance(customer, through_attrs: { role: 'member', status: 'active' })
          org
        end

        before do
          # The caller's own workspace exists but is archived, so no owned,
          # live org resolves — and it still holds the contact_email index
          # reservation, which step 4's creation has to survive.
          own = create_test_organization(customer: customer, default: true)
          own.archive!('spec fixture: superseded by tenant org via SSO')

          customer.default_org_id = tenant_org.objid
          customer.save
        end

        it 'does not apply the subscription to the tenant organization' do
          logic  = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          result = logic.process

          tenant_org.refresh!
          expect(tenant_org.stripe_customer_id).to eq('cus_tenant_billing_root')
          expect(tenant_org.stripe_subscription_id).to be_nil
          expect(result[:org_extid]).not_to eq(tenant_org.extid)
        end

        it 'creates a new organization the customer owns and applies it there' do
          logic  = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          result = logic.process

          target = Onetime::Organization.find_by_extid(result[:org_extid])
          created_organizations << target
          expect(target.owner?(customer)).to be(true)
          expect(target).not_to be_archived
          expect(target.stripe_subscription_id).to eq(stripe_subscription_id)
        end
      end

      # =====================================================================
      # Regression: step 1 must reject an ARCHIVED metadata orgid.
      #
      # The org named in subscription metadata can be archived between
      # checkout-session creation and payment completion (a tenant SSO
      # sign-in archives the personal workspace). Applying the subscription
      # there leaves the customer with no live workspace and a paid
      # subscription only an operator can move.
      #
      # Twin of the CheckoutCompleted coverage in
      # spec/operations/process_webhook_event/checkout_completed_spec.rb.
      # =====================================================================
      context 'when the metadata orgid points at an org archived after checkout started' do
        let!(:archived_org) do
          org = create_test_organization(customer: customer, default: true)
          org.archive!('spec fixture: archived between checkout creation and completion')
          org
        end

        # The customer's remaining live workspace — created without a
        # contact_email because the archived org still holds that reservation.
        let!(:live_org) do
          org = Onetime::Organization.create!('Live Workspace', customer, nil)
          created_organizations << org
          org
        end

        let(:subscription) do
          build_stripe_subscription(
            id: stripe_subscription_id,
            customer: stripe_customer_id,
            status: 'active',
            metadata: {
              'customer_extid' => customer.extid,
              'orgid' => archived_org.objid,
              Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1',
            },
          )
        end

        it 'does not apply the subscription to the archived org' do
          logic  = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          result = logic.process

          archived_org.refresh!
          expect(archived_org.stripe_subscription_id).to be_nil
          expect(archived_org.stripe_customer_id).to be_nil
          expect(result[:org_extid]).not_to eq(archived_org.extid)
        end

        it 'applies it to the customer live owned org instead' do
          logic  = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          result = logic.process

          live_org.refresh!
          expect(result[:org_extid]).to eq(live_org.extid)
          expect(live_org.stripe_subscription_id).to eq(stripe_subscription_id)
          expect(live_org.subscription_status).to eq('active')
        end

        it 'does not mint an extra workspace' do
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns

          expect { logic.process }.not_to(change { customer.organization_instances.to_a.length })
        end
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
