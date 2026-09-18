# apps/api/colonel/spec/logic/colonel/webhook_visibility_operation_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'onetime/operations/billing/webhook_visibility'

RSpec.describe Onetime::Operations::Billing::WebhookVisibility do
  Event = Struct.new(
    :stripe_event_id, :event_type, :processing_status, :processing_outcome,
    :first_seen_at, :processed_at, :attempt_count, :api_version, :livemode,
    :created, :pending_webhooks, :last_attempt_at, :circuit_retry_at,
    :circuit_retry_count, :error_message, :data_object_id, :event_payload,
    keyword_init: true,
  ) do
    def retryable? = processing_status != 'success' && attempt_count.to_i < 3
    def max_attempts_reached? = attempt_count.to_i >= 3
  end

  Pending = Struct.new(
    :email_hash, :subscription_status, :planid, :region, :received_at,
    :source_stripe_event_id,
    keyword_init: true,
  )

  let(:event_a) do
    Event.new(
      stripe_event_id: 'evt_a', event_type: 'invoice.paid', processing_status: 'success',
      processing_outcome: nil, first_seen_at: '100', processed_at: '101', attempt_count: '1',
      api_version: '2025-01-27', livemode: 'true', created: '90', pending_webhooks: '0',
      last_attempt_at: '100', circuit_retry_count: '0', error_message: nil,
      data_object_id: 'cus_never_expose', event_payload: '{"customer":"never_expose"}',
    )
  end
  let(:event_b) do
    Event.new(
      stripe_event_id: 'evt_b', event_type: 'customer.subscription.updated', processing_status: 'retrying',
      processing_outcome: 'retryable', first_seen_at: '200', attempt_count: '2',
      error_message: 'customer cus_never_expose failed', data_object_id: 'cus_never_expose',
      event_payload: '{"customer":"never_expose"}', circuit_retry_at: '250', circuit_retry_count: '1',
    )
  end
  let(:event_model) { class_double(Billing::StripeWebhookEvent, prefix: 'stripe_webhook_event') }
  let(:pending_model) { class_double(Billing::PendingFederatedSubscription, prefix: 'pending_fed_sub') }
  let(:redis) { instance_double('Redis') }

  subject(:visibility) do
    described_class.new(
      dbclient: redis,
      webhook_event_model: event_model,
      pending_subscription_model: pending_model,
    )
  end

  before do
    allow(event_model).to receive(:load_multi) { |ids| [event_a, event_b].select { |event| ids.include?(event.stripe_event_id) } }
    allow(pending_model).to receive(:load_multi).and_return([])
  end

  it 'sorts an unordered Redis scan by received time and emits an allowlisted event row' do
    allow(redis).to receive(:scan).with(
      '0', match: 'stripe_webhook_event:*:object', count: described_class::SCAN_COUNT,
    ).and_return(['0', ['stripe_webhook_event:evt_a:object', 'stripe_webhook_event:evt_b:object']])

    page = visibility.list_webhook_events(page: 1, per_page: 1)

    expect(page.rows).to eq([
      {
        event_id: 'evt_b', event_type: 'customer.subscription.updated',
        processing_status: 'retrying', processing_outcome: 'retryable', received_at: 200,
        processed_at: nil, attempt_count: 2, retryable: true,
      },
    ])
    expect(page).to have_attributes(total_count: 2, total_pages: 2, capped: false)
  end

  it 'marks counts capped when the bounded scan stops before Redis reaches its terminal cursor' do
    stub_const('Onetime::Operations::Billing::WebhookVisibility::MAX_SCAN_ROWS', 1)
    allow(redis).to receive(:scan).with(
      '0', match: 'stripe_webhook_event:*:object', count: described_class::SCAN_COUNT,
    ).and_return(['17', ['stripe_webhook_event:evt_a:object']])

    page = visibility.list_webhook_events

    expect(page).to have_attributes(total_count: 1, capped: true)
    expect(redis).to have_received(:scan).once
  end

  it 'does not expose payload, customer/object identifiers, or raw error text in detail' do
    detail = visibility.webhook_event_detail(event_b)

    expect(detail).to include(error_present: true, retryable: true, circuit_retry_at: 250)
    expect(detail.to_s).not_to include('never_expose')
    expect(detail).not_to have_key(:event_payload)
    expect(detail).not_to have_key(:data_object_id)
    expect(detail).not_to have_key(:error_message)
  end

  it 'represents legacy and expired source correlations as unavailable without returning email hashes' do
    legacy = Pending.new(
      email_hash: 'email-hash-never-expose', subscription_status: 'active', planid: 'pro_v1',
      region: 'eu', received_at: '300', source_stripe_event_id: nil,
    )
    expired_source = Pending.new(
      email_hash: 'another-hash-never-expose', subscription_status: 'past_due', planid: 'pro_v1',
      region: 'us', received_at: '200', source_stripe_event_id: 'evt_expired',
    )
    allow(redis).to receive(:scan).with(
      '0', match: 'pending_fed_sub:*:object', count: described_class::SCAN_COUNT,
    ).and_return(['0', ['pending_fed_sub:email-hash-never-expose:object', 'pending_fed_sub:another-hash-never-expose:object']])
    allow(pending_model).to receive(:load_multi).and_return([legacy, expired_source])
    allow(event_model).to receive(:load_multi).with(['evt_expired']).and_return([])

    page = visibility.list_pending_federated_subscriptions(page: 1, per_page: 50)

    expect(page.rows).to eq([
      {
        subscription_status: 'active', planid: 'pro_v1', region: 'eu', received_at: 300,
        source_webhook: { state: 'no_correlation', processing_status: nil, outcome: nil },
      },
      {
        subscription_status: 'past_due', planid: 'pro_v1', region: 'us', received_at: 200,
        source_webhook: { state: 'expired', processing_status: nil, outcome: nil },
      },
    ])
    expect(page.rows.to_s).not_to include('hash-never-expose')
  end

  it 'returns a correlated source event only through its safe processing projection' do
    correlated = Pending.new(
      email_hash: 'email-hash-never-expose', subscription_status: 'active', planid: 'pro_v1',
      region: 'eu', received_at: '300', source_stripe_event_id: 'evt_b',
    )
    allow(redis).to receive(:scan).with(
      '0', match: 'pending_fed_sub:*:object', count: described_class::SCAN_COUNT,
    ).and_return(['0', ['pending_fed_sub:email-hash-never-expose:object']])
    allow(pending_model).to receive(:load_multi).and_return([correlated])
    allow(event_model).to receive(:load_multi).with(['evt_b']).and_return([event_b])

    page = visibility.list_pending_federated_subscriptions

    expect(page.rows.first[:source_webhook]).to eq(
      state: 'available', processing_status: 'retrying', outcome: 'retryable',
    )
    expect(page.rows.first.to_s).not_to include('email-hash-never-expose')
  end
end
