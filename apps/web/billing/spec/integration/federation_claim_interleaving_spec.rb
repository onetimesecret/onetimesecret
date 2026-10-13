# frozen_string_literal: true

# Scheduled interleavings for F8 (cancellation replay) and F9 (incomplete
# materialization). Only Stripe I/O, billing enablement, and the documented
# fault/scheduler boundaries are intercepted; lookups and writes remain native.
# Run: tests/lanes/run billing-integration --only apps/web/billing/spec/integration/federation_claim_interleaving_spec.rb

require 'spec_helper'
require 'auth/operations/ensure_default_workspace'
require 'auth/operations/set_customer_verification'
require_relative '../../operations/process_webhook_event'
require_relative '../../models/pending_federated_subscription'

RSpec.describe 'Federation claim interleavings', :integration do
  before(:context) { Onetime.boot! :test unless Onetime.ready? }

  let(:initial_time) { Time.utc(2026, 10, 13, 12, 0, 0) }
  let(:email) { "claim-interleaving-#{SecureRandom.hex(12)}@example.com" }
  let(:email_hash) { Onetime::Utils::EmailHash.compute(email) }
  let(:stripe_customer_id) { "cus_interleaving_#{SecureRandom.hex(8)}" }
  let(:stripe_subscription_id) { "sub_interleaving_#{SecureRandom.hex(8)}" }
  let(:owner_membership) do
    Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, @customer.objid)
  end

  around do |example|
    previous_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'claim_interleaving_federation_secret_32chars'
    Timecop.freeze(initial_time) { example.run }
  ensure
    ENV['FEDERATION_SECRET'] = previous_secret
  end

  before do
    # Both billing lanes boot in standalone mode; enable paid entitlement readers.
    allow(Onetime::BillingConfig.instance).to receive(:enabled?).and_return(true)
    allow(Stripe::Customer).to receive(:retrieve).with(stripe_customer_id).and_return(
      Stripe::Customer.construct_from({
        id: stripe_customer_id,
        object: 'customer',
        email: email,
        metadata: { 'email_hash' => email_hash, 'region' => 'US' },
      }),
    )
    allow(Stripe::Customer).to receive(:update).and_return(nil)

    expect(Time.now.to_i).to eq(initial_time.to_i)
    expect(Familia.now.to_i).to eq(initial_time.to_i)
    expect(Onetime::EntitlementPreview.active?).to be(false)
    expect(Billing::Plan.load_from_config('identity_plus_v1')[:entitlements]).to include('custom_branding')
    expect(Billing::Plan.load_from_config('free_v1')[:entitlements]).not_to include('custom_branding')
  end

  after do
    # Teardown must not trigger a fault that an earlier assertion left armed.
    @inject_retirement_failure = false
    @inject_collection_failure = false
    begin
      pending_record&.destroy!
    ensure
      begin
        Billing::PendingFederatedSubscription.unindex_recent(email_hash)
        # Organization#destroy! semantically removes owner memberships and their
        # entitlement subkeys; Familia also deletes the org's related collections.
        @organization&.destroy!
      ensure
        @customer&.destroy!
      end
    end
  end

  def build_event(plan: 'identity_plus_v1', type: 'customer.subscription.updated', status: 'active')
    Stripe::Event.construct_from({
      id: "evt_interleaving_#{SecureRandom.hex(8)}",
      object: 'event',
      type: type,
      data: {
        object: {
          id: stripe_subscription_id,
          object: 'subscription',
          customer: stripe_customer_id,
          status: status,
          metadata: { Billing::Metadata::FIELD_PLAN_ID => plan },
          items: { data: [{ current_period_end: 2_000_000_000 }] },
        },
      },
    })
  end

  def dispatch(event)
    Billing::Operations::ProcessWebhookEvent.new(event: event).call
  end

  def pending_record
    Billing::PendingFederatedSubscription.find_by_email_hash(email_hash)
  end

  def provision_workspace(verified:)
    @customer = Onetime::Customer.create!(
      email: email, role: 'customer', verified: verified, verified_by: verified ? 'email' : nil,
    )
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(
      customer: @customer, require_verification: true,
    ).call[:organization]
  end

  def refresh_workspace!
    @organization.refresh!
    owner_membership.refresh!
  end

  def repeat_verification
    Auth::Operations::SetCustomerVerification.new(
      customer: @customer, verified: true, verified_by: 'email',
    ).call
  end

  it 'F8 preserves cancellation when a no-match writer resumes after provisioning published the hash index' do
    expect(dispatch(build_event)).to eq(:pending_stored)
    expect(pending_record).not_to be_nil
    deferred_event = build_event
    writer_interleavings = 0
    first_stamp = nil

    # Barrier: the dispatcher already observed no match. Before its pending
    # writer executes, signup claims the earlier record and publishes the index.
    # Resume the ORIGINAL writer at a later instant, not a fabricated receipt.
    allow(Billing::PendingFederatedSubscription).to receive(:store_from_webhook).and_wrap_original do |original, **attributes|
      if attributes[:source_stripe_event_id] == deferred_event.id
        writer_interleavings += 1
        expect(writer_interleavings).to eq(1)
        expect(Onetime::Organization.find_federated_by_email_hash(email_hash)).to eq([])
        provision_workspace(verified: true)
        refresh_workspace!
        first_stamp = @organization.subscription_federated_at.to_i
        expect(first_stamp).to eq(initial_time.to_i)
        expect(pending_record).to be_nil
        expect(Onetime::Organization.find_federated_by_email_hash(email_hash).map(&:objid)).to include(@organization.objid)
        Timecop.freeze(initial_time + 2)
        expect(Time.now.to_i).to eq(initial_time.to_i + 2)
        expect(Familia.now.to_i).to eq(initial_time.to_i + 2)
      end
      original.call(**attributes)
    end

    expect(dispatch(deferred_event)).to eq(:pending_stored)
    expect(writer_interleavings).to eq(1)
    expect(pending_record.source_stripe_event_id).to eq(deferred_event.id)
    expect(pending_record.received_at.to_i).to be > first_stamp

    retirement_attempts = 0
    retirement_failures = 0
    @inject_retirement_failure = true
    # The direct plan sync has saved the org before it attempts to retire the
    # pending row. Fail that retirement once; every subsequent destroy is real.
    allow_any_instance_of(Billing::PendingFederatedSubscription).to receive(:destroy!).and_wrap_original do |original, *args|
      retirement_attempts += 1
      if @inject_retirement_failure
        @inject_retirement_failure = false
        retirement_failures += 1
        expect(original.receiver.email_hash).to eq(email_hash)
        raise Redis::BaseConnectionError, 'injected pending retirement failure after direct sync'
      end
      original.call(*args)
    end

    expect(dispatch(build_event(plan: 'free_v1'))).to eq(:federated_only)
    expect(retirement_attempts).to eq(1)
    expect(retirement_failures).to eq(1)
    expect(pending_record).not_to be_nil
    expect(dispatch(build_event(type: 'customer.subscription.deleted', status: 'canceled'))).to eq(:federated_only)
    refresh_workspace!
    expect(@organization.subscription_federated_at.to_i).to eq(first_stamp)
    expect(@organization.planid).to eq('free_v1')
    expect(@organization.subscription_status).to eq('canceled')
    expect(@organization.can?('custom_branding')).to be(false)
    expect(owner_membership.can?('custom_branding')).to be(false)
    expect(@customer.mailbox_verified?).to be(true)
    expect(@customer.verified_by).to eq('email')

    expect(repeat_verification).to eq(:no_change)
    refresh_workspace!
    expect(retirement_failures).to eq(1)
    aggregate_failures('cancellation preservation') do
      expect(@organization.planid).to eq('free_v1')
      expect(@organization.subscription_status).to eq('canceled')
      expect(@organization.can?('custom_branding')).to be(false)
      expect(owner_membership.can?('custom_branding')).to be(false)
    end
  end

  it 'F9 completes paid materialization on retry after scalar persistence precedes a collection failure' do
    expect(dispatch(build_event)).to eq(:pending_stored)
    provision_workspace(verified: false)
    Billing::Operations::ApplySubscriptionToOrg.apply_free_tier(@organization, owner: false)
    @customer.verified = true
    @customer.verified_by = 'email'
    @customer.save
    collection_failures = 0
    @inject_collection_failure = true

    # Familia#save_with_collections commits save, then yields. Preserve that
    # native save and interrupt its yield immediately before the REAL collection
    # block (whose first write is entitlements_plan.clear / DEL) can execute.
    allow_any_instance_of(Onetime::Organization).to receive(:save_with_collections).and_wrap_original do |original, *args, **kwargs, &collection_writes|
      original.call(*args, **kwargs) do
        if @inject_collection_failure && original.receiver.objid == @organization.objid
          @inject_collection_failure = false
          collection_failures += 1
          raise Redis::BaseConnectionError, 'injected collection failure after native scalar save'
        end
        collection_writes.call if collection_writes
      end
    end

    expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(@customer)).to be(false)
    refresh_workspace!
    expect(collection_failures).to eq(1)
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(@organization.subscription_status).to eq('active')
    expect(@organization.subscription_federated_at.to_i).to eq(initial_time.to_i)
    expect(@organization.entitlements_materialized?).to be(true)
    expect(owner_membership.entitlements_materialized?).to be(true)
    expect(@organization.can?('custom_branding')).to be(false)
    expect(owner_membership.can?('custom_branding')).to be(false)
    expect(pending_record).not_to be_nil

    expect(repeat_verification).to eq(:no_change)
    refresh_workspace!
    expect(collection_failures).to eq(1)
    aggregate_failures('paid materialization recovery') do
      expect(@organization.can?('custom_branding')).to be(true)
      expect(owner_membership.can?('custom_branding')).to be(true)
      expect(pending_record).to be_nil
    end
  end
end
