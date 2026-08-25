# apps/web/billing/spec/operations/process_webhook_event/federation/no_match_logging_spec.rb
#
# frozen_string_literal: true

# Tests for the structured federation.no_match warning (#4230).
#
# A subscription webhook that matches no organization in this region means
# someone's account is not in the state they paid for. Both non-match paths used
# to be effectively silent: the non-federation fallback logged a bare warning
# carrying only the subscription id, and the federated path logged nothing at
# all before storing a pending record. The first signal was a support ticket.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/federation/no_match_logging_spec.rb

require_relative '../../../support/billing_spec_helper'
require_relative '../shared_examples'
require_relative '../../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: federation.no_match logging', :integration, :process_webhook_event do
  let(:stripe_customer_id) { 'cus_no_match_123' }
  let(:stripe_subscription_id) { 'sub_no_match_456' }
  let(:unmatched_hash) { 'nomatch_hash_000000000000' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:no_match_event) { Billing::Operations::WebhookHandlers::FederationSupport::NO_MATCH_EVENT }

  # Capture the Billing logger so the warning payload can be asserted on.
  let(:logger) { instance_double(SemanticLogger::Logger) }

  before do
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('Billing').and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
  end

  after do
    created_organizations.each { |org| org.destroy! rescue nil }
    created_customers.each { |cust| cust.destroy! rescue nil }
  end

  describe 'federated path: no owner and no federated org' do
    around do |example|
      original_secret = ENV['FEDERATION_SECRET']
      ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
      example.run
    ensure
      ENV['FEDERATION_SECRET'] = original_secret
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'email_hash' => unmatched_hash },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.created', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Stripe::Customer).to receive(:retrieve)
        .with(stripe_customer_id)
        .and_return(Stripe::Customer.construct_from({
                                                      id: stripe_customer_id,
                                                      object: 'customer',
                                                      email: 'nobody@example.com',
                                                      metadata: { 'email_hash' => unmatched_hash },
                                                    }))

      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(nil)

      allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
        .and_return([])
    end

    after do
      Billing::PendingFederatedSubscription.find_by_email_hash(unmatched_hash)&.destroy! rescue nil
    end

    it 'logs federation.no_match with the correlation fields' do
      expect(logger).to receive(:warn).with(
        no_match_event,
        hash_including(
          email_hash: unmatched_hash,
          customer: stripe_customer_id,
          subscription: stripe_subscription_id,
          event_type: 'customer.subscription.created',
          reason: Billing::Operations::WebhookHandlers::FederationSupport::REASON_NO_ORG_MATCH,
          federation_enabled: true,
        )
      )

      operation.call
    end

    it 'records that a pending record was stored' do
      expect(logger).to receive(:warn).with(
        no_match_event,
        hash_including(pending_stored: true)
      )

      operation.call
    end

    it 'includes the region' do
      expect(logger).to receive(:warn).with(
        no_match_event,
        hash_including(region: Billing::Metadata.current_region)
      )

      operation.call
    end
  end

  describe 'federated path: no email hash to match on' do
    around do |example|
      original_secret = ENV['FEDERATION_SECRET']
      ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
      example.run
    ensure
      ENV['FEDERATION_SECRET'] = original_secret
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: {},
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.created', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      # No email_hash in metadata and no email to compute one from: nothing can
      # ever be matched or claimed later, which is what pending_stored: false
      # records.
      allow(Stripe::Customer).to receive(:retrieve)
        .with(stripe_customer_id)
        .and_return(Stripe::Customer.construct_from({
                                                      id: stripe_customer_id,
                                                      object: 'customer',
                                                      email: nil,
                                                      metadata: {},
                                                    }))

      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(nil)
    end

    it 'logs federation.no_match with pending_stored false' do
      expect(logger).to receive(:warn).with(
        no_match_event,
        hash_including(
          email_hash: nil,
          pending_stored: false,
          reason: Billing::Operations::WebhookHandlers::FederationSupport::REASON_NO_ORG_MATCH,
        )
      )

      operation.call
    end
  end

  describe 'non-federated path: subscription id matches no organization' do
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
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(nil)
    end

    it 'logs federation.no_match alongside the existing warning' do
      expect(logger).to receive(:warn).with(
        no_match_event,
        hash_including(
          customer: stripe_customer_id,
          subscription: stripe_subscription_id,
          event_type: 'customer.subscription.updated',
          reason: Billing::Operations::WebhookHandlers::FederationSupport::REASON_NO_SUBSCRIPTION_MATCH,
          federation_enabled: false,
        )
      )

      operation.call
    end

    it 'still returns :not_found' do
      expect(operation.call).to eq(:not_found)
    end
  end

  describe 'region label' do
    let(:test_class) do
      Class.new do
        include Billing::Operations::WebhookHandlers::FederationSupport
      end
    end

    let(:handler) { test_class.new }

    it 'reports the configured jurisdiction' do
      allow(OT).to receive(:conf).and_return({
        'features' => { 'regions' => { 'enabled' => true, 'current_jurisdiction' => 'CA' } },
      })

      expect(handler.send(:federation_region_label)).to eq('CA')
    end

    it 'falls back to "unknown" rather than raising when regions are misconfigured' do
      # regions enabled with no jurisdiction set makes current_region raise.
      # The no-match line must survive that: the misconfiguration is already
      # surfaced by every non-logging caller.
      allow(OT).to receive(:conf).and_return({
        'features' => { 'regions' => { 'enabled' => true, 'current_jurisdiction' => nil } },
      })

      expect(handler.send(:federation_region_label))
        .to eq(Billing::Operations::WebhookHandlers::FederationSupport::UNKNOWN_REGION)
    end
  end
end
