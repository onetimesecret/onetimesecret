# apps/web/billing/spec/operations/process_webhook_event/subscription_created_spec.rb
#
# frozen_string_literal: true

# Tests for customer.subscription.created webhook event handling (#4230).
#
# This handler exists for cross-region federation. Before it, federation ran on
# updated/deleted/paused/resumed only, so a purchase in region B by someone who
# already had an org in region A never propagated until a later event on the
# same subscription happened to fire.
#
# The owner path deliberately writes nothing — checkout.session.completed owns
# that write path in the purchasing region. See the handler's class comment.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/subscription_created_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.subscription.created', :integration, :process_webhook_event do
  let(:owner_email) { "created-owner-#{SecureRandom.hex(4)}@example.com" }
  let(:federated_email) { "created-fed-#{SecureRandom.hex(4)}@example.com" }

  let(:stripe_customer_id) { 'cus_created_test_123' }
  let(:stripe_subscription_id) { 'sub_created_test_456' }
  let(:prior_subscription_id) { 'sub_created_test_prior' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:event) { build_stripe_event(type: 'customer.subscription.created', data_object: subscription) }
  let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

  after do
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

  describe 'handler registration' do
    it 'registers a handler for customer.subscription.created' do
      handler = Billing::Operations::ProcessWebhookEvent.handler_registry
        .find { |h| h.handles?('customer.subscription.created') }

      expect(handler).to eq(Billing::Operations::WebhookHandlers::SubscriptionCreated)
    end

    it 'no longer returns :unhandled for the event type' do
      # The regression this handler fixes: the event had no handler at all.
      expect(Billing::Operations::ProcessWebhookEvent.handler_registry)
        .to include(Billing::Operations::WebhookHandlers::SubscriptionCreated)
    end
  end

  context 'with federation enabled' do
    around do |example|
      original_secret = ENV['FEDERATION_SECRET']
      ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
      example.run
    ensure
      ENV['FEDERATION_SECRET'] = original_secret
    end

    # Prevent real Stripe API calls from record_federation_note
    before do
      allow(Stripe::Customer).to receive(:update).and_return(
        Stripe::Customer.construct_from({ id: 'cus_stubbed', object: 'customer', metadata: {} })
      )
    end

    describe 'federated organization in another region (the fix)' do
      let!(:federated_customer) { create_test_customer(email: federated_email) }
      let!(:federated_org) do
        org = create_test_organization(customer: federated_customer)
        org.stripe_customer_id = nil # not an owner - this is the region A org
        org.subscription_status = nil
        # billing_email is what compute_email_hash! hashes, and it is the same
        # address the buyer used in the other region - that shared address is
        # the whole basis for the match.
        org.billing_email = federated_email
        org.compute_email_hash!
        org.save
        org
      end

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            'plan_id' => 'identity_plus_v1',
            'email_hash' => federated_org.email_hash,
          },
        )
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(build_stripe_customer(
                        id: stripe_customer_id,
                        email: federated_email,
                        metadata: { 'email_hash' => federated_org.email_hash },
                      ))

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(nil)

        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .with(federated_org.email_hash)
          .and_return([federated_org])
      end

      it 'returns :federated_only' do
        expect(operation.call).to eq(:federated_only)
      end

      it 'applies the subscription status to the federated org' do
        operation.call
        federated_org.refresh!
        expect(federated_org.subscription_status).to eq('active')
      end

      it 'applies the plan from subscription metadata' do
        operation.call
        federated_org.refresh!
        expect(federated_org.planid).to eq('identity_plus_v1')
      end

      it 'marks the org as federated' do
        operation.call
        federated_org.refresh!
        expect(federated_org.subscription_federated?).to be true
        expect(federated_org.subscription_federated_at).not_to be_nil
      end

      it 'does not give the federated org Stripe ownership fields' do
        operation.call
        federated_org.refresh!
        expect(federated_org.stripe_customer_id.to_s).to be_empty
        expect(federated_org.stripe_subscription_id.to_s).to be_empty
      end
    end

    describe 'owner organization in the purchasing region' do
      let!(:owner_customer) { create_test_customer(email: owner_email) }
      let!(:owner_org) do
        org = create_test_organization(customer: owner_customer)
        org.stripe_customer_id = stripe_customer_id
        org.stripe_subscription_id = prior_subscription_id
        org.subscription_status = 'active'
        org.billing_email = owner_email
        org.compute_email_hash!
        org.save
        org
      end

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            'plan_id' => 'identity_plus_v1',
            'email_hash' => owner_org.email_hash,
          },
        )
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(build_stripe_customer(
                        id: stripe_customer_id,
                        email: owner_email,
                        metadata: { 'email_hash' => owner_org.email_hash },
                      ))

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)

        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
      end

      it 'returns :owner_only' do
        expect(operation.call).to eq(:owner_only)
      end

      # checkout.session.completed compares the STORED subscription id against
      # the incoming one to detect a replacement that would orphan a live,
      # still-charging subscription (#2605). Overwriting it here would make that
      # check compare the new id against itself and silently pass.
      it 'leaves the stored subscription id for checkout.session.completed to replace' do
        operation.call
        owner_org.refresh!
        expect(owner_org.stripe_subscription_id).to eq(prior_subscription_id)
      end

      it 'does not mark the owner as federated' do
        operation.call
        owner_org.refresh!
        expect(owner_org.subscription_federated_at).to be_nil
      end
    end

    describe 'no organization in this region yet' do
      let(:unmatched_hash) { 'nonexistent_hash_00000000' }

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: { 'email_hash' => unmatched_hash },
        )
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(build_stripe_customer(
                        id: stripe_customer_id,
                        email: 'nobody@example.com',
                        metadata: { 'email_hash' => unmatched_hash },
                      ))

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(nil)

        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
      end

      after do
        Billing::PendingFederatedSubscription.find_by_email_hash(unmatched_hash)&.destroy! rescue nil
      end

      it 'returns :pending_stored' do
        expect(operation.call).to eq(:pending_stored)
      end

      it 'stores the subscription for a future account in this region' do
        operation.call
        pending = Billing::PendingFederatedSubscription.find_by_email_hash(unmatched_hash)
        expect(pending).not_to be_nil
      end
    end
  end

  context 'with federation disabled' do
    around do |example|
      original_secret = ENV['FEDERATION_SECRET']
      ENV.delete('FEDERATION_SECRET')
      example.run
    ensure
      ENV['FEDERATION_SECRET'] = original_secret if original_secret
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'plan_id' => 'identity_plus_v1' },
      )
    end

    it 'returns :skipped' do
      expect(operation.call).to eq(:skipped)
    end

    it 'does not look up organizations' do
      expect(Onetime::Organization).not_to receive(:find_by_stripe_subscription_id)
      expect(Onetime::Organization).not_to receive(:find_by_stripe_customer_id)
      operation.call
    end

    it 'does not call Stripe' do
      expect(Stripe::Customer).not_to receive(:retrieve)
      operation.call
    end

    # Every new subscription in a single-region deployment would otherwise
    # report a non-match seconds before checkout.session.completed linked it,
    # drowning the real misses the warning exists to surface.
    it 'does not emit a federation.no_match warning' do
      logger = instance_double(SemanticLogger::Logger)
      allow(Onetime).to receive(:get_logger).and_call_original
      allow(Onetime).to receive(:get_logger).with('Billing').and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:debug)

      expect(logger).not_to receive(:warn)
        .with(Billing::Operations::WebhookHandlers::FederationSupport::NO_MATCH_EVENT, anything)

      operation.call
    end
  end
end
