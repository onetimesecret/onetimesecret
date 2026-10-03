# spec/cli/notifications_deliveries_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots notifications deliveries` (#4479). The read
# itself belongs to Onetime::Operations::Notifications::ListDeliveryEvents
# (covered in its own spec); this covers the operator-input contract and the
# two output formats over a stubbed read, as the CLI lane runs against a
# Redis double.
#
# Run: tests/lanes/run unit --only spec/cli/notifications_deliveries_command_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'Notifications Deliveries Command', type: :cli do
  let(:op_class) { Onetime::Operations::Notifications::ListDeliveryEvents }
  let(:event) do
    {
      id: 'evt1',
      occurred_at: 1_700_000_000.5,
      channel: 'webhook',
      stage: 'delivery',
      outcome: 'failed',
      correlation_id: 'corr-1',
      message_id: nil,
      event_type: 'secret.viewed',
      template: 'secret_viewed',
      customer_id: nil,
      reason: 'http_status',
      error_class: nil,
      error_message: nil,
      http_status: 503,
      target_host: 'hooks.example.com',
      provider: nil,
      provider_message_id: nil,
      duration_ms: 42,
      attempt_count: 1,
    }
  end

  def stub_read(events)
    result = op_class::Result.new(
      events: events,
      limit: 50,
      offset: 0,
      more: false,
      retained: events.size,
      filters: {},
    )
    allow(op_class).to receive(:new).and_return(instance_double(op_class, call: result))
  end

  it 'rejects a non-positive --limit before reading the feed' do
    expect(op_class).not_to receive(:new)

    output = run_cli_command_quietly('notifications', 'deliveries', '--limit', '0')
    expect(output[:stderr]).to include('--limit must be a positive integer')
    expect(last_exit_code).to eq(1)
  end

  it 'reports an unknown outcome filter with a non-zero exit' do
    allow(op_class).to receive(:new).and_call_original

    output = run_cli_command_quietly('notifications', 'deliveries', '--outcome', 'delivered')
    expect(output[:stderr]).to include('outcome must be one of')
    expect(last_exit_code).to eq(1)
  end

  it 'passes the filters to the read operation' do
    stub_read([])

    run_cli_command_quietly('notifications', 'deliveries', '--channel', 'webhook', '--correlation', 'corr-1', '-n', '5')

    expect(op_class).to have_received(:new).with(
      limit: 5, offset: 0, channel: 'webhook', stage: nil, outcome: nil, correlation_id: 'corr-1', template: nil,
    )
    expect(last_exit_code).to eq(0)
  end

  it 'prints matching events as text and as json' do
    stub_read([event])

    text = run_cli_command_quietly('notifications', 'deliveries')
    expect(last_exit_code).to eq(0)
    expect(text[:stdout]).to include(
      'webhook',
      'delivery',
      'failed',
      'secret_viewed',
      'corr-1',
      'http=503',
      'host=hooks.example.com',
      '42ms',
    )

    json   = run_cli_command_quietly('notifications', 'deliveries', '--format', 'json')
    parsed = JSON.parse(json[:stdout])
    expect(parsed['events'].size).to eq(1)
    expect(parsed['events'].first).to include('outcome' => 'failed', 'http_status' => 503)
    expect(parsed['retained']).to eq(1)
  end

  it 'prints the complete correlation id for reuse with --correlation' do
    correlation_id = '550e8400-e29b-41d4-a716-446655440000'
    stub_read([event.merge(correlation_id: correlation_id)])

    output = run_cli_command_quietly('notifications', 'deliveries')
    expect(last_exit_code).to eq(0)
    expect(output[:stdout]).to include(correlation_id)

    run_cli_command_quietly('notifications', 'deliveries', '--correlation', correlation_id)
    expect(last_exit_code).to eq(0)
    expect(op_class).to have_received(:new).with(
      limit: 50, offset: 0, channel: nil, stage: nil, outcome: nil, correlation_id: correlation_id, template: nil,
    )
  end

  {
    channel: 'webhook',
    stage: 'delivery',
    outcome: 'failed',
    correlation: 'corr-1',
    template: 'secret_viewed',
  }.each do |filter, value|
    it "rejects --#{filter} with --counts instead of ignoring the filter" do
      stub_read([])
      allow(Onetime::DeliveryEvent).to receive(:daily_counts).and_return([])

      output = run_cli_command_quietly('notifications', 'deliveries', "--#{filter}", value, '--counts', '7')
      expect(output[:stderr]).to include('--counts cannot be combined with event filters', "--#{filter}")
      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to be_empty
      expect(Onetime::DeliveryEvent).not_to have_received(:daily_counts)
      expect(op_class).not_to have_received(:new)
    end
  end

  it 'reports all event filters combined with --counts' do
    allow(Onetime::DeliveryEvent).to receive(:daily_counts).and_return([])

    output = run_cli_command_quietly(
      'notifications', 'deliveries', '--channel', 'webhook', '--outcome', 'failed', '--counts', '7',
    )
    expect(output[:stderr]).to include('--counts cannot be combined with event filters', '--channel', '--outcome')
    expect(last_exit_code).to eq(1)
    expect(Onetime::DeliveryEvent).not_to have_received(:daily_counts)
  end

  [[], ['--counts', '7']].each do |mode|
    it "rejects an unknown --format in #{mode.empty? ? 'events' : 'counts'} mode before reading" do
      stub_read([])
      allow(Onetime::DeliveryEvent).to receive(:daily_counts).and_return([])

      output = run_cli_command_quietly('notifications', 'deliveries', *mode, '--format', 'jsn')
      expect(output[:stderr]).to include('--format must be one of: text, json')
      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to be_empty
      expect(op_class).not_to have_received(:new)
      expect(Onetime::DeliveryEvent).not_to have_received(:daily_counts)
    end
  end

  [0, -1].each do |days|
    it "rejects --counts #{days} before reading aggregates" do
      expect(Onetime::DeliveryEvent).not_to receive(:daily_counts)

      output = run_cli_command_quietly('notifications', 'deliveries', '--counts', days.to_s)
      expect(output[:stderr]).to include('--counts must be a positive integer')
      expect(last_exit_code).to eq(1)
    end
  end

  [Onetime::DeliveryEvent::COUNTS_TTL / 86_400 + 1, 100].uniq.each do |days|
    it "rejects --counts #{days} above the aggregate retention window" do
      allow(Onetime::DeliveryEvent).to receive(:daily_counts).and_return([])
      max_days = Onetime::DeliveryEvent::COUNTS_TTL / 86_400

      output = run_cli_command_quietly('notifications', 'deliveries', '--counts', days.to_s)
      expect(output[:stderr]).to include("--counts must be at most #{max_days} days")
      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to be_empty
      expect(Onetime::DeliveryEvent).not_to have_received(:daily_counts)
    end
  end

  it 'accepts the maximum retained --counts window' do
    max_days = Onetime::DeliveryEvent::COUNTS_TTL / 86_400
    allow(Onetime::DeliveryEvent).to receive(:daily_counts).with(max_days).and_return([])

    output = run_cli_command_quietly('notifications', 'deliveries', '--counts', max_days.to_s)
    expect(last_exit_code).to eq(0)
    expect(output[:stderr]).to be_empty
    expect(Onetime::DeliveryEvent).to have_received(:daily_counts).with(max_days)
  end

  it 'prints per-day totals as json with --counts' do
    rows = [{ date: '20260930', counts: { 'email:queue:queued' => 2 } }]
    allow(Onetime::DeliveryEvent).to receive(:daily_counts).with(1).and_return(rows)

    output = run_cli_command_quietly('notifications', 'deliveries', '--counts', '1', '--format', 'json')
    expect(last_exit_code).to eq(0)
    expect(JSON.parse(output[:stdout])).to eq(JSON.parse(JSON.generate(rows)))
  end

  it 'prints per-day totals with --counts' do
    allow(Onetime::DeliveryEvent).to receive(:daily_counts).with(1)
      .and_return([{ date: '20260930', counts: { 'email:queue:queued' => 2 } }])

    output = run_cli_command_quietly('notifications', 'deliveries', '--counts', '1')
    expect(last_exit_code).to eq(0)
    expect(output[:stdout]).to include('20260930', 'email:queue:queued=2')
  end
end
