# apps/web/billing/spec/operations/process_webhook_event/federation/sso_mailbox_gate_spec.rb
#
# frozen_string_literal: true

# Regression for #4754 review F3: the direct federated sync in
# SubscriptionFederation#update_federated_org must respect the same mailbox
# gate as the deferred claim in EnsureDefaultWorkspace (#4735).
#
# An SSO JIT customer (verified_by 'sso') has not proven mailbox control, so
# EnsureDefaultWorkspace defers the PendingFederatedSubscription claim and
# leaves the record in place for SetCustomerVerification to re-claim later.
# If the default workspace has an email_hash anyway (written by
# `bin/ots migrations backfill-email-hash`, or computed before the deferral
# existed), a subscription webhook finds the org by hash and must not deliver
# the plan to it, nor destroy the pending record the deferral is keeping.
#
# #4754 review, F1: the rule is the customer record's
# (Customer#federation_claim_deferred?), and it also defers an UNVERIFIED
# standard signup while the deployment has a verification step. The billing
# lane boots in standalone mode, where verify_account_loaded? is false, so
# those examples stub the config predicate.
#
# The other examples pin the paths the gate leaves alone: a mailbox-verified
# owner, a verified owner with a non-mailbox provenance, a workspace that
# already has a federated plan, a cancellation, a pause, and a sibling
# workspace for the same hash.
#
# Lookups and writes are native. Only Stripe I/O and billing enablement are
# stubbed.
#
# Run: tests/lanes/run billing --only apps/web/billing/spec/operations/process_webhook_event/federation/sso_mailbox_gate_spec.rb

require_relative '../../../support/billing_spec_helper'
require_relative '../shared_examples'
require_relative '../../../../operations/process_webhook_event'
require_relative '../../../../models/pending_federated_subscription'
require 'auth/operations/ensure_default_workspace'
require 'auth/operations/set_customer_verification'

RSpec.describe 'ProcessWebhookEvent: federated sync honours the mailbox gate', :integration, :process_webhook_event do
  let(:email) { "sso-gate-#{SecureRandom.hex(8)}@example.com" }
  let(:email_hash) { Onetime::Utils::EmailHash.compute(email) }
  let(:stripe_customer_id) { "cus_sso_gate_#{SecureRandom.hex(6)}" }
  let(:stripe_subscription_id) { "sub_sso_gate_#{SecureRandom.hex(6)}" }
  let(:extra_organizations) { [] }
  let(:extra_customers) { [] }

  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  before do
    # The billing lane boots in standalone mode; enable paid entitlement readers.
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
  end

  after do
    Billing::PendingFederatedSubscription.find_by_email_hash(email_hash)&.destroy!
    Billing::PendingFederatedSubscription.unindex_recent(email_hash) rescue nil
    extra_organizations.each { |org| org.destroy! rescue nil }
    extra_customers.each { |cust| cust.destroy! rescue nil }
    @organization&.destroy! rescue nil
    @customer&.destroy! rescue nil
  end

  def pending_record
    Billing::PendingFederatedSubscription.find_by_email_hash(email_hash)
  end

  def subscription_event(type: 'customer.subscription.updated', status: 'active', plan: 'identity_plus_v1')
    Stripe::Event.construct_from({
      id: "evt_sso_gate_#{SecureRandom.hex(8)}",
      object: 'event',
      type: type,
      created: Time.now.to_i,
      data: {
        object: {
          id: stripe_subscription_id,
          object: 'subscription',
          customer: stripe_customer_id,
          status: status,
          metadata: { Billing::Metadata::FIELD_PLAN_ID => plan },
          items: { data: [{ current_period_end: (Time.now + (30 * 24 * 60 * 60)).to_i }] },
        },
      },
    })
  end

  def subscription_updated_event
    subscription_event
  end

  def dispatch(event)
    Billing::Operations::ProcessWebhookEvent.new(event: event).call
  end

  # A webhook before any account exists here stores the pending record.
  def store_initial_pending
    expect(dispatch(subscription_updated_event)).to eq(:pending_stored)
    expect(pending_record).not_to be_nil
  end

  # SSO JIT provisioning: IdP-asserted address, no mailbox proof. The claim
  # is deferred and the pending record is left for re-claim.
  def provision_sso_workspace
    @customer = Onetime::Customer.create!(
      email: email, role: 'customer', verified: true,
      verified_by: 'sso', provisioning_origin: 'sso_jit',
    )
    expect(@customer.verified?).to be(true)
    expect(@customer.mailbox_verified?).to be(false)

    @organization = Auth::Operations::EnsureDefaultWorkspace.new(
      customer: @customer, require_verification: true,
    ).call[:organization]
    expect(@organization.subscription_federated?).to be(false)
    expect(@organization.email_hash.to_s).to be_empty
  end

  # The workspace gains an email_hash without mailbox proof. The deferred
  # path returns before compute_email_hash!, but the org settings form sets
  # billing_email (UpdateOrganization) and the backfill command computes the
  # hash for any org with a billing_email and no hash
  # (backfill_email_hash_command.rb).
  def backfill_hash(org = @organization, billing_email: email)
    org.billing_email = billing_email
    org.compute_email_hash!
    org.save
    expect(org.email_hash).to eq(email_hash)
    expect(Onetime::Organization.find_federated_by_email_hash(email_hash).map(&:objid)).to include(org.objid)
  end

  it 'does not apply the plan to an SSO-only workspace or destroy its deferred pending record' do
    store_initial_pending
    provision_sso_workspace
    expect(pending_record).not_to be_nil
    backfill_hash

    # The next subscription webhook goes through the real handler path
    # (SubscriptionUpdated -> process_with_federation -> update_federated_org).
    second = subscription_updated_event
    dispatch(second)

    @organization.refresh!
    @customer.refresh!
    expect(@customer.mailbox_verified?).to be(false)

    aggregate_failures 'mailbox gate on the direct sync' do
      expect(@organization.subscription_federated?).to be(false)
      expect(@organization.planid.to_s).not_to eq('identity_plus_v1')
      expect(@organization.can?('custom_branding')).to be(false)
      expect(pending_record).not_to be_nil
    end

    # The deferred webhook refreshed the pending record: newest state wins.
    expect(pending_record.source_stripe_event_id).to eq(second.id)
  end

  it 'applies the refreshed pending record once an operator records mailbox proof' do
    store_initial_pending
    provision_sso_workspace
    backfill_hash
    dispatch(subscription_updated_event)
    expect(pending_record).not_to be_nil

    verification = Auth::Operations::SetCustomerVerification.new(
      customer: @customer, verified: true, verified_by: 'cli_provision',
    )
    expect(verification.call).to eq(:success)
    expect(verification.federation_claimed?).to be(true)

    @organization.refresh!
    expect(@organization.subscription_federated?).to be(true)
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(@organization.can?('custom_branding')).to be(true)
    expect(pending_record).to be_nil

    # Now mailbox-verified: the next webhook syncs the workspace directly.
    expect(dispatch(subscription_event(plan: 'free_v1'))).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.planid).to eq('free_v1')
    expect(pending_record).to be_nil
  end

  it 'still syncs a workspace whose owner has mailbox proof and retires the pending record' do
    store_initial_pending
    @customer = Onetime::Customer.create!(email: email, role: 'customer', verified: true, verified_by: 'email')
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call[:organization]
    @organization.refresh!
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(pending_record).to be_nil

    expect(dispatch(subscription_event(plan: 'free_v1'))).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.planid).to eq('free_v1')
    expect(@organization.can?('custom_branding')).to be(false)
    expect(pending_record).to be_nil
  end

  it 'still syncs a verified non-SSO owner with a non-mailbox provenance, as the claim path does' do
    # 'autoverify' is not mailbox proof, but the record is verified?, so the
    # deployment's verification step will never run for it again. The
    # predicate deliberately does not defer such a record, even with a
    # verification step enabled (see Customer#federation_claim_deferred?).
    allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(true)
    @customer = Onetime::Customer.create!(email: email, role: 'customer', verified: true, verified_by: 'autoverify')
    expect(@customer.mailbox_verified?).to be(false)
    expect(@customer.federation_claim_deferred?).to be(false)
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call[:organization]
    backfill_hash

    expect(dispatch(subscription_updated_event)).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.subscription_federated?).to be(true)
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(pending_record).to be_nil
  end

  # Standard signup on a deployment with a verification step: the customer is
  # unverified, the signup hook defers the claim, and the webhook gate must
  # read the same rule off the record (#4754 review, F1).
  def provision_unverified_signup_workspace
    @customer = Onetime::Customer.create!(email: email, role: 'customer', provisioning_origin: 'canonical_signup')
    expect(@customer.verified?).to be(false)
    expect(@customer.federation_claim_deferred?).to be(true)

    @organization = Auth::Operations::EnsureDefaultWorkspace.new(
      customer: @customer, require_verification: true,
    ).call[:organization]
    expect(@organization.subscription_federated?).to be(false)
    expect(@organization.email_hash.to_s).to be_empty
  end

  describe 'an unverified standard signup on a deployment with a verification step' do
    before { allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(true) }

    it 'does not apply the plan to the workspace or destroy its deferred pending record' do
      store_initial_pending
      provision_unverified_signup_workspace
      expect(pending_record).not_to be_nil
      backfill_hash

      second = subscription_updated_event
      expect(dispatch(second)).to eq(:federated_only)

      @organization.refresh!
      aggregate_failures 'mailbox gate on the direct sync' do
        expect(@organization.subscription_federated?).to be(false)
        expect(@organization.planid.to_s).not_to eq('identity_plus_v1')
        expect(@organization.can?('custom_branding')).to be(false)
        expect(pending_record).not_to be_nil
        expect(pending_record.source_stripe_event_id).to eq(second.id)
      end
    end

    it 'applies the refreshed pending record once the verification step stamps mailbox proof' do
      store_initial_pending
      provision_unverified_signup_workspace
      backfill_hash
      dispatch(subscription_updated_event)
      expect(pending_record).not_to be_nil

      # after_verify_account: Rodauth has committed the Verified row and the
      # hook stamps 'email'.
      verification = Auth::Operations::SetCustomerVerification.new(
        customer: @customer, verified: true, verified_by: 'email', rodauth_already_synced: true,
      )
      expect(verification.call).to eq(:success)
      expect(verification.federation_claimed?).to be(true)

      @organization.refresh!
      expect(@organization.subscription_federated?).to be(true)
      expect(@organization.planid).to eq('identity_plus_v1')
      expect(@organization.can?('custom_branding')).to be(true)
      expect(pending_record).to be_nil

      expect(dispatch(subscription_event(plan: 'free_v1'))).to eq(:federated_only)
      @organization.refresh!
      expect(@organization.planid).to eq('free_v1')
    end

    it 'keeps updating an unverified workspace that already has an active federated plan' do
      # The carve-out (federated_benefit_active?) is independent of the owner
      # rule: a plan granted on an earlier release keeps receiving downgrades
      # and lapses; only a new grant waits for proof.
      provision_unverified_signup_workspace
      backfill_hash
      Billing::Operations::ApplySubscriptionToOrg.call(
        @organization, subscription_updated_event.data.object, owner: false, save: false
      )
      @organization.mark_subscription_federated!
      @organization.save
      @organization.refresh!
      expect(@organization.planid).to eq('identity_plus_v1')
      expect(Billing::PendingFederatedSubscription.awaiting_mailbox_proof?(@organization)).to be(false)

      expect(dispatch(subscription_event(plan: 'free_v1'))).to eq(:federated_only)
      @organization.refresh!
      expect(@organization.planid).to eq('free_v1')
      expect(@organization.can?('custom_branding')).to be(false)
      expect(pending_record).to be_nil

      # Without a paid plan the next grant waits for the mailbox proof.
      expect(Billing::PendingFederatedSubscription.awaiting_mailbox_proof?(@organization)).to be(true)
      dispatch(subscription_updated_event)
      @organization.refresh!
      expect(@organization.planid).to eq('free_v1')
      expect(pending_record).not_to be_nil
    end
  end

  it 'syncs an unverified standard signup directly when the deployment has no verification step' do
    # The documented residual: with verify_account off, nothing will ever
    # prove the address, so the claim path claims at signup and the webhook
    # gate does not defer either.
    allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(false)
    @customer = Onetime::Customer.create!(email: email, role: 'customer', provisioning_origin: 'canonical_signup')
    expect(@customer.federation_claim_deferred?).to be(false)
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer, require_verification: true).call[:organization]
    backfill_hash

    expect(dispatch(subscription_updated_event)).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.subscription_federated?).to be(true)
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(pending_record).to be_nil
  end

  it 'stores the subscription as pending for an unverified standard signup when the process resolved simple mode by default' do
    # bin/ots billing webhooks replay from a host shell, or a billing worker
    # started without AUTHENTICATION_MODE, resolves simple mode on a full-mode
    # install and reads verify_account_loaded? as false with nothing raised.
    # The record rule fails closed on the unsettled mode, so the direct sync
    # defers like the claim instead of applying the plan to a workspace whose
    # owner the install has yet to verify (#4754 review, F1 follow-up).
    allow(Onetime.auth_config).to receive_messages(simple_by_default?: true, verify_account_loaded?: false)
    store_initial_pending
    @customer = Onetime::Customer.create!(email: email, role: 'customer', provisioning_origin: 'canonical_signup')
    expect(@customer.federation_claim_deferred?).to be(true)
    @organization = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call[:organization]
    expect(@organization.subscription_federated?).to be(false)
    expect(pending_record).not_to be_nil
    backfill_hash

    second = subscription_updated_event
    expect(dispatch(second)).to eq(:federated_only)

    @organization.refresh!
    aggregate_failures 'mailbox gate on an unsettled auth mode' do
      expect(@organization.subscription_federated?).to be(false)
      expect(@organization.planid.to_s).not_to eq('identity_plus_v1')
      expect(@organization.can?('custom_branding')).to be(false)
      expect(pending_record).not_to be_nil
      expect(pending_record.source_stripe_event_id).to eq(second.id)
    end
  end

  it 'keeps updating an SSO workspace that already has an active federated plan' do
    # The state an SSO default workspace created before the deferral existed
    # can be in: hashed and federated at creation.
    provision_sso_workspace
    backfill_hash
    Billing::Operations::ApplySubscriptionToOrg.call(
      @organization, subscription_updated_event.data.object, owner: false, save: false
    )
    @organization.mark_subscription_federated!
    @organization.save
    @organization.refresh!
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(@organization.can?('custom_branding')).to be(true)

    # A downgrade reaches it.
    expect(dispatch(subscription_event(plan: 'free_v1'))).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.planid).to eq('free_v1')
    expect(@organization.can?('custom_branding')).to be(false)
    expect(pending_record).to be_nil

    # Once it no longer has a paid plan, a new grant waits for proof.
    dispatch(subscription_updated_event)
    @organization.refresh!
    expect(@organization.planid).to eq('free_v1')
    expect(pending_record).not_to be_nil
  end

  it 'applies a cancellation to a deferred workspace and retires the pending record' do
    store_initial_pending
    provision_sso_workspace
    backfill_hash

    expect(dispatch(subscription_event(type: 'customer.subscription.deleted', status: 'canceled'))).to eq(:federated_only)
    @organization.refresh!
    expect(@organization.subscription_status).to eq('canceled')
    expect(@organization.planid).to eq('free_v1')
    expect(@organization.can?('custom_branding')).to be(false)
    expect(pending_record).to be_nil
  end

  it 'refreshes the pending record when a deferred workspace is paused, without marking it synced' do
    store_initial_pending
    provision_sso_workspace
    backfill_hash

    paused = subscription_event(type: 'customer.subscription.paused', status: 'paused')
    dispatch(paused)
    @organization.refresh!
    expect(@organization.subscription_status).to eq('paused')
    # The deferred workspace received nothing, so it records no sync, and the
    # refreshed record survives for the claim that follows verification.
    expect(@organization.subscription_sync_version.to_s).to be_empty
    expect(pending_record).not_to be_nil
    expect(pending_record.subscription_status).to eq('paused')
    expect(pending_record.source_stripe_event_id).to eq(paused.id)
    expect(pending_record.active?).to be(false)
  end

  # #4754 review (NB): for a workspace that is not deferred the pause is a
  # direct sync, so it must record the sync order and retire a stale active
  # record as update_federated_org and clear_federated_org do. Without that,
  # a record stored before the workspace had its email hash survived the
  # pause, and the next claim retry (a repeat verification of the owner)
  # replayed its active snapshot over the pause.
  describe 'a pause reaching a workspace whose owner has mailbox proof' do
    def provision_mailbox_verified_workspace
      @customer = Onetime::Customer.create!(email: email, role: 'customer', verified: true, verified_by: 'email')
      org       = Auth::Operations::EnsureDefaultWorkspace.new(customer: @customer).call[:organization]
      # Nothing was pending at creation, so the claim computed the hash in
      # memory and never saved it. Reload rather than refresh!, which keeps
      # in-memory fields that Redis lacks.
      @organization = Onetime::Organization.load(org.objid)
      expect(@organization.email_hash.to_s).to be_empty
    end

    it 'records the sync order and retires the stale active record, so a claim retry cannot replay it' do
      provision_mailbox_verified_workspace
      store_initial_pending
      stored_version = pending_record.sync_version
      backfill_hash

      expect(dispatch(subscription_event(type: 'customer.subscription.paused', status: 'paused'))).to eq(:federated_only)
      @organization.refresh!
      aggregate_failures 'pause as a direct sync' do
        expect(@organization.subscription_status).to eq('paused')
        expect(@organization.subscription_sync_version.to_i).to be > stored_version.to_i
        expect(@organization.subscription_synced_at.to_s).not_to be_empty
        expect(pending_record).to be_nil
      end

      # The documented retry: a repeat verification with the same proof.
      verification = Auth::Operations::SetCustomerVerification.new(customer: @customer, verified: true, verified_by: 'email')
      expect(verification.call).to eq(:no_change)
      expect(verification.federation_claimed?).to be(false)
      @organization.refresh!
      expect(@organization.subscription_status).to eq('paused')
      expect(@organization.planid.to_s).not_to eq('identity_plus_v1')
    end

    it "keeps a deferred sibling's refreshed record when the same pause also reaches a synced workspace" do
      store_initial_pending
      provision_sso_workspace
      backfill_hash
      team_owner = Onetime::Customer.create!(
        email: "team-owner-#{SecureRandom.hex(6)}@example.com", role: 'customer', verified: true, verified_by: 'email',
      )
      extra_customers << team_owner
      team_org = Onetime::Organization.create!('Team', team_owner, team_owner.email)
      extra_organizations << team_org
      backfill_hash(team_org, billing_email: email.upcase)

      paused = subscription_event(type: 'customer.subscription.paused', status: 'paused')
      expect(dispatch(paused)).to eq(:federated_only)

      team_org.refresh!
      @organization.refresh!
      aggregate_failures 'synced sibling and deferred workspace' do
        expect(team_org.subscription_status).to eq('paused')
        expect(team_org.subscription_sync_version.to_s).not_to be_empty
        expect(@organization.subscription_status).to eq('paused')
        expect(@organization.subscription_sync_version.to_s).to be_empty
        expect(pending_record).not_to be_nil
        expect(pending_record.subscription_status).to eq('paused')
        expect(pending_record.source_stripe_event_id).to eq(paused.id)
      end
    end
  end

  it 'does not retire the pending record of a deferred workspace when a sibling workspace syncs' do
    store_initial_pending
    provision_sso_workspace
    backfill_hash

    # Another workspace in this region whose billing email differs only in
    # case (billing_email is unique verbatim; the hash is case-folded), owned
    # by a customer with mailbox proof.
    team_owner = Onetime::Customer.create!(
      email: "team-owner-#{SecureRandom.hex(6)}@example.com", role: 'customer', verified: true, verified_by: 'email',
    )
    extra_customers << team_owner
    team_org = Onetime::Organization.create!('Team', team_owner, team_owner.email)
    extra_organizations << team_org
    backfill_hash(team_org, billing_email: email.upcase)

    second = subscription_updated_event
    expect(dispatch(second)).to eq(:federated_only)

    team_org.refresh!
    @organization.refresh!
    expect(team_org.planid).to eq('identity_plus_v1')
    expect(@organization.planid.to_s).not_to eq('identity_plus_v1')
    expect(pending_record).not_to be_nil
    expect(pending_record.source_stripe_event_id).to eq(second.id)
  end

  # A sibling workspace for the same hash that the sibling's owner owns as a
  # default workspace, so a mailbox-verified call for that owner re-claims it
  # (EnsureDefaultWorkspace.claim_pending_federation_for). The owner's own
  # address hashes differently; the billing email differs from the deferred
  # workspace's only in case.
  def provision_sibling_default_workspace(verified_by:)
    owner = Onetime::Customer.create!(
      email: "sibling-owner-#{SecureRandom.hex(6)}@example.com",
      role: 'customer',
      verified: !verified_by.nil?,
      verified_by: verified_by,
    )
    extra_customers << owner
    org = Auth::Operations::EnsureDefaultWorkspace.new(
      customer: owner, require_verification: verified_by.nil?,
    ).call[:organization]
    extra_organizations << org
    backfill_hash(org, billing_email: email.upcase)
    [owner, org]
  end

  def operator_verify(customer, verified_by)
    Auth::Operations::SetCustomerVerification.new(
      customer: customer, verified: true, verified_by: verified_by,
    ).call
  end

  it "keeps the deferred workspace's pending record when a sibling's re-claim finds it superseded" do
    store_initial_pending
    provision_sso_workspace
    backfill_hash
    sibling_owner, sibling_org = provision_sibling_default_workspace(verified_by: 'email')

    # The webhook syncs the sibling directly and keeps the record for the
    # deferred workspace (the sibling rule in discard_superseded_pending).
    second = subscription_updated_event
    expect(dispatch(second)).to eq(:federated_only)
    sibling_org.refresh!
    expect(sibling_org.planid).to eq('identity_plus_v1')
    expect(pending_record.superseded_by?(sibling_org)).to be(true)

    # A repeat verification of the sibling's owner re-claims on :no_change.
    # The record is superseded for the sibling, but the deferred workspace
    # still needs it.
    expect(operator_verify(sibling_owner, 'email')).to eq(:no_change)
    expect(pending_record).not_to be_nil
    expect(pending_record.source_stripe_event_id).to eq(second.id)

    # The deferred workspace's claim applies it once its owner proves the
    # mailbox, and that claim consumes it.
    expect(operator_verify(@customer, 'cli_provision')).to eq(:success)
    @organization.refresh!
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(@organization.can?('custom_branding')).to be(true)
    expect(pending_record).to be_nil
  end

  it "keeps the deferred workspace's pending record when a sibling's claim applies it" do
    store_initial_pending
    provision_sso_workspace
    backfill_hash
    sibling_owner, sibling_org = provision_sibling_default_workspace(verified_by: nil)

    # The sibling's owner verifies the mailbox; its claim applies the record.
    expect(operator_verify(sibling_owner, 'email')).to eq(:success)
    sibling_org.refresh!
    expect(sibling_org.planid).to eq('identity_plus_v1')
    expect(pending_record).not_to be_nil
    expect(pending_record.superseded_by?(sibling_org)).to be(true)

    # A repeat verification does not apply it to the sibling again.
    expect(operator_verify(sibling_owner, 'email')).to eq(:no_change)
    expect(pending_record).not_to be_nil

    expect(operator_verify(@customer, 'cli_provision')).to eq(:success)
    @organization.refresh!
    expect(@organization.planid).to eq('identity_plus_v1')
    expect(pending_record).to be_nil
  end
end
