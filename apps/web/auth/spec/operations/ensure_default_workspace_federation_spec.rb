# apps/web/auth/spec/operations/ensure_default_workspace_federation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Security regression tests for the pending-federated-subscription claim gate
# in Auth::Operations::EnsureDefaultWorkspace.
#
# Background
# ----------
# Stripe webhooks fan out to every region. When a checkout completes but no
# local org matches the account's email hash, the region stores a
# PendingFederatedSubscription keyed by HMAC email_hash. Later, when a user
# creates an account in that region, the pending record is claimed and applied.
#
# The gap these tests lock down: on the STANDARD email/password signup path the
# claim used to run from after_create_account, BEFORE the user proved ownership
# of the email. An attacker who knew a paying subscriber's email could register
# it in another region and steal (and destroy) the victim's pending
# subscription at account-creation time.
#
# The fix defers the claim on that path until the email is verified
# (require_verification: true), and re-invokes it through
# EnsureDefaultWorkspace.claim_pending_federation_for once SetCustomerVerification
# stamps a mailbox-proof provenance (after_verify_account, colonel admin, CLI).
# Mailbox-proven callers (invite, post-payment billing, authenticated lazy
# creation) use the default (require_verification: false) and claim immediately.
#
# #4735: the SSO JIT caller is NOT pre-verified in the sense that matters. The
# IdP asserted the address (verified_by: 'sso'); nobody proved mailbox control.
# That caller now passes require_verification: true, and the operation defers
# for an sso_jit record on EVERY path, so a later lazy creation cannot deliver
# the benefit the JIT path withheld. Only Customer#mailbox_verified? (an
# 'email'/'invite_token'/'cli_provision'/'colonel_admin' stamp) lets it through.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=full
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/web/auth/spec/operations/ensure_default_workspace_federation_spec.rb
#
# =============================================================================

require 'spec_helper'
require 'securerandom'

RSpec.describe 'EnsureDefaultWorkspace: federated subscription claim gate', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/ensure_default_workspace'
    require 'billing/models/pending_federated_subscription'
  end

  # Federation requires a configured HMAC secret; EmailHash.compute reads it
  # from ENV first (see lib/onetime/utils/email_hash.rb).
  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_pending_records) { [] }

  after do
    created_organizations.each { |org| org.delete! if org&.exists? rescue nil }
    created_customers.each { |cust| cust.delete! if cust&.exists? rescue nil }
    created_pending_records.each { |rec| rec.destroy! rescue nil }
  end

  def unique_email(prefix = 'fed')
    "#{prefix}-#{SecureRandom.hex(8)}@federation-test.example.com"
  end

  def create_customer(email:, verified:, verified_by: nil, provisioning_origin: nil)
    cust = Onetime::Customer.create!(
      email: email, role: 'customer', verified: verified,
      verified_by: verified ? verified_by : nil, provisioning_origin: provisioning_origin,
    )
    created_customers << cust
    cust
  end

  # Simulate a Stripe webhook that arrived before the account existed here.
  def create_pending_for(email, status: 'active', planid: 'pro_monthly', received_at: Time.now.to_i)
    hash = Onetime::Utils::EmailHash.compute(email)
    pending = Billing::PendingFederatedSubscription.new(hash)
    pending.subscription_status     = status
    pending.planid                  = planid
    pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
    pending.region                  = 'US'
    pending.received_at             = received_at.to_s
    pending.save
    created_pending_records << pending
    pending
  end

  def pending_exists?(email)
    hash = Onetime::Utils::EmailHash.compute(email)
    !Billing::PendingFederatedSubscription.find_by_email_hash(hash).nil?
  end

  # ---------------------------------------------------------------------------
  # Standard (unverified) signup: claim must be DEFERRED
  # ---------------------------------------------------------------------------
  describe 'standard signup before email verification (require_verification: true)' do
    it 'creates the workspace but does NOT claim or destroy the pending record' do
      email = unique_email('standard-unverified')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call

      org = result[:organization]
      created_organizations << org

      # Workspace itself is still provisioned at signup...
      expect(org).to be_a(Onetime::Organization)
      expect(org.is_default).to be true

      # ...but the federated subscription is NOT claimed.
      expect(org.subscription_federated?).to be(false)
      expect(org.subscription_status.to_s).to eq('')

      # And crucially the victim's pending record survives (not stolen).
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # After verification: the deferred claim is applied
  # ---------------------------------------------------------------------------
  describe 'after the standard signup verifies their email' do
    it 'claims and applies the pending subscription, then consumes the record' do
      email = unique_email('standard-verify')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = create_customer(email: email, verified: false)

      # Signup: workspace created, claim deferred.
      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)

      # Verification happens (mirrors after_verify_account stamping the
      # mailbox-proof 'email' provenance before re-invoking the claim).
      customer.verified    = true
      customer.verified_by = 'email'
      customer.save

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(true)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(org.planid.to_s).to eq('pro_monthly')

      # Pending record consumed exactly once.
      expect(pending_exists?(email)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-verified callers claim immediately (no regression)
  # ---------------------------------------------------------------------------
  describe 'pre-verified callers claim immediately' do
    it 'claims at creation for an already-verified customer (invite path)' do
      email = unique_email('verified-immediate')
      create_pending_for(email)
      customer = create_customer(email: email, verified: true, verified_by: 'invite_token')

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(pending_exists?(email)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # SSO JIT (#4735): an IdP-asserted address is not mailbox proof
  # ---------------------------------------------------------------------------
  describe 'an SSO JIT-provisioned customer (verified_by: sso)' do
    def sso_customer(email)
      create_customer(email: email, verified: true, verified_by: 'sso', provisioning_origin: 'sso_jit')
    end

    it 'does not claim at creation when the JIT caller passes require_verification: true' do
      email = unique_email('sso-jit')
      create_pending_for(email)
      customer = sso_customer(email)
      expect(customer.verified?).to be(true)
      expect(customer.mailbox_verified?).to be(false)

      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      org = result[:organization]
      created_organizations << org

      expect(org.is_default).to be true
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'does not claim on the default path either (lazy creation cannot deliver what JIT deferred)' do
      email = unique_email('sso-lazy')
      create_pending_for(email)
      customer = sso_customer(email)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'does not claim for a held sso_jit record (idp_unverified) on the default path' do
      email = unique_email('sso-held')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false, provisioning_origin: 'sso_jit')
      customer.verification_hold = 'idp_unverified'
      customer.save

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      created_organizations << result[:organization]

      expect(result[:organization].subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end

    it 'claims once an operator stamps a mailbox-proof provenance (the re-claim trigger)' do
      email = unique_email('sso-operator-verify')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = sso_customer(email)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer, require_verification: true).call
      org = result[:organization]
      created_organizations << org
      expect(pending_exists?(email)).to be(true)

      # `bin/ots customers verify` / colonel admin: verified stays true, only
      # the provenance moves to a mailbox-proof value. Rodauth is already
      # Verified for an SSO account, so this is a Redis-only write.
      outcome = Auth::Operations::SetCustomerVerification.new(
        customer: customer,
        verified: true,
        verified_by: 'cli_provision',
        rodauth_already_synced: true,
      ).call
      expect(outcome).to eq(:success)
      expect(customer.mailbox_verified?).to be(true)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
      expect(org.planid.to_s).to eq('pro_monthly')
      expect(pending_exists?(email)).to be(false)
    end

    it 'does not claim when the re-verification keeps an IdP-asserted provenance' do
      email = unique_email('sso-still-sso')
      create_pending_for(email)
      customer = sso_customer(email)
      created_organizations << Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)

      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # A workspace that owns a local subscription is never a federation target
  # ---------------------------------------------------------------------------
  describe 'a default workspace that already owns a local subscription' do
    # The deferred re-claim can arrive long after signup: an SSO customer
    # subscribes locally while the cross-region record waits on mailbox proof.
    # Applying the pending record would overwrite the local plan, status and
    # period end, keep the local Stripe subscription id, and destroy the
    # pending record — two sources of truth for one workspace (#4735 review).
    it 'refuses the re-claim, keeps the local plan and leaves the pending record intact' do
      email = unique_email('local-owner')
      create_pending_for(email, status: 'active', planid: 'pro_monthly')
      customer = create_customer(email: email, verified: true, verified_by: 'sso', provisioning_origin: 'sso_jit')

      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer, require_verification: true).call[:organization]
      created_organizations << org
      expect(pending_exists?(email)).to be(true)

      # Local checkout completes before the operator verifies the address.
      local_sub                   = "sub_local_#{SecureRandom.hex(6)}"
      org.stripe_customer_id      = "cus_local_#{SecureRandom.hex(6)}"
      org.stripe_subscription_id  = local_sub
      org.planid                  = 'team_yearly'
      org.subscription_status     = 'trialing'
      org.subscription_period_end = '1999999999'
      org.save

      customer.verified_by = 'cli_provision'
      customer.save
      expect(customer.mailbox_verified?).to be(true)

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.planid.to_s).to eq('team_yearly')
      expect(org.subscription_status.to_s).to eq('trialing')
      expect(org.subscription_period_end.to_s).to eq('1999999999')
      expect(org.stripe_subscription_id).to eq(local_sub)
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Planless pending records must not be claimed (cross-region catalog miss)
  # ---------------------------------------------------------------------------
  describe 'pending record without a resolved planid' do
    # Regression: PendingFederatedSubscription used to resolve the plan via
    # local catalog lookup, which fails by design for cross-region price IDs,
    # storing planid=nil. Claiming such a record marked the org federated
    # (showing the "subscription synced" notification) while applying no
    # benefit, and destroyed the pending record so nothing could retry.
    it 'skips the claim, does not mark federated, and preserves the pending record' do
      email = unique_email('planless')
      create_pending_for(email, planid: nil)
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      # Workspace exists, but no phantom federation happened: no synced
      # notification, no subscription status, planid stays the free default.
      expect(org.subscription_federated?).to be(false)
      expect(org.show_federation_notification?).to be(false)
      expect(org.subscription_status.to_s).to eq('')
      expect(org.planid.to_s).to eq(Billing::Metadata::FREE_PLAN_ID)

      # The pending record survives for the webhook path to re-sync later.
      expect(pending_exists?(email)).to be(true)

      # The verify-path entry point also refuses it.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency / safety of the verify-path claim entry point
  # ---------------------------------------------------------------------------
  describe 'claim_pending_federation_for is idempotent and safe' do
    it 'is a no-op when there is no pending record' do
      email = unique_email('none-pending')
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)

      # No pending was ever stored -> safe no-op, no error.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(false)
    end

    it 'does not double-apply when the subscription was already claimed' do
      email = unique_email('already-claimed')
      create_pending_for(email)
      # 'email' provenance: the re-claim gate is mailbox_verified?, so a bare
      # verified: true would skip at the gate and pass this example vacuously.
      customer = create_customer(email: email, verified: true, verified_by: 'email')

      # First claim consumes the pending record.
      result = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)

      # Second invocation (as after_verify_account would do) is a safe no-op.
      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
    end

    # The first claim saved the org but failed to destroy the record; a
    # cancellation webhook then reached the org directly. An operator's
    # verification retry must not replay the surviving snapshot over the
    # cancellation (#4735 review, F8).
    it 'discards a surviving record the first claim already applied instead of replaying it' do
      email = unique_email('replayed-snapshot')
      pending = create_pending_for(email)
      customer = create_customer(email: email, verified: true, verified_by: 'email')

      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)

      # The record as it would have survived a failed destroy!: same hash, same
      # received_at (the claim ran in the same second it was stored).
      create_pending_for(email, received_at: pending.received_at)

      # Cancellation synced straight to the org by the webhook path.
      org.subscription_status = 'canceled'
      org.planid              = 'free_v1'
      org.save

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_status).to eq('canceled')
      expect(org.planid).to eq('free_v1')
      expect(pending_exists?(email)).to be(false), 'the replayed snapshot must be consumed, not kept for the next retry'
    end

    it 'still applies a record received after the workspace was federated' do
      email = unique_email('newer-record')
      customer = create_customer(email: email, verified: true, verified_by: 'email')
      org = Auth::Operations::EnsureDefaultWorkspace.new(customer: customer).call[:organization]
      created_organizations << org
      org.subscription_federated_at = Time.now.to_i - 3600
      org.save

      create_pending_for(email, planid: 'identity_monthly')

      expect(Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)).to be(true)
      org.refresh!
      expect(org.planid.to_s).to eq('identity_monthly')
      expect(pending_exists?(email)).to be(false)
    end

    it 'is a no-op when the customer is not verified' do
      email = unique_email('claim-unverified')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      # Workspace exists but the customer never verified.
      result = Auth::Operations::EnsureDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      created_organizations << result[:organization]

      applied = Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end
end
