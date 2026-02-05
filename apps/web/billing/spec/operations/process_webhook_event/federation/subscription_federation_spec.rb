# apps/web/billing/spec/operations/process_webhook_event/federation/subscription_federation_spec.rb
#
# frozen_string_literal: true

# Tests for subscription federation via HMAC email hash (#2471).
#
# Federation allows a single Stripe subscription to grant benefits across
# multiple organizations via email hash matching. The hash is:
# - Computed at subscription creation from billing email
# - Stored immutably in Stripe customer metadata
# - Used for matching on webhook events (NOT the current email)
#
# Security model:
# - Owner lookup: by stripe_customer_id (direct ownership)
# - Federated lookup: by email_hash (cross-region matching)
# - Attack prevention: Email changes post-subscription don't affect hash
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/federation/

require_relative '../../../support/billing_spec_helper'
require_relative '../shared_examples'
require_relative '../../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: Subscription Federation', :integration, :process_webhook_event do
  let(:owner_email) { "owner-#{SecureRandom.hex(4)}@example.com" }
  let(:federated_email) { "federated-#{SecureRandom.hex(4)}@example.com" }
  let(:attacker_email) { "attacker-#{SecureRandom.hex(4)}@example.com" }
  let(:victim_email) { "victim-#{SecureRandom.hex(4)}@example.com" }

  let(:stripe_customer_id) { 'cus_federation_test_123' }
  let(:stripe_subscription_id) { 'sub_federation_test_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each { |org| org.destroy! rescue nil }
    created_customers.each { |cust| cust.destroy! rescue nil }
  end

  describe 'owner organization lookup' do
    context 'when owner org exists with matching stripe_customer_id' do
      let!(:owner_customer) { create_test_customer(email: owner_email) }
      let!(:owner_org) do
        org = create_test_organization(customer: owner_customer)
        org.stripe_customer_id = stripe_customer_id
        org.stripe_subscription_id = stripe_subscription_id
        org.subscription_status = 'active'
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
            'email_hash' => owner_org.email_hash,
            'customer_extid' => owner_customer.extid,
          },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)
      end

      it 'finds owner org by stripe_customer_id' do
        expect(operation.call).to eq(:success)
      end

      it 'updates owner org subscription status' do
        operation.call
        owner_org.refresh!
        expect(owner_org.subscription_status).to eq('active')
      end

      it 'does not mark owner as federated' do
        operation.call
        owner_org.refresh!
        expect(owner_org.subscription_federated?).to be false
      end
    end
  end

  describe 'federated organization lookup' do
    context 'when federated org exists with matching email_hash (no stripe_customer_id)' do
      let!(:federated_customer) { create_test_customer(email: federated_email) }
      let!(:federated_org) do
        org = create_test_organization(customer: federated_customer)
        # Federated org has NO stripe_customer_id - only email_hash
        org.stripe_customer_id = nil
        org.stripe_subscription_id = nil
        org.compute_email_hash!
        org.save
        org
      end

      # Different customer ID (owner is elsewhere), but matching email_hash
      let(:owner_stripe_customer_id) { 'cus_owner_different_region' }

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: owner_stripe_customer_id,
          status: 'active',
          metadata: {
            'email_hash' => federated_org.email_hash,
          },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        # No owner org found by stripe_customer_id
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(owner_stripe_customer_id)
          .and_return(nil)

        # Federated org found by email_hash (returns array)
        allow(Onetime::Organization).to receive(:find_all_by_email_hash)
          .with(federated_org.email_hash)
          .and_return([federated_org])
      end

      it 'finds federated org by email_hash when owner not found' do
        expect(operation.call).to eq(:success)
      end

      it 'updates federated org subscription status' do
        operation.call
        federated_org.refresh!
        expect(federated_org.subscription_status).to eq('active')
      end

      it 'marks federated org as federated' do
        operation.call
        federated_org.refresh!
        expect(federated_org.subscription_federated?).to be true
      end

      it 'sets subscription_federated_at timestamp' do
        operation.call
        federated_org.refresh!
        expect(federated_org.subscription_federated_at).not_to be_nil
      end
    end
  end

  describe 'owner AND federated orgs both updated' do
    context 'when both owner and federated orgs exist' do
      let!(:owner_customer) { create_test_customer(email: owner_email) }
      let!(:owner_org) do
        org = create_test_organization(customer: owner_customer, name: 'Owner Org')
        org.stripe_customer_id = stripe_customer_id
        org.stripe_subscription_id = stripe_subscription_id
        org.subscription_status = 'trialing'
        org.compute_email_hash!
        org.save
        org
      end

      let!(:federated_customer) { create_test_customer(email: federated_email) }
      let!(:federated_org) do
        org = create_test_organization(customer: federated_customer, name: 'Federated Org')
        org.stripe_customer_id = nil
        # Same email_hash as owner (simulating same user in different region)
        org.email_hash = owner_org.email_hash
        org.subscription_status = nil
        org.save
        org
      end

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            'email_hash' => owner_org.email_hash,
          },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)

        # Return both owner and federated org (filtering happens in handler)
        allow(Onetime::Organization).to receive(:find_all_by_email_hash)
          .with(owner_org.email_hash)
          .and_return([owner_org, federated_org])
      end

      it 'updates both owner and federated orgs' do
        operation.call

        owner_org.refresh!
        federated_org.refresh!

        expect(owner_org.subscription_status).to eq('active')
        expect(federated_org.subscription_status).to eq('active')
      end

      it 'marks only federated org as federated' do
        operation.call

        owner_org.refresh!
        federated_org.refresh!

        expect(owner_org.subscription_federated?).to be false
        expect(federated_org.subscription_federated?).to be true
      end
    end
  end

  describe 'no matching organization' do
    context 'when no org found by customer_id or email_hash' do
      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            'email_hash' => 'nonexistent_hash_00000000',
          },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(nil)

        # No orgs found by email_hash (returns empty array)
        allow(Onetime::Organization).to receive(:find_all_by_email_hash)
          .with('nonexistent_hash_00000000')
          .and_return([])
      end

      it 'returns :not_found (discards webhook, does not error)' do
        expect(operation.call).to eq(:not_found)
      end

      it 'does not raise an error' do
        expect { operation.call }.not_to raise_error
      end
    end
  end

  describe 'SECURITY: email-swap attack prevention' do
    # Attack scenario:
    # 1. Attacker subscribes with attacker@evil.com
    # 2. email_hash computed and stored in Stripe metadata
    # 3. Attacker changes Stripe email to victim@example.com
    # 4. Webhook fires with attacker's email_hash but victim's current email
    # 5. Federation lookup uses email_hash from metadata (attacker's), not current email
    # 6. Victim org (with victim's email_hash) is NOT found -> attack fails

    context 'when attacker changes Stripe email to victim email post-subscription' do
      let!(:attacker_customer) { create_test_customer(email: attacker_email) }
      let!(:attacker_org) do
        org = create_test_organization(customer: attacker_customer, name: 'Attacker Org')
        org.stripe_customer_id = stripe_customer_id
        org.compute_email_hash!
        org.save
        org
      end

      let!(:victim_customer) { create_test_customer(email: victim_email) }
      let!(:victim_org) do
        org = create_test_organization(customer: victim_customer, name: 'Victim Org')
        org.stripe_customer_id = nil  # Victim has no subscription
        org.compute_email_hash!
        org.save
        org
      end

      # Attacker's subscription with attacker's original email_hash
      # (even though Stripe email might now show victim's email)
      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {
            # CRITICAL: email_hash is from original subscription creation
            # It NEVER changes, even if attacker modifies Stripe email
            'email_hash' => attacker_org.email_hash,
          },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        # Attacker's org found by stripe_customer_id
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(attacker_org)

        # Lookup by attacker's email_hash returns only attacker org
        # (victim has different email_hash, so not in results)
        allow(Onetime::Organization).to receive(:find_all_by_email_hash)
          .with(attacker_org.email_hash)
          .and_return([attacker_org])
      end

      it 'updates attacker org (they own the subscription)' do
        operation.call
        attacker_org.refresh!
        expect(attacker_org.subscription_status).to eq('active')
      end

      it 'does NOT update victim org (different email_hash)' do
        original_status = victim_org.subscription_status
        operation.call
        victim_org.refresh!
        expect(victim_org.subscription_status).to eq(original_status)
      end

      it 'victim org remains unaffected by attacker email change' do
        operation.call
        victim_org.refresh!
        expect(victim_org.subscription_federated?).to be false
        expect(victim_org.subscription_federated_at).to be_nil
      end
    end
  end

  describe 'metadata without email_hash' do
    context 'when Stripe metadata has no email_hash (legacy customer)' do
      let!(:owner_customer) { create_test_customer(email: owner_email) }
      let!(:owner_org) do
        org = create_test_organization(customer: owner_customer)
        org.stripe_customer_id = stripe_customer_id
        org.save
        org
      end

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: stripe_customer_id,
          status: 'active',
          metadata: {}, # No email_hash
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)
      end

      it 'still updates owner org (found by stripe_customer_id)' do
        operation.call
        owner_org.refresh!
        expect(owner_org.subscription_status).to eq('active')
      end

      it 'skips federation lookup when no email_hash in metadata' do
        expect(Onetime::Organization).not_to receive(:find_all_by_email_hash)
        operation.call
      end
    end
  end
end
