# apps/api/colonel/spec/logic/colonel/webhook_visibility_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

RSpec.describe 'Colonel webhook visibility adapters' do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end
  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_customer', extid: 'ur_customer', role: 'customer',
      verified?: true, anonymous?: false)
  end
  let(:strategy_result) do
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: {})
  end
  let(:page) do
    Onetime::Operations::Billing::WebhookVisibility::Page.new(
      rows: [{ event_id: 'evt_1' }], page: 1, per_page: 50,
      total_count: 1, total_pages: 1, capped: true, stale_count: 0,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
  end

  describe ColonelAPI::Logic::Colonel::ListStripeWebhookEvents do
    it 'enforces the colonel role and returns the bounded pagination envelope' do
      visibility = instance_double(Onetime::Operations::Billing::WebhookVisibility)
      allow(Onetime::Operations::Billing::WebhookVisibility).to receive(:new).and_return(visibility)
      allow(visibility).to receive(:list_webhook_events).and_return(page)

      logic = described_class.new(strategy_result, {})
      logic.raise_concerns
      data = logic.process

      expect(visibility).to have_received(:list_webhook_events).with(page: 1, per_page: 50)
      expect(data).to eq(
        record: {},
        details: {
          events: [{ event_id: 'evt_1' }],
          pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1, capped: true },
        },
      )
    end

    it 'refuses a non-colonel before reading Redis' do
      logic = described_class.new(strategy_result.tap { |result| allow(result).to receive(:user).and_return(customer) }, {})

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe ColonelAPI::Logic::Colonel::ListPendingFederatedSubscriptions do
    it 'uses the same bounded pagination envelope without exposing the backing key' do
      visibility = instance_double(Onetime::Operations::Billing::WebhookVisibility)
      allow(Onetime::Operations::Billing::WebhookVisibility).to receive(:new).and_return(visibility)
      allow(visibility).to receive(:list_pending_federated_subscriptions).and_return(page)

      logic = described_class.new(strategy_result, { 'page' => '0', 'per_page' => '1000' })
      logic.raise_concerns
      data = logic.process

      expect(visibility).to have_received(:list_pending_federated_subscriptions).with(page: 0, per_page: 1000)
      expect(data[:details][:pagination]).to include(capped: true)
      expect(data.to_s).not_to include('email_hash')
    end
  end

  describe ColonelAPI::Logic::Colonel::GetStripeWebhookEvent do
    let(:event) { instance_double(Billing::StripeWebhookEvent) }
    let(:row) do
      {
        event_id: 'evt_1', event_type: 'customer.subscription.updated',
        processing_status: 'failed', processing_outcome: 'retryable',
        received_at: 1_700_000_000, processed_at: nil, attempt_count: 2,
        retryable: true,
      }
    end
    let(:detail) do
      {
        api_version: '2025-01-27', livemode: false, stripe_created_at: 1_700_000_000,
        pending_webhooks: 0, last_attempt_at: 1_700_000_001, retryable: true,
        max_attempts_reached: false, circuit_retry_at: nil, circuit_retry_count: 0,
        error_present: true,
      }
    end

    before do
      @visibility = instance_double(Onetime::Operations::Billing::WebhookVisibility)
      allow(Onetime::Operations::Billing::WebhookVisibility).to receive(:new).and_return(@visibility)
      allow(@visibility).to receive(:find_webhook_event).with('evt_1').and_return(event)
      allow(@visibility).to receive(:webhook_event_row).with(event).and_return(row)
      allow(@visibility).to receive(:webhook_event_detail).with(event).and_return(detail)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    end

    it 'returns only safe projections and emits exactly one safe access observation' do
      logic = described_class.new(strategy_result, { 'event_id' => 'evt_1' })
      logic.raise_concerns
      data = logic.process

      expect(data).to eq(record: row, details: detail)
      expect(data.to_s).not_to include('event_payload')
      expect(data.to_s).not_to include('error_message')
      expect(data.to_s).not_to include('data_object_id')
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: 'ur_colonel', verb: 'billing.webhook.inspect', target: 'evt_1', result: :success,
        detail: {
          event_type: 'customer.subscription.updated', processing_status: 'failed',
          processing_outcome: 'retryable',
        },
      )
    end

    it '404s missing or expired ids without an access observation' do
      allow(@visibility).to receive(:find_webhook_event).with('evt_missing').and_return(nil)
      logic = described_class.new(strategy_result, { 'event_id' => 'evt_missing' })

      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
    end
  end
end
