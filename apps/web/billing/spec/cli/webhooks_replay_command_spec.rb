# apps/web/billing/spec/cli/webhooks_replay_command_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/webhooks_replay_command'
require_relative '../../models/stripe_webhook_event'

RSpec.describe Onetime::CLI::BillingWebhooksReplayCommand, type: :billing do
  let(:command) { described_class.new }

  # Sample event data
  let(:event_id_1) { "evt_test_#{SecureRandom.hex(8)}" }
  let(:event_id_2) { "evt_test_#{SecureRandom.hex(8)}" }
  let(:event_id_3) { "evt_test_#{SecureRandom.hex(8)}" }

  let(:sample_payload) do
    {
      id: event_id_1,
      type: 'customer.subscription.updated',
      object: 'event',
      data: {
        object: {
          id: 'sub_test123',
          object: 'subscription',
          customer: 'cus_test123',
          metadata: { customer_extid: 'cust_ot_123' }
        }
      }
    }.to_json
  end

  def create_test_event(event_id:, event_type:, status:, first_seen_at: nil, customer_id: nil)
    event = Billing::StripeWebhookEvent.new(stripe_event_id: event_id)
    event.event_type = event_type
    event.processing_status = status
    event.first_seen_at = (first_seen_at || Time.now).to_i.to_s
    event.last_attempt_at = Time.now.to_i.to_s
    event.attempt_count = '0'
    event.api_version = '2023-10-16'
    event.livemode = 'false'
    event.data_object_id = customer_id || 'sub_test123'
    event.event_payload = sample_payload
    event.save
    event
  end

  describe '#parse_since_option' do
    it 'parses hours correctly' do
      cutoff = command.send(:parse_since_option, '2h')
      expect(cutoff).to be_within(5).of((Time.now - 7200).to_i)
    end

    it 'parses days correctly' do
      cutoff = command.send(:parse_since_option, '3d')
      expect(cutoff).to be_within(5).of((Time.now - 259_200).to_i)
    end

    it 'parses minutes correctly' do
      cutoff = command.send(:parse_since_option, '30m')
      expect(cutoff).to be_within(5).of((Time.now - 1800).to_i)
    end

    it 'parses ISO8601 timestamps' do
      timestamp = '2024-01-15T10:00:00Z'
      cutoff = command.send(:parse_since_option, timestamp)
      expect(cutoff).to eq(Time.parse(timestamp).to_i)
    end

    it 'defaults to 24h when nil' do
      cutoff = command.send(:parse_since_option, nil)
      expect(cutoff).to be_within(5).of((Time.now - 86_400).to_i)
    end
  end

  describe '#resolve_customer_filter' do
    it 'returns nil for nil input' do
      result = command.send(:resolve_customer_filter, nil)
      expect(result).to be_nil
    end

    it 'returns Stripe customer ID directly if starts with cus_' do
      result = command.send(:resolve_customer_filter, 'cus_test123')
      expect(result).to eq('cus_test123')
    end
  end

  describe '#matches_filters?' do
    let(:event) do
      e = Billing::StripeWebhookEvent.new(stripe_event_id: event_id_1)
      e.event_type = 'customer.subscription.updated'
      e.processing_status = 'failed'
      e.first_seen_at = Time.now.to_i.to_s
      e
    end

    it 'matches when all filters pass' do
      result = command.send(:matches_filters?, event,
        type: 'customer.subscription.updated',
        cutoff: (Time.now - 3600).to_i,
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: 'failed',
        force: false
      )
      expect(result).to be true
    end

    it 'rejects when type does not match' do
      result = command.send(:matches_filters?, event,
        type: 'checkout.session.completed',
        cutoff: (Time.now - 3600).to_i,
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: 'failed',
        force: false
      )
      expect(result).to be false
    end

    it 'rejects when status does not match' do
      result = command.send(:matches_filters?, event,
        type: nil,
        cutoff: (Time.now - 3600).to_i,
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: 'pending',
        force: false
      )
      expect(result).to be false
    end

    it 'rejects events older than cutoff' do
      event.first_seen_at = (Time.now - 7200).to_i.to_s # 2 hours ago

      result = command.send(:matches_filters?, event,
        type: nil,
        cutoff: (Time.now - 3600).to_i, # 1 hour cutoff
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: 'failed',
        force: false
      )
      expect(result).to be false
    end

    it 'skips successful events unless force is true' do
      event.processing_status = 'success'

      result = command.send(:matches_filters?, event,
        type: nil,
        cutoff: nil,
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: nil,
        force: false
      )
      expect(result).to be false

      result_with_force = command.send(:matches_filters?, event,
        type: nil,
        cutoff: nil,
        stripe_customer_id: nil,
        original_customer_id: nil,
        status: nil,
        force: true
      )
      expect(result_with_force).to be true
    end
  end

  describe '#matches_customer?' do
    let(:event) do
      e = Billing::StripeWebhookEvent.new(stripe_event_id: event_id_1)
      e.data_object_id = 'cus_test123'
      e.event_payload = {
        data: {
          object: {
            customer: 'cus_test123',
            metadata: { customer_extid: 'cust_ot_456' }
          }
        }
      }.to_json
      e
    end

    it 'matches on data_object_id with stripe_customer_id' do
      result = command.send(:matches_customer?, event, 'cus_test123')
      expect(result).to be true
    end

    it 'matches on customer field in payload' do
      event.data_object_id = 'sub_xxx' # Different from customer
      result = command.send(:matches_customer?, event, 'cus_test123')
      expect(result).to be true
    end

    it 'matches on customer_extid in metadata using original_customer_id' do
      event.data_object_id = 'sub_xxx'
      # When user provides extid like 'cust_ot_456', it should match metadata
      result = command.send(:matches_customer?, event, nil, original_customer_id: 'cust_ot_456')
      expect(result).to be true
    end

    it 'does not match customer_extid when only stripe_customer_id is provided' do
      event.data_object_id = 'sub_xxx'
      # When stripe_customer_id doesn't match any Stripe fields and no original_customer_id
      result = command.send(:matches_customer?, event, 'cus_other')
      expect(result).to be false
    end

    it 'returns false for non-matching customer' do
      result = command.send(:matches_customer?, event, 'cus_other', original_customer_id: 'wrong_id')
      expect(result).to be false
    end
  end

  describe '#format_age' do
    it 'returns "just now" for recent events' do
      timestamp = Time.now.to_i.to_s
      expect(command.send(:format_age, timestamp)).to eq('just now')
    end

    it 'formats minutes correctly' do
      timestamp = (Time.now - 300).to_i.to_s # 5 minutes ago
      expect(command.send(:format_age, timestamp)).to eq('5m ago')
    end

    it 'formats hours correctly' do
      timestamp = (Time.now - 7200).to_i.to_s # 2 hours ago
      expect(command.send(:format_age, timestamp)).to eq('2h ago')
    end

    it 'formats days correctly' do
      timestamp = (Time.now - 172_800).to_i.to_s # 2 days ago
      expect(command.send(:format_age, timestamp)).to eq('2d ago')
    end

    it 'returns N/A for nil timestamp' do
      expect(command.send(:format_age, nil)).to eq('N/A')
    end
  end

  describe '#collect_replay_candidates' do
    before do
      # Create test events with different statuses and times
      create_test_event(
        event_id: event_id_1,
        event_type: 'customer.subscription.updated',
        status: 'failed',
        first_seen_at: Time.now - 3600 # 1 hour ago
      )

      create_test_event(
        event_id: event_id_2,
        event_type: 'checkout.session.completed',
        status: 'failed',
        first_seen_at: Time.now - 7200 # 2 hours ago
      )

      create_test_event(
        event_id: event_id_3,
        event_type: 'customer.subscription.updated',
        status: 'success',
        first_seen_at: Time.now - 1800 # 30 minutes ago
      )
    end

    it 'returns single event when event_id is specified' do
      events = command.send(:collect_replay_candidates,
        event_id: event_id_1,
        type: nil,
        since: '24h',
        customer: nil,
        status: 'failed',
        limit: 10,
        force: false
      )

      expect(events.size).to eq(1)
      expect(events.first.stripe_event_id).to eq(event_id_1)
    end

    it 'filters by event type' do
      events = command.send(:collect_replay_candidates,
        event_id: nil,
        type: 'customer.subscription.updated',
        since: '24h',
        customer: nil,
        status: 'failed',
        limit: 10,
        force: false
      )

      expect(events.size).to eq(1)
      expect(events.first.stripe_event_id).to eq(event_id_1)
    end

    it 'filters by status' do
      events = command.send(:collect_replay_candidates,
        event_id: nil,
        type: nil,
        since: '24h',
        customer: nil,
        status: 'failed',
        limit: 10,
        force: false
      )

      expect(events.size).to eq(2)
      expect(events.map(&:stripe_event_id)).to include(event_id_1, event_id_2)
    end

    it 'respects limit' do
      events = command.send(:collect_replay_candidates,
        event_id: nil,
        type: nil,
        since: '24h',
        customer: nil,
        status: 'failed',
        limit: 1,
        force: false
      )

      expect(events.size).to eq(1)
    end

    it 'includes successful events when force is true' do
      events = command.send(:collect_replay_candidates,
        event_id: nil,
        type: 'customer.subscription.updated',
        since: '24h',
        customer: nil,
        status: nil,
        limit: 10,
        force: true
      )

      # Should include both failed and successful events of this type
      expect(events.size).to eq(2)
    end

    it 'returns events sorted chronologically (oldest first)' do
      events = command.send(:collect_replay_candidates,
        event_id: nil,
        type: nil,
        since: '24h',
        customer: nil,
        status: 'failed',
        limit: 10,
        force: false
      )

      # Events should be sorted by created timestamp (oldest first for dependency chains)
      expect(events.size).to eq(2)
      # The created field defaults based on first_seen_at, so check order
      first_created = events.first.created.to_i
      second_created = events.last.created.to_i
      expect(first_created).to be <= second_created
    end
  end

  describe 'dry run mode' do
    before do
      create_test_event(
        event_id: event_id_1,
        event_type: 'customer.subscription.updated',
        status: 'failed'
      )
    end

    it 'does not execute replay when dry_run is true' do
      # Skip if billing isn't enabled (config check in stripe_configured?)
      skip 'Billing not enabled in test config' unless OT.billing_config&.enabled?

      # Capture output
      output = capture_stdout do
        command.call(
          event_id: event_id_1,
          dry_run: true,
          yes: true
        )
      end

      expect(output).to include('DRY RUN')
      expect(output).to include('Replay Preview')

      # Verify event was not modified
      event = Billing::StripeWebhookEvent.find_by_identifier(event_id_1)
      expect(event.processing_status).to eq('failed')
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
