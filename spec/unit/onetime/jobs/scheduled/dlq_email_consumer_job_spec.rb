# spec/unit/onetime/jobs/scheduled/dlq_email_consumer_job_spec.rb
#
# frozen_string_literal: true

# DlqEmailConsumerJob's AMQP transaction handling, with channel doubles: the
# order of tx_select, publish, ack/nack, and tx_commit, and where a failure
# stops the batch. The same paths against a real broker are in
# spec/integration/all/jobs/dlq_email_consumer_transaction_spec.rb.

require 'spec_helper'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'

RSpec.describe Onetime::Jobs::Scheduled::DlqEmailConsumerJob do
  let(:logger) { double('logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:payload) { JSON.generate('raw' => true, 'email' => { 'to' => 'test@example.com' }) }
  let(:properties) do
    double('properties', message_id: 'dlq-message-1', content_type: 'application/json',
      headers: { 'x-death' => [{ 'queue' => 'email.message.send' }], 'x-schema-version' => 1 })
  end
  let(:delivery) { double('delivery', delivery_tag: 1) }
  let(:exchange) { double('exchange', publish: nil) }
  let(:channel) do
    double('channel', default_exchange: exchange, ack: nil, nack: nil,
      tx_select: nil, tx_commit: nil, tx_rollback: nil, open?: true, close: nil)
  end
  let(:queue) { double('queue', message_count: 2) }

  before do
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(described_class).to receive(:claim_replay).and_return(true)
    allow(described_class).to receive(:acquire_channel).and_return([nil, channel, false])
    allow(channel).to receive(:queue).with(described_class::DLQ_NAME, durable: true, passive: true).and_return(queue)
    allow(queue).to receive(:pop).with(manual_ack: true).and_return(
      [delivery, properties, payload], [double('delivery2', delivery_tag: 2), properties, payload])
  end

  def run_batch
    described_class.send(:consume_dlq_batch)
  end

  it 'selects transactions before popping and commits publish and ack in order' do
    allow(queue).to receive(:message_count).and_return(1)
    expect(channel).to receive(:tx_select).ordered
    expect(queue).to receive(:pop).with(manual_ack: true).ordered.and_return([delivery, properties, payload])
    expect(exchange).to receive(:publish).with(payload, routing_key: 'email.message.send',
      persistent: true, message_id: 'dlq-message-1', content_type: 'application/json',
      headers: { 'x-schema-version' => 1 }).ordered
    expect(channel).to receive(:ack).with(1).ordered
    expect(channel).to receive(:tx_commit).ordered
    expect(logger).to receive(:info).with(/replayed=1/)
    run_batch
  end

  [:publish, :ack].each do |failure|
    it "rolls back a failed #{failure}, leaves it unacked, and continues to the next message" do
      target = failure == :publish ? exchange : channel
      calls = 0
      allow(target).to receive(failure) do
        calls += 1
        raise IOError, 'interrupted before commit' if calls == 1
      end
      expect(channel).to receive(:tx_rollback).once.ordered
      expect(channel).to receive(:tx_commit).once.ordered
      expect(channel).not_to receive(:nack)
      expect(logger).to receive(:error).with(/rolled back before commit: IOError/, message_id: 'dlq-message-1')
      expect(logger).to receive(:info).with(/replayed=1.*deferred=1/)
      run_batch
    end
  end

  it 'stops without settling the delivery or popping another message when rollback fails' do
    allow(channel).to receive(:ack).and_raise(IOError, 'ack interrupted')
    allow(channel).to receive(:tx_rollback).and_raise(IOError, 'channel closed')
    expect(queue).to receive(:pop).once
    expect(channel).not_to receive(:tx_commit)
    expect(channel).not_to receive(:nack)
    expect(logger).to receive(:error).with(/rollback failed; batch stopped/i, message_id: 'dlq-message-1')
    expect(channel).to receive(:close)
    run_batch
  end

  it 'stops on an unconfirmed commit without rollback, nack, or another pop' do
    allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
    expect(queue).to receive(:pop).once
    expect(channel).not_to receive(:tx_rollback)
    expect(channel).not_to receive(:nack)
    expect(logger).to receive(:error).with(
      /outcome unknown.*may already be republished.*counts before the stop: replayed=0/i,
      message_id: 'dlq-message-1',
    )
    expect(logger).not_to receive(:info).with(/Batch complete/)
    expect(channel).to receive(:close)
    run_batch
  end

  {
    'non-auth' => JSON.generate('template' => 'secret_link'),
    'missing token' => JSON.generate('template' => 'password_reset', 'data' => {}),
    'expired token' => JSON.generate('template' => 'password_reset', 'data' => { 'account_id' => 123 }),
    'invalid JSON' => '{invalid',
  }.each do |name, body|
    it "commits the #{name} discard in transaction mode" do
      allow(described_class).to receive(:token_expired?).and_return(true)
      allow(queue).to receive(:message_count).and_return(1)
      allow(queue).to receive(:pop).and_return([delivery, properties, body])
      expect(channel).to receive(:nack).with(1, false, false).ordered
      expect(channel).to receive(:tx_commit).ordered
      expect(exchange).not_to receive(:publish)
      run_batch
    end
  end

  it 'commits the missing-route discard in transaction mode' do
    allow(properties).to receive(:headers).and_return(nil)
    allow(queue).to receive(:message_count).and_return(1)
    expect(channel).to receive(:nack).with(1, false, false).ordered
    expect(channel).to receive(:tx_commit).ordered
    expect(exchange).not_to receive(:publish)
    run_batch
  end

  it 'commits the duplicate ack without republishing' do
    allow(described_class).to receive(:claim_replay).and_return(false)
    allow(queue).to receive(:message_count).and_return(1)
    expect(channel).to receive(:ack).with(1).ordered
    expect(channel).to receive(:tx_commit).ordered
    expect(exchange).not_to receive(:publish)
    run_batch
  end

  it 'stops on a failed duplicate ack rather than nacking the same delivery' do
    allow(described_class).to receive(:claim_replay).and_return(false)
    allow(channel).to receive(:ack).and_raise(IOError, 'ack interrupted')
    expect(queue).to receive(:pop).once
    expect(channel).not_to receive(:nack)
    expect(channel).not_to receive(:tx_commit)
    expect(logger).to receive(:error).with(/duplicate acknowledgement failed before commit/i,
      message_id: 'dlq-message-1')
    run_batch
  end

  it 'stops on an unconfirmed discard commit rather than nacking twice' do
    allow(queue).to receive(:pop).and_return([delivery, properties, '{invalid'])
    allow(channel).to receive(:tx_commit).and_raise(IOError, 'commit reply lost')
    expect(queue).to receive(:pop).once
    expect(channel).to receive(:nack).with(1, false, false).once
    expect(channel).not_to receive(:tx_rollback)
    expect(logger).to receive(:error).with(/outcome unknown.*discard/i, message_id: 'dlq-message-1')
    run_batch
  end

  it 'does not start a transaction for an empty DLQ' do
    allow(queue).to receive(:message_count).and_return(0)
    expect(channel).not_to receive(:tx_select)
    expect(queue).not_to receive(:pop)
    run_batch
  end
end
