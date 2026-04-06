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

  # Enable federation for all tests in this file
  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  # Stub Stripe::Customer.update globally to prevent real API calls from
  # record_federation_note. The unit tests for record_federation_note verify
  # the actual behavior; here we just prevent network calls.
  before do
    allow(Stripe::Customer).to receive(:update).and_return(
      Stripe::Customer.construct_from({ id: 'cus_stubbed', object: 'customer', metadata: {} })
    )
  end

  # Build a mock Stripe::Customer for testing
  def build_stripe_customer(id:, email:, metadata: {})
    Stripe::Customer.construct_from({
      id: id,
      object: 'customer',
      email: email,
      metadata: metadata,
    })
  end

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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        stripe_customer = build_stripe_customer(
          id: stripe_customer_id,
          email: owner_email,
          metadata: { 'email_hash' => owner_org.email_hash },
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)

        # Owner-only scenario: no federated orgs
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
      end

      it 'finds owner org by stripe_customer_id' do
        # Returns :owner_only when only owner is found (no federated orgs)
        expect(operation.call).to eq(:owner_only)
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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        stripe_customer = build_stripe_customer(
          id: owner_stripe_customer_id,
          email: federated_email,
          metadata: { 'email_hash' => federated_org.email_hash },
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(owner_stripe_customer_id)
          .and_return(stripe_customer)

        # No owner org found by stripe_customer_id
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(owner_stripe_customer_id)
          .and_return(nil)

        # Federated org found by email_hash (returns array of non-owner orgs)
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([federated_org])
      end

      it 'finds federated org by email_hash when owner not found' do
        # Returns :federated_only when no owner but federated orgs found
        expect(operation.call).to eq(:federated_only)
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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        stripe_customer = build_stripe_customer(
          id: stripe_customer_id,
          email: owner_email,
          metadata: { 'email_hash' => owner_org.email_hash },
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)

        # Return only federated org (find_federated_by_email_hash excludes owners)
        # The owner is found separately via stripe_customer_id
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([federated_org])
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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        stripe_customer = build_stripe_customer(
          id: stripe_customer_id,
          email: 'unknown@example.com',
          metadata: { 'email_hash' => 'nonexistent_hash_00000000' },
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(nil)

        # No orgs found by email_hash (returns empty array)
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
      end

      it 'returns :pending_stored (stores subscription for future matching)' do
        # When no org is found, federation stores subscription data for future matching
        # when a user creates an account with a matching email_hash
        expect(operation.call).to eq(:pending_stored)
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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        # The email_hash in metadata is from original subscription (attacker's)
        stripe_customer = build_stripe_customer(
          id: stripe_customer_id,
          email: victim_email,  # Attacker changed email to victim's
          metadata: { 'email_hash' => attacker_org.email_hash },  # But hash is still attacker's
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)

        # Attacker's org found by stripe_customer_id
        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(attacker_org)

        # Lookup by attacker's email_hash returns empty (attacker is already found as owner)
        # Victim org has different email_hash, so wouldn't match anyway
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
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
        # Stub Stripe::Customer.retrieve (called by process_with_federation)
        # Legacy customer with no email_hash in metadata
        stripe_customer = build_stripe_customer(
          id: stripe_customer_id,
          email: owner_email,
          metadata: {},  # No email_hash - code will compute from email
        )
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)

        allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
          .with(stripe_customer_id)
          .and_return(owner_org)

        # Code will compute hash from email and still do federation lookup
        # Allow the call but return empty array (no federated orgs)
        allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
          .and_return([])
      end

      it 'still updates owner org (found by stripe_customer_id)' do
        operation.call
        owner_org.refresh!
        expect(owner_org.subscription_status).to eq('active')
      end

      it 'uses computed hash from email when no metadata hash exists' do
        # For legacy customers without email_hash in Stripe metadata,
        # the code computes a hash from the email and does a federation lookup
        expect(Onetime::Organization).to receive(:find_federated_by_email_hash).once
        operation.call
      end
    end
  end

  describe 'record_federation_note' do
    # Test the SubscriptionFederation#record_federation_note method directly
    # by creating a test class that includes the module

    let(:test_class) do
      Class.new do
        include Billing::Operations::WebhookHandlers::SubscriptionFederation
      end
    end

    let(:handler) { test_class.new }

    let!(:federated_customer) { create_test_customer(email: federated_email) }
    let!(:federated_org) do
      org = create_test_organization(customer: federated_customer)
      org.stripe_customer_id = nil
      org.planid = 'identity_plus_v1'
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

    describe 'successful note recording' do
      before do
        # Mock OT.conf for region lookup
        allow(OT).to receive(:conf).and_return({
          'site' => { 'region' => 'EU' },
        })
      end

      it 'calls Stripe::Customer.update with correct metadata structure' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          metadata: hash_including(
            'last_federation_region' => 'EU',
            'last_federation_org' => federated_org.extid,
            'last_federation_plan' => 'identity_plus_v1',
            'last_federation_type' => 'initial',
            'last_federation_at' => satisfy { |v| v.is_a?(String) && v.match?(/\d{4}-\d{2}-\d{2}T/) }
          )
        )

        handler.send(:record_federation_note, subscription, federated_org, true)
      end

      it 'sets federation_type to initial for first federation' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          metadata: hash_including('last_federation_type' => 'initial')
        )

        handler.send(:record_federation_note, subscription, federated_org, true)
      end

      it 'sets federation_type to update for subsequent federations' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          metadata: hash_including('last_federation_type' => 'update')
        )

        handler.send(:record_federation_note, subscription, federated_org, false)
      end

      it 'passes only federation keys (Stripe merges with existing metadata server-side)' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          metadata: satisfy { |m|
            # Only federation keys are sent — Stripe preserves existing metadata
            m.keys.all? { |k| k.start_with?('last_federation_') } &&
            m['last_federation_region'] == 'EU'
          }
        )

        handler.send(:record_federation_note, subscription, federated_org, true)
      end
    end

    describe 'Stripe API error handling' do
      before do
        allow(OT).to receive(:conf).and_return({ 'site' => { 'region' => 'EU' } })

        # Simulate Stripe API error on update
        allow(Stripe::Customer).to receive(:update)
          .and_raise(Stripe::APIError.new('Rate limit exceeded'))
      end

      it 'does not raise when Stripe update fails' do
        expect {
          handler.send(:record_federation_note, subscription, federated_org, true)
        }.not_to raise_error
      end

      it 'logs warning when note recording fails' do
        logger = instance_double(SemanticLogger::Logger)
        # Allow other logger categories (cleanup calls OT.ld which uses 'App' category)
        allow(Onetime).to receive(:get_logger).and_call_original
        allow(Onetime).to receive(:get_logger).with('Billing').and_return(logger)
        allow(logger).to receive(:info)

        expect(logger).to receive(:warn).with(
          '[SubscriptionFederation] Failed to record federation note',
          hash_including(
            stripe_customer_id: stripe_customer_id,
            error: 'Rate limit exceeded'
          )
        )

        handler.send(:record_federation_note, subscription, federated_org, true)
      end
    end

    describe 'empty customer ID handling' do
      let(:subscription_no_customer) do
        Stripe::Subscription.construct_from({
          id: stripe_subscription_id,
          object: 'subscription',
          customer: '',
          status: 'active',
          metadata: {},
          items: { data: [] },
        })
      end

      it 'returns early without calling Stripe API when customer is empty' do
        expect(Stripe::Customer).not_to receive(:retrieve)
        expect(Stripe::Customer).not_to receive(:update)

        handler.send(:record_federation_note, subscription_no_customer, federated_org, true)
      end
    end

    describe 'unresolved plan_id handling' do
      # Use a separate customer to avoid "Organization exists" conflict
      let(:noplan_email) { "noplan-#{SecureRandom.hex(4)}@example.com" }
      let!(:noplan_customer) { create_test_customer(email: noplan_email) }
      let!(:org_no_plan) do
        org = create_test_organization(customer: noplan_customer)
        org.stripe_customer_id = nil
        org.planid = nil
        org.save
        org
      end

      before do
        allow(OT).to receive(:conf).and_return({ 'site' => { 'region' => 'EU' } })
      end

      it 'uses "unresolved" when org has no planid' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          metadata: hash_including('last_federation_plan' => 'unresolved')
        )

        handler.send(:record_federation_note, subscription, org_no_plan, true)
      end
    end
  end
end
