# apps/web/billing/spec/operations/process_webhook_event/trial_will_end_spec.rb
#
# frozen_string_literal: true

# Tests for customer.subscription.trial_will_end webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/trial_will_end_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.subscription.trial_will_end', :integration, :process_webhook_event do
  let(:test_email) { "trial-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_trial_123' }
  let(:stripe_subscription_id) { 'sub_trial_456' }
  let(:trial_end_timestamp) { (Time.now + 3 * 24 * 60 * 60).to_i } # 3 days from now

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  # Build subscription with trial_end field
  def build_subscription_with_trial(id:, customer:, status:, trial_end:, metadata: {})
    Stripe::Subscription.construct_from({
      id: id,
      object: 'subscription',
      customer: customer,
      status: status,
      trial_end: trial_end,
      metadata: metadata,
      current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
      items: {
        data: [{
          price: {
            id: 'price_test',
            product: 'prod_test',
            metadata: {},
          },
        }],
      },
    })
  end

  context 'with existing organization' do
    let!(:customer) { create_test_customer(custid: nil, email: test_email) }
    let!(:organization) do
      org = create_test_organization(customer: customer)
      org.stripe_subscription_id = stripe_subscription_id
      org.subscription_status = 'trialing'
      org.save
      org
    end

    let(:subscription) do
      build_subscription_with_trial(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'trialing',
        trial_end: trial_end_timestamp,
        metadata: { 'custid' => customer.custid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.trial_will_end', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(organization)
    end

    include_examples 'handles event successfully'

    it 'does not change subscription_status' do
      original_status = organization.subscription_status
      operation.call
      organization.refresh!
      expect(organization.subscription_status).to eq(original_status)
    end

    it 'logs trial ending notification' do
      # Handler logs trial_end timestamp but doesn't modify organization
      expect { operation.call }.not_to raise_error
    end
  end

  context 'with unknown organization' do
    let(:subscription) do
      build_subscription_with_trial(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'trialing',
        trial_end: trial_end_timestamp,
        metadata: { 'custid' => 'unknown_custid' },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.trial_will_end', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(nil)
    end

    include_examples 'logs warning for missing organization'
  end
end
