# apps/web/auth/spec/operations/ensure_default_workspace_federation_same_second_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Regression for #4754 review F2. The claim used to decide "already applied"
# by comparing PendingFederatedSubscription#received_at with
# Organization#subscription_synced_at in whole seconds using <=. A pending
# snapshot stored in the same second the org was last synced, but carrying
# newer subscription state, was treated as already applied and destroyed by
# the next verification retry.
#
# Pending records and orgs now record a position in one sync order
# (sync_version / subscription_sync_version), and the webhook's no-match
# lookup and its store run under the federation lock the claim also takes.
#
# Both writers use the real code: Billing::PendingFederatedSubscription
# .store_from_webhook and Organization#mark_subscription_synced!. Timecop
# freezes the clock so both writes fall in the same second.
#
# =============================================================================

require 'spec_helper'
require 'securerandom'

RSpec.describe 'EnsureDefaultWorkspace: pending snapshot stored in the same second as the last sync', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/ensure_default_workspace'
    require 'billing/models/pending_federated_subscription'
    require 'billing/operations/process_webhook_event'
  end

  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
    Timecop.return
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:email_hashes) { [] }

  after do
    created_organizations.each { |org| org.delete! if org&.exists? rescue nil }
    created_customers.each { |cust| cust.delete! if cust&.exists? rescue nil }
    email_hashes.each do |hash|
      Billing::PendingFederatedSubscription.find_by_email_hash(hash)&.destroy! rescue nil
    end
  end

  # Fixed instant, mid-second so a freeze cannot straddle a boundary.
  let(:t0) { Time.at(1_893_456_000, 400, :millisecond) }

  def unique_email
    "same-second-#{SecureRandom.hex(8)}@federation-test.example.com"
  end

  def stripe_subscription(plan_id:, status: 'active', id: "sub_#{SecureRandom.hex(6)}")
    Stripe::Subscription.construct_from(
      id: id,
      object: 'subscription',
      customer: 'cus_same_second',
      status: status,
      metadata: { 'plan_id' => plan_id },
      items: {
        object: 'list',
        data: [{ id: 'si_1', object: 'subscription_item', current_period_end: (t0 + 30 * 86_400).to_i }],
      },
    )
  end

  # The real webhook writer for a region where no org matched yet.
  def store_pending(email_hash, plan_id:, event_id:)
    Billing::PendingFederatedSubscription.store_from_webhook(
      email_hash: email_hash,
      subscription: stripe_subscription(plan_id: plan_id),
      region: 'EU',
      source_stripe_event_id: event_id,
    )
  end

  def mailbox_verified_customer(email)
    cust = Onetime::Customer.create!(email: email, role: 'customer', verified: true, verified_by: 'email')
    created_customers << cust
    cust
  end

  it 'applies a newer snapshot stored in the same second as the claim that synced the org' do
    email = unique_email
    hash  = Onetime::Utils::EmailHash.compute(email)
    email_hashes << hash

    Timecop.freeze(t0)

    # Webhook 1 (no org yet): pending snapshot for plan A.
    store_pending(hash, plan_id: 'identity_plus_v1', event_id: 'evt_first')

    # Signup with mailbox proof: workspace created, snapshot A claimed,
    # subscription_synced_at = t0, record destroyed.
    customer = mailbox_verified_customer(email)
    org      = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
    created_organizations << org
    org.refresh!
    expect(org.planid).to eq('identity_plus_v1')
    expect(org.subscription_synced_at.to_i).to eq(t0.to_i)

    # Webhook 2 (plan change to B) did its no-org lookup before the workspace
    # existed and writes its snapshot now, still in second t0.
    store_pending(hash, plan_id: 'team_plus_v1', event_id: 'evt_second')
    pending = Billing::PendingFederatedSubscription.find_by_email_hash(hash)
    expect(pending.received_at.to_i).to eq(org.subscription_synced_at.to_i)
    expect(pending.source_stripe_event_id).to eq('evt_second')

    # A later verification retry (SetCustomerVerification runs the claim on every
    # mailbox-verified call, :no_change included).
    Timecop.freeze(t0 + 60)
    applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)

    org.refresh!
    expect(org.planid).to eq('team_plus_v1'),
      "snapshot B (evt_second) was stored after the claim that applied A, so the retry must apply it; " \
      "applied=#{applied.inspect}, pending_left=#{Billing::PendingFederatedSubscription.pending?(hash)}"
    expect(applied).to be(true)
  end

  # The real webhook ordering: process_with_federation looks up orgs, finds
  # none, and only then calls store_from_webhook. Provisioning used to
  # complete inside that window and claim the older snapshot, leaving the
  # webhook's newer one to be discarded as a same-second leftover. The
  # lookup and the store now run under the federation lock, so a
  # provisioning that starts inside the window waits for the store and
  # applies the newer snapshot.
  it 'applies the snapshot a subscription.updated webhook stores while provisioning waits for the lock' do
    email = unique_email
    hash  = Onetime::Utils::EmailHash.compute(email)
    email_hashes << hash

    Timecop.freeze(t0)
    store_pending(hash, plan_id: 'identity_plus_v1', event_id: 'evt_first')
    customer = mailbox_verified_customer(email)

    allow(Stripe::Customer).to receive(:retrieve).with('cus_same_second').and_return(
      Stripe::Customer.construct_from(
        id: 'cus_same_second', object: 'customer', email: email,
        metadata: { 'email_hash' => hash, 'region' => 'EU' },
      ),
    )
    allow(Stripe::Customer).to receive(:update).and_return(nil)

    event = Stripe::Event.construct_from(
      id: "evt_second_#{SecureRandom.hex(4)}", object: 'event', type: 'customer.subscription.updated',
      data: { object: stripe_subscription(plan_id: 'team_plus_v1').to_hash },
    )

    provisioning = nil
    allow(Billing::PendingFederatedSubscription).to receive(:store_from_webhook).and_wrap_original do |original, **attributes|
      if attributes[:source_stripe_event_id] == event.id && provisioning.nil?
        # The dispatcher already saw no org. Provisioning starts now, on
        # another thread, and must wait for this store.
        expect(Onetime::Organization.find_federated_by_email_hash(hash)).to eq([])
        provisioning = Thread.new do
          Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
        end
        sleep 0.5
        expect(provisioning).to be_alive
        expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash).planid).to eq('identity_plus_v1')
      end
      original.call(**attributes)
    end

    expect(Billing::Operations::ProcessWebhookEvent.new(event: event).call).to eq(:pending_stored)

    org = provisioning.value
    created_organizations << org
    org.refresh!
    expect(org.planid).to eq('team_plus_v1'),
      "#{event.id} was stored before provisioning took the lock, so the claim must apply it; " \
      "pending_left=#{Billing::PendingFederatedSubscription.pending?(hash)}"
    expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash)).to be_nil

    # A later retry has nothing left to apply and changes nothing.
    Timecop.freeze(t0 + 60)
    expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)).to be(false)
    org.refresh!
    expect(org.planid).to eq('team_plus_v1')
  end

  # F8 in the same second: the claim saved the org and then failed to
  # destroy the record it applied. The surviving copy has the version the
  # org recorded, so the retry discards it even though its received_at ties
  # the sync marker, and even after a cancellation reached the org.
  it 'discards the surviving copy of the snapshot the claim applied, in the same second' do
    email = unique_email
    hash  = Onetime::Utils::EmailHash.compute(email)
    email_hashes << hash

    Timecop.freeze(t0)
    store_pending(hash, plan_id: 'identity_plus_v1', event_id: 'evt_first')
    applied_copy = Billing::PendingFederatedSubscription.find_by_email_hash(hash)

    customer = mailbox_verified_customer(email)
    org      = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
    created_organizations << org
    org.refresh!
    expect(org.planid).to eq('identity_plus_v1')
    expect(org.subscription_sync_version.to_i).to eq(applied_copy.sync_version.to_i)
    expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash)).to be_nil

    # The record as a failed destroy! would have left it.
    applied_copy.save
    leftover = Billing::PendingFederatedSubscription.find_by_email_hash(hash)
    expect(leftover.received_at.to_i).to eq(org.subscription_synced_at.to_i)
    expect(leftover.sync_version.to_i).to eq(org.subscription_sync_version.to_i)

    # A cancellation written straight to the org without a newer version
    # (the timestamp is all a pre-version writer records).
    org.subscription_status = 'canceled'
    org.planid              = 'free_v1'
    org.save

    Timecop.freeze(t0 + 60)
    expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)).to be(false)
    org.refresh!
    expect(org.planid).to eq('free_v1')
    expect(org.subscription_status).to eq('canceled')
    expect(Billing::PendingFederatedSubscription.find_by_email_hash(hash)).to be_nil
  end
end
