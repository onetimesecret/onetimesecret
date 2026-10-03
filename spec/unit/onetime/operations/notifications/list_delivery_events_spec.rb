# spec/unit/onetime/operations/notifications/list_delivery_events_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/notifications/list_delivery_events'

# The shared read path over the delivery-event feed (#4479). Runs against the
# real Familia-backed sorted set on the test database.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/operations/notifications/list_delivery_events_spec.rb
RSpec.describe Onetime::Operations::Notifications::ListDeliveryEvents do
  before { Onetime::DeliveryEvent.events.clear }
  after  { Onetime::DeliveryEvent.events.clear }

  def record(**fields)
    Onetime::DeliveryEvent.record(**fields)
  end

  it 'projects every field explicitly, newest first' do
    record(channel: 'email', stage: 'queue', outcome: 'queued', correlation_id: 'c1')
    newest = record(channel: 'webhook', stage: 'delivery', outcome: 'sent', correlation_id: 'c1', http_status: 200)

    result = described_class.new.call

    expect(result.events.size).to eq(2)
    expect(result.events.first.keys).to eq(described_class::FIELDS.map(&:to_sym))
    expect(result.events.first).to include(id: newest['id'], http_status: 200, provider: nil)
    expect(result.retained).to eq(2)
    expect(result.more).to be false
  end

  it 'filters by channel, outcome and correlation id' do
    record(channel: 'email', stage: 'queue', outcome: 'queued', correlation_id: 'c1')
    record(channel: 'email', stage: 'delivery', outcome: 'failed', correlation_id: 'c1')
    record(channel: 'webhook', stage: 'delivery', outcome: 'failed', correlation_id: 'c2')

    failed = described_class.new(outcome: 'failed').call
    expect(failed.events.map { |event| event[:channel] }).to contain_exactly('email', 'webhook')

    chain = described_class.new(correlation_id: 'c1').call
    expect(chain.events.map { |event| event[:stage] }).to eq(%w[delivery queue])

    email_failed = described_class.new(channel: 'email', outcome: 'failed').call
    expect(email_failed.events.size).to eq(1)
    expect(email_failed.filters).to eq(channel: 'email', outcome: 'failed')
  end

  it 'pages through matches with limit and offset and reports more' do
    5.times { |n| record(channel: 'email', stage: 'queue', outcome: 'queued', correlation_id: "c#{n}") }

    page1 = described_class.new(limit: 2).call
    page2 = described_class.new(limit: 2, offset: 2).call
    page3 = described_class.new(limit: 2, offset: 4).call

    expect(page1.events.map { |event| event[:correlation_id] }).to eq(%w[c4 c3])
    expect(page1.more).to be true
    expect(page2.events.map { |event| event[:correlation_id] }).to eq(%w[c2 c1])
    expect(page2.more).to be true
    expect(page3.events.map { |event| event[:correlation_id] }).to eq(%w[c0])
    expect(page3.more).to be false
  end

  it 'walks past the first page when a filter matches only older events' do
    stub_const('Onetime::Operations::Notifications::ListDeliveryEvents::PAGE', 2)
    record(channel: 'webhook', stage: 'delivery', outcome: 'sent')
    3.times { record(channel: 'email', stage: 'queue', outcome: 'queued') }

    result = described_class.new(channel: 'webhook').call

    expect(result.events.size).to eq(1)
    expect(result.more).to be false
  end

  it 'rejects an unknown enum filter value' do
    expect { described_class.new(outcome: 'delivered').call }
      .to raise_error(ArgumentError, /outcome must be one of/)
  end

  it 'ignores blank filters and clamps the limit' do
    op     = described_class.new(limit: 10_000, offset: -3, channel: ' ', outcome: nil)
    result = op.call

    expect(result.filters).to eq({})
    expect(result.limit).to eq(described_class::MAX_LIMIT)
    expect(result.offset).to eq(0)
  end
end
