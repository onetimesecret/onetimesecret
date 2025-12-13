# apps/web/billing/spec/operations/process_webhook_event/catalog_updates_spec.rb
#
# frozen_string_literal: true

# Tests for product/price/plan update webhook events.
# These events trigger plan cache refresh.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/catalog_updates_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: catalog updates', :integration, :process_webhook_event do
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:product) { build_stripe_product(id: 'prod_test_123', name: 'Test Plan') }
  let(:price) { build_stripe_price(id: 'price_test_123', product: 'prod_test_123') }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  shared_examples 'refreshes plan cache' do |event_type|
    let(:data_object) { event_type.include?('price') ? price : product }
    let(:event) { build_stripe_event(type: event_type, data_object: data_object) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before { allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(true) }

    include_examples 'handles event successfully'

    it 'calls Plan.refresh_from_stripe' do
      operation.call
      expect(Billing::Plan).to have_received(:refresh_from_stripe)
    end
  end

  context 'product.created' do
    include_examples 'refreshes plan cache', 'product.created'
  end

  context 'product.updated' do
    include_examples 'refreshes plan cache', 'product.updated'
  end

  context 'price.created' do
    include_examples 'refreshes plan cache', 'price.created'
  end

  context 'price.updated' do
    include_examples 'refreshes plan cache', 'price.updated'
  end

  context 'plan.created' do
    include_examples 'refreshes plan cache', 'plan.created'
  end

  context 'plan.updated' do
    include_examples 'refreshes plan cache', 'plan.updated'
  end

  context 'when cache refresh fails' do
    let(:event) { build_stripe_event(type: 'product.updated', data_object: product) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Billing::Plan).to receive(:refresh_from_stripe)
        .and_raise(StandardError, 'Cache refresh failed')
    end

    it 'returns :success (cache errors are non-fatal)' do
      expect(operation.call).to eq(:success)
    end

    it 'does not propagate the error' do
      expect { operation.call }.not_to raise_error
    end
  end
end
