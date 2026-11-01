# frozen_string_literal: true

# F1 (#4754 review): a deferred federation claim used to read the workspace
# and the pending record once, then write the pending plan back without
# re-reading either. A cancellation webhook that ran between those reads and
# the claim's save was undone by it: the paid plan came back after
# customer.subscription.deleted, the last event for that subscription.
#
# The claim and the federated webhook path now take one lock per email_hash
# (Billing::PendingFederatedSubscription.with_federation_lock) and the claim
# reads the org and the pending record inside it. These examples schedule a
# real cancellation (ProcessWebhookEvent, customer.subscription.deleted) at
# the points where it used to be lost:
#
#   - inside the claim's locked section, from a second thread: the webhook
#     waits for the lock and then applies, so the cancellation is the last
#     write;
#   - after the claim loaded the workspace but before it took the lock: the
#     claim's re-read sees the cancellation and does not replay the pending
#     snapshot the cancellation failed to retire.
#
# Only Stripe I/O, billing enablement, the scheduling points and the
# documented fault points are intercepted; lookups and writes remain native.
# Run: tests/lanes/run billing-integration --only apps/web/billing/spec/integration/federation_claim_cancellation_race_spec.rb

require 'spec_helper'
require 'auth/operations/ensure_default_workspace'
require 'auth/operations/set_customer_verification'
require_relative '../../operations/process_webhook_event'
require_relative '../../operations/apply_subscription_to_org'
require_relative '../../models/pending_federated_subscription'

RSpec.describe 'Federation claim racing a cancellation webhook', :integration do
  before(:context) { Onetime.boot! :test unless Onetime.ready? }

  # How long the scheduling point waits before it checks that the webhook
  # thread is still blocked on the lock. A webhook that was not blocked
  # finishes well inside it.
  let(:blocked_webhook_grace) { 0.5 }

  let(:initial_time) { Time.utc(2026, 10, 13, 12, 0, 0) }
  let(:email) { "claim-cancel-race-#{SecureRandom.hex(12)}@example.com" }
  let(:email_hash) { Onetime::Utils::EmailHash.compute(email) }
  let(:stripe_customer_id) { "cus_cancelrace_#{SecureRandom.hex(8)}" }
  let(:stripe_subscription_id) { "sub_cancelrace_#{SecureRandom.hex(8)}" }
  let(:owner_membership) do
    Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, @customer.objid)
  end
  let(:federation_lock) do
    Familia::Lock.new(Billing::PendingFederatedSubscription.federation_lock_key(email_hash))
  end

  around do |example|
    previous_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'claim_cancel_race_federation_secret_32chars'
    Timecop.freeze(initial_time) { example.run }
  ensure
    ENV['FEDERATION_SECRET'] = previous_secret
  end

  before do
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

    expect(Billing::Plan.load_from_config('identity_plus_v1')[:entitlements]).to include('custom_branding')
    expect(Billing::Plan.load_from_config('free_v1')[:entitlements]).not_to include('custom_branding')
  end

  after do
    @inject_collection_failure = false
    @inject_retirement_failure = false
    @cancel_after_pending_read = false
    @cancel_after_materialize  = false
    @cancel_before_lock        = false
    @webhook_thread&.join(10)
    federation_lock.force_unlock!
    begin
      pending_record&.destroy!
    ensure
      begin
        Billing::PendingFederatedSubscription.unindex_recent(email_hash)
        @organization&.destroy!
      ensure
        @customer&.destroy!
      end
    end
  end

  def build_event(plan: 'identity_plus_v1', type: 'customer.subscription.updated', status: 'active')
    Stripe::Event.construct_from({
      id: "evt_cancelrace_#{SecureRandom.hex(8)}",
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

  def cancellation_event
    build_event(type: 'customer.subscription.deleted', status: 'canceled')
  end

  def dispatch(event)
    Billing::Operations::ProcessWebhookEvent.new(event: event).call
  end

  def pending_record
    Billing::PendingFederatedSubscription.find_by_email_hash(email_hash)
  end

  def persisted_org
    Onetime::Organization.load(@organization.objid)
  end

  def refresh_workspace!
    @organization.refresh!
    owner_membership.refresh!
  end

  # SSO JIT account: IdP-asserted address, no mailbox proof. The default
  # workspace is created on the default path; the claim is deferred.
  def provision_sso_workspace
    @customer     = Onetime::Customer.create!(
      email: email, role: 'customer', verified: true, verified_by: 'sso', provisioning_origin: 'sso_jit',
    )
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call[:organization]
    expect(@organization).not_to be_nil
    expect(@organization.email_hash.to_s).to be_empty
    expect(@organization.planid).not_to eq('identity_plus_v1')
  end

  def operator_verify
    Auth::Operations::SetCustomerVerification.new(
      customer: @customer, verified: true, verified_by: 'cli_provision',
    )
  end

  # Dispatch the cancellation from a second thread while this thread has
  # the federation lock, and confirm it is waiting for the lock rather than
  # done: the org it would write is still paid after the grace period.
  def start_blocked_cancellation
    expect(federation_lock.locked?).to be(true)
    event           = cancellation_event
    @webhook_thread = Thread.new { dispatch(event) }
    sleep blocked_webhook_grace
    expect(@webhook_thread).to be_alive
    expect(persisted_org.subscription_status).not_to eq('canceled')
  end

  def expect_cancellation_preserved
    refresh_workspace!
    aggregate_failures('cancellation preserved after claim') do
      expect(@organization.planid).to eq('free_v1')
      expect(@organization.subscription_status).to eq('canceled')
      expect(@organization.can?('custom_branding')).to be(false)
      expect(owner_membership.can?('custom_branding')).to be(false)
      expect(pending_record).to be_nil
    end
  end

  # Familia#save_with_collections commits the scalar save, then yields to the
  # collection writes. Fail the yield once (as the F9 interleaving spec does)
  # so the first claim leaves a paid plan with the hash published, no sync
  # marker, and the pending record intact.
  def arm_collection_failure_once
    @inject_collection_failure = true
    allow_any_instance_of(Onetime::Organization).to receive(:save_with_collections).and_wrap_original do |original, *args, **kwargs, &collection_writes|
      original.call(*args, **kwargs) do
        if @inject_collection_failure && original.receiver.objid == @organization.objid
          @inject_collection_failure = false
          raise Redis::BaseConnectionError, 'injected collection failure after native scalar save'
        end
        collection_writes&.call
      end
    end
  end

  # The F9 state a :no_change retry exists for: mailbox proof recorded, the
  # first claim saved the paid scalars (publishing the hash) and then failed,
  # the pending record survives.
  def strand_first_claim
    expect(dispatch(build_event)).to eq(:pending_stored)
    provision_sso_workspace
    expect(pending_record).not_to be_nil

    arm_collection_failure_once
    first = operator_verify
    expect(first.call).to eq(:success)
    expect(first.federation_claimed?).to be(false)
    refresh_workspace!
    expect(@customer.mailbox_verified?).to be(true)
    expect(@organization.email_hash).to eq(email_hash)
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(@organization.subscription_synced_at.to_s).to be_empty
    expect(Onetime::Organization.find_federated_by_email_hash(email_hash).map(&:objid)).to include(@organization.objid)
    expect(pending_record).not_to be_nil
  end

  it 'a :no_change verification retry does not write the paid plan back over a cancellation that arrives during it' do
    strand_first_claim

    # Retry. Schedule the cancellation right after the claim has read the
    # pending record, inside its locked section.
    Timecop.freeze(initial_time + 5)
    injected                   = 0
    @cancel_after_pending_read = true
    allow(Billing::PendingFederatedSubscription).to receive(:find_by_email_hash).and_wrap_original do |original, *args|
      result = original.call(*args)
      if @cancel_after_pending_read && args.first == email_hash && Thread.current != @webhook_thread
        @cancel_after_pending_read = false
        injected                  += 1
        expect(result).not_to be_nil
        start_blocked_cancellation
      end
      result
    end

    retry_op = operator_verify
    expect(retry_op.call).to eq(:no_change)
    expect(retry_op.federation_claimed?).to be(true)
    expect(injected).to eq(1)

    # The webhook ran once the claim released the lock: its write is last.
    expect(@webhook_thread.value).to eq(:federated_only)
    expect_cancellation_preserved
  end

  it 'the first claim does not write the paid plan back over a cancellation that arrives after its scalar save' do
    expect(dispatch(build_event)).to eq(:pending_stored)
    provision_sso_workspace
    expect(pending_record).not_to be_nil

    # The claim's materialization saves the paid scalars (publishing the
    # email_hash index) before the claim's own final save. Schedule the
    # cancellation right after materialization returns.
    injected                  = 0
    @cancel_after_materialize = true
    allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:materialize_entitlements_for_org).and_wrap_original do |original, org, *args, **kwargs|
      result = original.call(org, *args, **kwargs)
      if @cancel_after_materialize && org.objid == @organization.objid && Thread.current != @webhook_thread
        @cancel_after_materialize = false
        injected                 += 1
        Timecop.freeze(initial_time + 5)
        expect(Onetime::Organization.find_federated_by_email_hash(email_hash).map(&:objid)).to include(@organization.objid)
        start_blocked_cancellation
      end
      result
    end

    op = operator_verify
    expect(op.call).to eq(:success)
    expect(op.federation_claimed?).to be(true)
    expect(injected).to eq(1)

    expect(@webhook_thread.value).to eq(:federated_only)
    expect_cancellation_preserved
  end

  # The claim loads the workspace (signup_workspace_for) before it takes the
  # lock. A cancellation that commits in between, and fails to retire the
  # pending record, must still win: the claim re-reads the org under the lock
  # and recognises the surviving record as older than the cancellation.
  it 'a retry re-reads the workspace under the lock and does not replay a snapshot the cancellation already superseded' do
    strand_first_claim

    Timecop.freeze(initial_time + 5)
    retirement_failures        = 0
    @inject_retirement_failure = false
    allow_any_instance_of(Billing::PendingFederatedSubscription).to receive(:destroy!).and_wrap_original do |original, *args|
      if @inject_retirement_failure
        @inject_retirement_failure = false
        retirement_failures       += 1
        raise Redis::BaseConnectionError, 'injected pending retirement failure after the cancellation'
      end
      original.call(*args)
    end

    injected            = 0
    @cancel_before_lock = true
    allow(Billing::PendingFederatedSubscription).to receive(:with_federation_lock).and_wrap_original do |original, *args, **kwargs, &block|
      if @cancel_before_lock && args.first == email_hash
        @cancel_before_lock        = false
        injected                  += 1
        @inject_retirement_failure = true
        expect(dispatch(cancellation_event)).to eq(:federated_only)
        expect(retirement_failures).to eq(1)
        expect(persisted_org.planid).to eq('free_v1')
        expect(persisted_org.subscription_status).to eq('canceled')
        expect(pending_record).not_to be_nil
      end
      original.call(*args, **kwargs, &block)
    end

    retry_op = operator_verify
    expect(retry_op.call).to eq(:no_change)
    expect(retry_op.federation_claimed?).to be(false)
    expect(injected).to eq(1)
    expect_cancellation_preserved
  end

  describe 'lock contention' do
    it 'a webhook that cannot take the lock raises for a retry and writes nothing' do
      strand_first_claim
      stub_const('Billing::Operations::WebhookHandlers::SubscriptionFederation::FEDERATION_LOCK_WAIT', 0.2)
      token = federation_lock.acquire(ttl: 30)
      expect(token).to be_truthy

      expect { dispatch(cancellation_event) }
        .to raise_error(Billing::PendingFederatedSubscription::FederationLockTimeout)

      expect(persisted_org.planid).to eq('identity_plus_v1')
      expect(persisted_org.subscription_status).to eq('active')
      expect(pending_record).not_to be_nil
      expect(federation_lock.held_by?(token)).to be(true)
    end

    it 'a claim that cannot take the lock leaves the pending record for the next retry' do
      strand_first_claim
      stub_const('Auth::Operations::EnsureDefaultWorkspace::CLAIM_LOCK_WAIT', 0.2)
      token = federation_lock.acquire(ttl: 30)

      blocked = operator_verify
      expect(blocked.call).to eq(:no_change)
      expect(blocked.federation_claimed?).to be(false)
      expect(pending_record).not_to be_nil

      federation_lock.release(token)
      retry_op = operator_verify
      expect(retry_op.call).to eq(:no_change)
      expect(retry_op.federation_claimed?).to be(true)
      refresh_workspace!
      expect(@organization.can?('custom_branding')).to be(true)
      expect(owner_membership.can?('custom_branding')).to be(true)
      expect(pending_record).to be_nil
    end
  end
end
