# apps/web/auth/spec/operations/create_default_workspace_federation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Security regression tests for the pending-federated-subscription claim gate
# in Auth::Operations::CreateDefaultWorkspace.
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
# (require_verification: true), and re-invokes it from after_verify_account via
# CreateDefaultWorkspace.claim_pending_federation_for. Pre-verified/trusted
# callers (SSO, invite, post-payment billing, authenticated lazy creation) use
# the default (require_verification: false) and claim immediately.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/web/auth/spec/operations/create_default_workspace_federation_spec.rb
#
# =============================================================================

require 'spec_helper'
require 'securerandom'

RSpec.describe 'CreateDefaultWorkspace: federated subscription claim gate', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/create_default_workspace'
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

  def create_customer(email:, verified:)
    cust = Onetime::Customer.create!(email: email, role: 'customer', verified: verified)
    created_customers << cust
    cust
  end

  # Simulate a Stripe webhook that arrived before the account existed here.
  def create_pending_for(email, status: 'active', planid: 'pro_monthly')
    hash = Onetime::Utils::EmailHash.compute(email)
    pending = Billing::PendingFederatedSubscription.new(hash)
    pending.subscription_status     = status
    pending.planid                  = planid
    pending.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
    pending.region                  = 'US'
    pending.received_at             = Time.now.to_i.to_s
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

      result = Auth::Operations::CreateDefaultWorkspace.new(
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
      result = Auth::Operations::CreateDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)
      expect(pending_exists?(email)).to be(true)

      # Verification happens (mirrors after_verify_account marking the customer
      # verified before re-invoking the claim).
      customer.verified = true
      customer.save

      applied = Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(customer)
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
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(true)
      expect(org.subscription_status.to_s).to eq('active')
      expect(pending_exists?(email)).to be(false)
    end

    it 'claims at creation on the default (require_verification: false) path even ' \
       'when the Redis customer.verified flag is not yet set (SSO/omniauth caller)' do
      # The SSO caller (after_omniauth_create_account) invokes CreateDefaultWorkspace
      # with the default require_verification: false, while CreateCustomer leaves the
      # Redis customer.verified flag false (the Rodauth account is IdP-verified). This
      # asserts SSO still claims immediately and is not blocked by the new gate.
      email = unique_email('sso-immediate')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      result = Auth::Operations::CreateDefaultWorkspace.new(
        customer: customer,
        require_verification: false,
      ).call
      org = result[:organization]
      created_organizations << org

      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency / safety of the verify-path claim entry point
  # ---------------------------------------------------------------------------
  describe 'claim_pending_federation_for is idempotent and safe' do
    it 'is a no-op when there is no pending record' do
      email = unique_email('none-pending')
      customer = create_customer(email: email, verified: true)

      result = Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(false)

      # No pending was ever stored -> safe no-op, no error.
      applied = Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(false)
    end

    it 'does not double-apply when the subscription was already claimed' do
      email = unique_email('already-claimed')
      create_pending_for(email)
      customer = create_customer(email: email, verified: true)

      # First claim consumes the pending record.
      result = Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
      org = result[:organization]
      created_organizations << org
      expect(org.subscription_federated?).to be(true)
      expect(pending_exists?(email)).to be(false)

      # Second invocation (as after_verify_account would do) is a safe no-op.
      applied = Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)

      org.refresh!
      expect(org.subscription_federated?).to be(true)
    end

    it 'is a no-op when the customer is not verified' do
      email = unique_email('claim-unverified')
      create_pending_for(email)
      customer = create_customer(email: email, verified: false)

      # Workspace exists but the customer never verified.
      result = Auth::Operations::CreateDefaultWorkspace.new(
        customer: customer,
        require_verification: true,
      ).call
      created_organizations << result[:organization]

      applied = Auth::Operations::CreateDefaultWorkspace.claim_pending_federation_for(customer)
      expect(applied).to be(false)
      expect(pending_exists?(email)).to be(true)
    end
  end
end
