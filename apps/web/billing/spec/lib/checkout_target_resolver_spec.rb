# apps/web/billing/spec/lib/checkout_target_resolver_spec.rb
#
# frozen_string_literal: true

# Tests for Billing::CheckoutTargetResolver — the shared target-selection
# policy used by BOTH completion surfaces for the same checkout:
#
#   - Billing::Logic::Welcome::ProcessCheckoutSession   (browser redirect)
#   - Billing::Operations::WebhookHandlers::CheckoutCompleted (webhook)
#
# SCOPE: these examples drive the resolver DIRECTLY (resolve + step 4) in the
# order the two surfaces would reach it. They are not end-to-end claims about
# either surface's request/job lifecycle.
#
# Run: LANES_DATASTORE_DB=14 RACK_ENV=test bundle exec rspec \
#   apps/web/billing/spec/lib/checkout_target_resolver_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../operations/process_webhook_event/shared_examples'
require_relative '../../lib/checkout_target_resolver'

RSpec.describe Billing::CheckoutTargetResolver, :billing do
  include BillingSpecHelper
  include ProcessWebhookEventHelpers

  let(:test_email) { "resolver-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { "cus_test_#{SecureRandom.hex(4)}" }
  let(:stripe_subscription_id) { "sub_test_#{SecureRandom.hex(4)}" }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:logger) { double('billing_logger', info: nil, warn: nil, error: nil, debug: nil) }

  # A payment-link / legacy checkout: no orgid stamped in metadata, so step 1
  # cannot resolve and the ordering of steps 2-4 is what decides the target.
  let(:metadata) { { 'customer_extid' => customer.extid } }

  let!(:customer) { create_test_customer(email: test_email) }

  # Step 4 is reached when the customer's ONLY organizations are archived.
  #
  # This is the state that reaches step 4 on both surfaces regardless of
  # authentication: Billing::Controllers::Base#ensure_customer_has_workspace
  # self-heals only when `cust.organization_instances.any?` is false, and an
  # archived org still counts there — while owned_live_orgs rejects it as a
  # billing target. The archived org also still holds the contact_email index
  # reservation, so step 4's first create! attempt raises OrganizationExists
  # and falls to the nil-contact_email retry.
  let!(:archived_org) do
    org = create_test_organization(customer: customer, default: true)
    org.archive!('spec fixture: customer has no live workspace')
    org
  end

  let(:subscription) do
    build_stripe_subscription(
      id: stripe_subscription_id,
      customer: stripe_customer_id,
      status: 'active',
      metadata: metadata.merge('plan_id' => 'identity_plus_v1'),
    )
  end

  after do
    created_organizations.uniq(&:objid).each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  def resolve_for(label)
    described_class.resolve(
      customer: customer,
      metadata: metadata,
      stripe_customer_id: stripe_customer_id,
      logger: logger,
      label: label,
    )
  end

  def create_for(label)
    org = described_class.create_billing_workspace(
      customer,
      logger: logger,
      label: label,
      stripe_customer_id: stripe_customer_id,
    )
    created_organizations << org
    org
  end

  def live_owned_count
    described_class.owned_live_orgs(customer).length
  end

  describe 'concurrent completion of the same checkout (redirect + webhook)' do
    # =====================================================================
    # Control: the SEQUENTIAL ordering is safe. The second surface reads
    # after the first surface's create, so it resolves to the workspace the
    # first surface made and no second workspace is minted. This is the
    # ordering every existing spec exercises.
    # =====================================================================
    it 'resolves to the first surface workspace when the second surface reads after the create' do
      expect(resolve_for('[A]')).to be_nil

      org_a = create_for('[A]')

      expect(resolve_for('[B]')&.objid).to eq(org_a.objid)
      expect(live_owned_count).to eq(1)
    end

    # =====================================================================
    # Race: both surfaces read BEFORE either writes.
    #
    # Timeline (no threads — the interleaving is driven by call order):
    #   T1  A (redirect) resolves -> nil   (no orgid, cus_ not yet linked,
    #                                       no owned LIVE org)
    #   T2  B (webhook)  resolves -> nil   (same reads, same answer)
    #   T3  A creates the workspace, claiming stripe_customer_id
    #   T4  B creates: the claim is already held, so B adopts A's workspace
    #
    # Before the claim, T4 minted a SECOND is_default workspace and the
    # unique index then rejected the loser's subscription write with
    # Onetime::Problem — a 500 on the redirect surface (plans.rb#welcome
    # rescues only FormError/StripeError) and a failed webhook job.
    # =====================================================================
    it 'does not create a second workspace when both surfaces resolve before either creates' do
      redirect_target = resolve_for('[ProcessCheckoutSession]')
      webhook_target  = resolve_for('[CheckoutCompleted]')

      expect(redirect_target).to be_nil
      expect(webhook_target).to be_nil

      org_a = create_for('[ProcessCheckoutSession]')
      org_b = create_for('[CheckoutCompleted]')

      expect(org_b.objid).to eq(org_a.objid)
      expect(live_owned_count).to eq(1)
    end

    it 'lets the surface that loses the claim apply the subscription instead of failing' do
      resolve_for('[ProcessCheckoutSession]')
      resolve_for('[CheckoutCompleted]')

      org_a = create_for('[ProcessCheckoutSession]')
      org_b = create_for('[CheckoutCompleted]')

      org_a.update_from_stripe_subscription(subscription)

      expect { org_b.update_from_stripe_subscription(subscription) }.not_to raise_error
      expect(org_b.objid).to eq(org_a.objid)

      org_a.refresh!
      expect(org_a.stripe_subscription_id).to eq(stripe_subscription_id)
    end
  end

  # =======================================================================
  # Archived organizations.
  #
  # An org can be archived BETWEEN checkout-session creation and payment
  # completion (a tenant SSO sign-in archives the personal workspace via
  # JoinDomainOrganization#adopt_domain_default_org). The two steps that can
  # return an archived org disagree on purpose — step 1 rejects, step 2 does
  # not — and these examples pin both halves of that asymmetry.
  # =======================================================================
  describe 'archived organizations' do
    # A second live org the customer owns, so step 3 has something to find.
    # Created without a contact_email: the archived fixture still holds the
    # customer's email in the contact_email index.
    def create_live_owned_org
      org = Onetime::Organization.create!('Live Workspace', customer, nil)
      created_organizations << org
      org
    end

    context 'when the metadata orgid points at an archived org (step 1)' do
      let(:metadata) do
        { 'customer_extid' => customer.extid, 'orgid' => archived_org.objid }
      end

      it 'does not resolve to it' do
        expect(resolve_for('[CheckoutCompleted]')).to be_nil
      end

      it 'warns so an operator can see the checkout lost its explicit target' do
        resolve_for('[CheckoutCompleted]')

        expect(logger).to have_received(:warn).with(
          a_string_including('orgid in metadata is archived'),
          hash_including(orgid: archived_org.objid, extid: archived_org.extid),
        )
      end

      it 'falls through to the live org the customer owns (step 3)' do
        live_org = create_live_owned_org

        expect(resolve_for('[CheckoutCompleted]')&.objid).to eq(live_org.objid)
      end

      it 'falls through to the create path when nothing else resolves (step 4)' do
        expect(resolve_for('[CheckoutCompleted]')).to be_nil

        org = create_for('[CheckoutCompleted]')

        expect(org.objid).not_to eq(archived_org.objid)
        expect(org.owner?(customer)).to be(true)
        expect(org).not_to be_archived
      end

      it 'applies the subscription to the live org, never the archived one' do
        target = resolve_for('[CheckoutCompleted]') || create_for('[CheckoutCompleted]')
        target.update_from_stripe_subscription(subscription)

        archived_org.refresh!
        expect(archived_org.stripe_subscription_id).to be_nil
        expect(target.objid).not_to eq(archived_org.objid)
        expect(target.stripe_subscription_id).to eq(stripe_subscription_id)
      end
    end

    # =====================================================================
    # Step 2 deliberately returns an archived org. stripe_customer_id is a
    # unique index and the archived org still holds the claim, so rejecting
    # here would fall through to a create that takes the SAME claim, loses
    # it, and adopts its way straight back to the archived org — a loud
    # failure (or a duplicate workspace) in place of a recoverable state.
    #
    # If a future change flips this, the second example below fails first
    # and shows why.
    # =====================================================================
    context 'when an archived org holds the checkout stripe_customer_id (step 2)' do
      let(:metadata) do
        { 'customer_extid' => customer.extid, 'orgid' => archived_org.objid }
      end

      before do
        archived_org.stripe_customer_id = stripe_customer_id
        archived_org.save
      end

      it 'resolves to it anyway — the prior binding is the target' do
        expect(resolve_for('[CheckoutCompleted]')&.objid).to eq(archived_org.objid)
      end

      it 'warns: an archived org holding a live Stripe binding is an anomaly' do
        resolve_for('[CheckoutCompleted]')

        expect(logger).to have_received(:warn).with(
          a_string_including('bound to an archived org'),
          hash_including(
            stripe_customer_id: stripe_customer_id,
            orgid: archived_org.objid,
            extid: archived_org.extid,
          ),
        )
      end

      it 'is why rejecting here would not help: the create path bounces back to it' do
        expect(create_for('[CheckoutCompleted]').objid).to eq(archived_org.objid)
      end
    end
  end
end
