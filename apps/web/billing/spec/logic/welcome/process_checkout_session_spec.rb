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
require_relative '../../../operations/process_webhook_event'

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
          .with(hash_including(id: session_id, expand: %w[subscription]))
          .and_return(checkout_session)

        logic.raise_concerns
      end

      it 'extracts subscription from session' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns

        expect(logic.subscription).to eq(stripe_subscription_id)
      end

      it 'exposes the Stripe customer as a plain id' do
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
        logic.raise_concerns

        expect(logic.stripe_customer_id).to eq(stripe_customer_id)
      end

      context 'when Stripe hands back an expanded customer object' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: Stripe::Customer.construct_from(id: stripe_customer_id, object: 'customer'),
            subscription: stripe_subscription_id,
          })
        end

        it 'normalizes it to the cus_ id at the boundary' do
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns

          expect(logic.stripe_customer_id).to be_a(String)
          expect(logic.stripe_customer_id).to eq(stripe_customer_id)
        end
      end

      context 'when the customer field is neither a String nor a Stripe::Customer' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: Stripe::Price.construct_from(id: 'price_not_a_customer', object: 'price'),
            subscription: stripe_subscription_id,
          })
        end

        it 'yields nil rather than manufacturing a claim string' do
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns

          expect(logic.stripe_customer_id).to be_nil
        end
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

      # =====================================================================
      # Regression: the redirect adapter must hand CheckoutTargetResolver a
      # 'cus_' STRING.
      #
      # This surface used to retrieve the session with expand: [subscription,
      # customer], so checkout_session.customer was a Stripe::Customer. Both
      # CheckoutTargetResolver.from_stripe_customer and
      # Organization.stripe_claim_fields reject non-Strings on purpose, so the
      # object silently disabled step 2 (idempotent replay) AND the
      # stripe_customer_id unique-index claim that elects a single creator
      # when the redirect and the webhook complete the same checkout. Nothing
      # raised; the workspace was simply born without its claim.
      #
      # The fixture below is an ACTUAL expanded object rather than a
      # hand-passed String, which is why the direct resolver tests in
      # spec/lib/checkout_target_resolver_spec.rb could not catch this.
      # =====================================================================
      context 'when Stripe hands back an expanded customer object' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: Stripe::Customer.construct_from(id: stripe_customer_id, object: 'customer'),
            subscription: subscription,
          })
        end

        def run_redirect
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          logic.process
        end

        it 'passes the resolver the cus_ String, not the Stripe::Customer' do
          received = :never_called
          allow(::Billing::CheckoutTargetResolver).to receive(:resolve).and_wrap_original do |original, **kwargs|
            received = kwargs[:stripe_customer_id]
            original.call(**kwargs)
          end

          result = run_redirect
          created_organizations << Onetime::Organization.find_by_extid(result[:org_extid])

          expect(received).to be_a(String)
          expect(received).to eq(stripe_customer_id)
        end

        it 'passes the shared step-4 create the same String' do
          received = :never_called
          allow(::Billing::CheckoutTargetResolver).to receive(:create_checkout_workspace)
            .and_wrap_original do |original, cust, **kwargs|
              received = kwargs[:stripe_customer_id]
              original.call(cust, **kwargs)
            end

          result = run_redirect
          created_organizations << Onetime::Organization.find_by_extid(result[:org_extid])

          expect(received).to be_a(String)
          expect(received).to eq(stripe_customer_id)
        end

        it 'creates the workspace already holding the stripe_customer_id claim' do
          result = run_redirect
          target = Onetime::Organization.find_by_extid(result[:org_extid])
          created_organizations << target

          expect(target.stripe_customer_id).to eq(stripe_customer_id)
          expect(Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)&.objid)
            .to eq(target.objid)
        end

        it 'resolves the existing workspace when the redirect is replayed' do
          first  = run_redirect
          target = Onetime::Organization.find_by_extid(first[:org_extid])
          created_organizations << target

          expect { @second = run_redirect }.not_to(change { customer.organization_instances.to_a.length })
          expect(@second[:org_extid]).to eq(first[:org_extid])
        end

        # The two completion surfaces race for real: Stripe redirects the
        # browser while it delivers checkout.session.completed. Only the
        # stripe_customer_id unique index stops both from creating.
        context 'when the webhook completes the same checkout' do
          let(:webhook_event) do
            build_stripe_event(
              type: 'checkout.session.completed',
              data_object: build_stripe_session(
                id: session_id,
                customer: stripe_customer_id,
                subscription: stripe_subscription_id,
              ),
            )
          end

          before do
            stripe_customer = Stripe::Customer.construct_from(
              id: stripe_customer_id,
              object: 'customer',
              email: test_email,
              metadata: {},
            )
            allow(Stripe::Subscription).to receive(:retrieve)
              .with(stripe_subscription_id).and_return(subscription)
            allow(Stripe::Customer).to receive(:retrieve)
              .with(stripe_customer_id).and_return(stripe_customer)
            allow(Stripe::Customer).to receive(:update).and_return(stripe_customer)
          end

          it 'produces exactly one workspace' do
            Billing::Operations::ProcessWebhookEvent.new(event: webhook_event).call

            # Model the interleaving where BOTH surfaces resolved nothing
            # before either wrote: the redirect drops to its own create and
            # only the claim can stop a duplicate.
            allow(::Billing::CheckoutTargetResolver).to receive(:resolve).and_return(nil)

            result = run_redirect

            orgs = customer.organization_instances.to_a
            created_organizations.concat(orgs)

            expect(orgs.length).to eq(1)
            expect(result[:org_extid]).to eq(orgs.first.extid)
            expect(orgs.first.stripe_customer_id).to eq(stripe_customer_id)
          end
        end
      end

      # =====================================================================
      # Regression: fail closed. A subscription checkout whose Stripe customer
      # cannot be identified must stop BEFORE step 4 creates a workspace —
      # a workspace created without the claim is invisible to replay
      # resolution and to the concurrent-creation election, i.e. exactly the
      # silent state the expanded-object bug produced.
      # =====================================================================
      shared_examples 'a checkout that fails before creating a workspace' do
        it 'raises rather than creating an unclaimed workspace' do
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns

          expect { logic.process }.to raise_error(OT::FormError, /no valid Stripe customer/)
          expect(customer.organization_instances.to_a).to be_empty
        end

        it 'never reaches the resolver' do
          expect(::Billing::CheckoutTargetResolver).not_to receive(:resolve)
          expect(::Billing::CheckoutTargetResolver).not_to receive(:create_billing_workspace)

          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns

          expect { logic.process }.to raise_error(OT::FormError)
        end
      end

      context 'when the session has no Stripe customer' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: nil,
            subscription: subscription,
          })
        end

        include_examples 'a checkout that fails before creating a workspace'
      end

      context 'when the session customer is not a Stripe customer id' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: 'acct_not_a_customer',
            subscription: subscription,
          })
        end

        include_examples 'a checkout that fails before creating a workspace'
      end

      context 'when the session customer is an unexpected Stripe object' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: Stripe::Price.construct_from(id: 'price_not_a_customer', object: 'price'),
            subscription: subscription,
          })
        end

        include_examples 'a checkout that fails before creating a workspace'
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

      # The fail-closed guard belongs to the SUBSCRIPTION branch only. A
      # one-time payment binds no billing workspace, so an absent Stripe
      # customer is not an error here — putting the guard in raise_concerns
      # (which runs before the session's mode is known) would turn this
      # legitimate flow into a form error.
      context 'without a Stripe customer on the session' do
        let(:checkout_session) do
          Stripe::Checkout::Session.construct_from({
            id: session_id,
            object: 'checkout.session',
            customer: nil,
            subscription: nil,
          })
        end

        it 'still succeeds' do
          logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, params, locale)
          logic.raise_concerns
          result = logic.process

          expect(result).to include(session_id: session_id, success: true)
          expect(customer.organization_instances.to_a).to be_empty
        end
      end
    end
  end
end
