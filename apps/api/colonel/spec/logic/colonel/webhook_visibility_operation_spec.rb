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
    def exists? = true
  end

  Pending = Struct.new(
    :email_hash, :subscription_status, :planid, :region, :received_at,
    :source_stripe_event_id,
    keyword_init: true,
  ) do
    def exists? = true
  end

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

  # Stubs for the class-level sorted-set indexes. Familia exposes them as
  # `Model.recent_events` / `Model.recent_records`; we replace them here with
  # a hand-rolled instance-double stand-in that supports the four methods the
  # operation calls: element_count, revrange, remove.
  let(:event_index)   { double('recent_events') }
  let(:pending_index) { double('recent_records') }

  let(:event_model) do
    class_double(
      Billing::StripeWebhookEvent,
      recent_events: event_index,
    ).tap do |dbl|
      stub_const('Billing::StripeWebhookEvent::INDEX_MAX_ENTRIES', 10_000)
    end
  end
  let(:pending_model) do
    class_double(
      Billing::PendingFederatedSubscription,
      recent_records: pending_index,
    ).tap do |dbl|
      stub_const('Billing::PendingFederatedSubscription::INDEX_MAX_ENTRIES', 10_000)
    end
  end

  subject(:visibility) do
    described_class.new(
      webhook_event_model: event_model,
      pending_subscription_model: pending_model,
    )
  end

  before do
    allow(event_model).to receive(:load_multi) { |ids| [event_a, event_b].select { |event| ids.include?(event.stripe_event_id) } }
    allow(pending_model).to receive(:load_multi).and_return([])
    allow(event_index).to receive(:remove)
    allow(pending_index).to receive(:remove)
  end

  it 'reads the index newest-first (via revrange) and emits an allowlisted event row' do
    # Index has 2 entries. Page 1 / per_page 1 returns just the newest.
    allow(event_index).to receive(:element_count).and_return(2)
    allow(event_index).to receive(:revrange).with(0, 0).and_return(['evt_b'])

    page = visibility.list_webhook_events(page: 1, per_page: 1)

    expect(page.rows).to eq([
      {
        event_id: 'evt_b', event_type: 'customer.subscription.updated',
        processing_status: 'retrying', processing_outcome: 'retryable', received_at: 200,
        processed_at: nil, attempt_count: 2, retryable: true,
      },
    ])
    expect(page).to have_attributes(
      total_count: 2, total_pages: 2, capped: false, stale_count: 0,
    )
  end

  it 'marks capped only when the index reaches INDEX_MAX_ENTRIES' do
    stub_const('Billing::StripeWebhookEvent::INDEX_MAX_ENTRIES', 1)
    allow(event_index).to receive(:element_count).and_return(1)
    allow(event_index).to receive(:revrange).with(0, 49).and_return(['evt_a'])

    page = visibility.list_webhook_events

    expect(page).to have_attributes(total_count: 1, capped: true)
  end

  it 'lazy-prunes stale ids (index entry whose object no longer loads) and counts them' do
    allow(event_index).to receive(:element_count).and_return(3)
    allow(event_index).to receive(:revrange).with(0, 49).and_return(['evt_gone', 'evt_a', 'evt_b'])

    page = visibility.list_webhook_events

    expect(event_index).to have_received(:remove).with('evt_gone').once
    expect(event_index).not_to have_received(:remove).with('evt_a')
    expect(page.rows.map { |row| row[:event_id] }).to eq(['evt_a', 'evt_b'])
    expect(page.stale_count).to eq(1)
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
    allow(pending_index).to receive(:element_count).and_return(2)
    allow(pending_index).to receive(:revrange).with(0, 49)
      .and_return(['email-hash-never-expose', 'another-hash-never-expose'])
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
    allow(pending_index).to receive(:element_count).and_return(1)
    allow(pending_index).to receive(:revrange).with(0, 49).and_return(['email-hash-never-expose'])
    allow(pending_model).to receive(:load_multi).and_return([correlated])
    allow(event_model).to receive(:load_multi).with(['evt_b']).and_return([event_b])

    page = visibility.list_pending_federated_subscriptions

    expect(page.rows.first[:source_webhook]).to eq(
      state: 'available', processing_status: 'retrying', outcome: 'retryable',
    )
    expect(page.rows.first.to_s).not_to include('email-hash-never-expose')
  end
end
