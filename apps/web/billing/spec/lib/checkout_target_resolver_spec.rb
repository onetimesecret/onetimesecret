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
end
