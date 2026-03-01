# apps/web/billing/spec/integration/pending_federation_spec.rb
#
# frozen_string_literal: true

# Integration tests for pending federation storage when webhooks fire
# before account exists in a region.
#
# Tests the flow:
# 1. Webhook fires → no matching org → pending record stored
# 2. User creates account → pending matched → benefits applied
#
# Run: pnpm run test:rspec apps/web/billing/spec/integration/pending_federation_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../operations/process_webhook_event/shared_examples'
require_relative '../../operations/process_webhook_event'
require_relative '../../models/pending_federated_subscription'

RSpec.describe 'PendingFederation: Webhook Storage', :integration, :process_webhook_event do
  include ProcessWebhookEventHelpers
  include BillingSpecHelper

  let(:unknown_email) { "future-user-#{SecureRandom.hex(4)}@example.com" }
  let(:email_hash) { Onetime::Utils::EmailHash.compute(unknown_email) }
  let(:stripe_customer_id) { "cus_pending_test_#{SecureRandom.hex(4)}" }
  let(:stripe_subscription_id) { "sub_pending_test_#{SecureRandom.hex(4)}" }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_pending_records) { [] }

  # Enable federation for all tests
  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  before do
    mock_billing_config!
  end

  after do
    created_pending_records.each { |rec| rec.destroy! rescue nil }
    created_organizations.each { |org| org.destroy! rescue nil }
    created_customers.each { |cust| cust.destroy! rescue nil }
  end

  def build_stripe_customer(id:, email:, metadata: {})
    Stripe::Customer.construct_from({
      id: id,
      object: 'customer',
      email: email,
      metadata: metadata,
    })
  end

  def track_pending(pending)
    created_pending_records << pending if pending
    pending
  end

  describe 'webhook stores pending when no org exists' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'email_hash' => email_hash },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: unknown_email,
        metadata: { 'email_hash' => email_hash, 'region' => 'EU' },
      )
      allow(Stripe::Customer).to receive(:retrieve)
        .with(stripe_customer_id)
        .and_return(stripe_customer)

      # No orgs exist - triggers pending storage
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).and_return(nil)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash).and_return([])
    end

    it 'returns :pending_stored when no org matches' do
      result = operation.call
      track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(result).to eq(:pending_stored)
    end

    it 'creates a PendingFederatedSubscription record' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending).not_to be_nil
    end

    it 'stores subscription status' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending.subscription_status).to eq('active')
    end

    it 'stores region from metadata' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending.region).to eq('EU')
    end

    it 'stores received_at timestamp' do
      freeze_time do
        operation.call
        pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
        expect(pending.received_at.to_i).to eq(Time.now.to_i)
      end
    end
  end

  describe 'duplicate webhooks: idempotent storage' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'email_hash' => email_hash },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: unknown_email,
        metadata: { 'email_hash' => email_hash },
      )
      allow(Stripe::Customer).to receive(:retrieve).and_return(stripe_customer)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).and_return(nil)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash).and_return([])
    end

    it 'overwrites existing record on duplicate webhook (idempotent)' do
      # First webhook
      operation.call

      # Second webhook with updated status
      updated_subscription = build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'past_due',
        metadata: { 'email_hash' => email_hash },
      )
      updated_event = build_stripe_event(type: 'customer.subscription.updated', data_object: updated_subscription)
      Billing::Operations::ProcessWebhookEvent.new(event: updated_event).call

      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending.subscription_status).to eq('past_due')
    end
  end

  describe 'canceled subscription: stored but not active' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'canceled',
        metadata: { 'email_hash' => email_hash },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: unknown_email,
        metadata: { 'email_hash' => email_hash },
      )
      allow(Stripe::Customer).to receive(:retrieve).and_return(stripe_customer)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).and_return(nil)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash).and_return([])
    end

    it 'stores pending record with canceled status' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending).not_to be_nil
      expect(pending.subscription_status).to eq('canceled')
    end

    it 'pending record is not active' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(email_hash))
      expect(pending.active?).to be false
    end
  end

  describe 'account already exists: normal federation path' do
    let(:owner_email) { "existing-owner-#{SecureRandom.hex(4)}@example.com" }
    let!(:owner_customer) { create_test_customer(email: owner_email) }
    let!(:owner_org) do
      org = create_test_organization(customer: owner_customer)
      org.stripe_customer_id = stripe_customer_id
      org.compute_email_hash!
      org.save
      org
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'email_hash' => owner_org.email_hash },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: owner_email,
        metadata: { 'email_hash' => owner_org.email_hash },
      )
      allow(Stripe::Customer).to receive(:retrieve).and_return(stripe_customer)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(owner_org)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash).and_return([])
    end

    it 'returns :owner_only (not :pending_stored)' do
      expect(operation.call).to eq(:owner_only)
    end

    it 'does NOT create a pending record' do
      operation.call
      pending = Billing::PendingFederatedSubscription.find_by_email_hash(owner_org.email_hash)
      expect(pending).to be_nil
    end

    it 'updates owner org directly' do
      operation.call
      owner_org.refresh!
      expect(owner_org.subscription_status).to eq('active')
    end
  end

  describe 'no email_hash in metadata: computed hash used' do
    let(:legacy_email) { "legacy-customer-#{SecureRandom.hex(4)}@example.com" }
    let(:computed_hash) { Onetime::Utils::EmailHash.compute(legacy_email) }

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: {},  # No email_hash - legacy customer
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: legacy_email,
        metadata: {},  # No email_hash in metadata
      )
      allow(Stripe::Customer).to receive(:retrieve).and_return(stripe_customer)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id).and_return(nil)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash).and_return([])
    end

    it 'stores pending with computed hash from email' do
      operation.call
      pending = track_pending(Billing::PendingFederatedSubscription.find_by_email_hash(computed_hash))
      expect(pending).not_to be_nil
    end
  end
end

RSpec.describe 'PendingFederatedSubscription Model', :unit do
  let(:email_hash) { "test_hash_#{SecureRandom.hex(8)}" }
  let(:created_pending_records) { [] }

  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  after do
    created_pending_records.each { |rec| rec.destroy! rescue nil }
  end

  def create_pending(hash: email_hash, status: 'active', period_end: nil)
    pending = Billing::PendingFederatedSubscription.new(hash)
    pending.subscription_status = status
    pending.subscription_period_end = (period_end || Time.now + 30 * 24 * 60 * 60).to_i.to_s
    pending.received_at = Time.now.to_i.to_s
    pending.save
    created_pending_records << pending
    pending
  end

  describe '#active?' do
    it 'returns true for active status' do
      pending = create_pending(status: 'active')
      expect(pending.active?).to be true
    end

    it 'returns true for trialing status' do
      pending = create_pending(status: 'trialing')
      expect(pending.active?).to be true
    end

    it 'returns true for past_due status (grace period)' do
      pending = create_pending(status: 'past_due')
      expect(pending.active?).to be true
    end

    it 'returns false for canceled status' do
      pending = create_pending(status: 'canceled')
      expect(pending.active?).to be false
    end

    it 'returns false for unpaid status' do
      pending = create_pending(status: 'unpaid')
      expect(pending.active?).to be false
    end
  end

  describe '#expired?' do
    it 'returns false for future period_end' do
      pending = create_pending(period_end: Time.now + 30 * 24 * 60 * 60)
      expect(pending.expired?).to be false
    end

    it 'returns true for past period_end' do
      pending = create_pending(period_end: Time.now - 1)
      expect(pending.expired?).to be true
    end

    it 'returns false for empty period_end' do
      pending = create_pending
      pending.subscription_period_end = nil
      pending.save
      expect(pending.expired?).to be false
    end
  end

  describe '.find_by_email_hash' do
    it 'finds existing pending record' do
      created = create_pending
      found = Billing::PendingFederatedSubscription.find_by_email_hash(email_hash)
      expect(found).not_to be_nil
      expect(found.subscription_status).to eq('active')
    end

    it 'returns nil for non-existent hash' do
      found = Billing::PendingFederatedSubscription.find_by_email_hash('nonexistent_hash')
      expect(found).to be_nil
    end

    it 'returns nil for empty hash' do
      found = Billing::PendingFederatedSubscription.find_by_email_hash('')
      expect(found).to be_nil
    end

    it 'returns nil for nil hash' do
      found = Billing::PendingFederatedSubscription.find_by_email_hash(nil)
      expect(found).to be_nil
    end
  end

  describe 'TTL/expiration' do
    it 'has 90 day default expiration' do
      expected_seconds = 90 * 24 * 60 * 60
      expect(Billing::PendingFederatedSubscription.default_expiration).to eq(expected_seconds)
    end
  end
end
