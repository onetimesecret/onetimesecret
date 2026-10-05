# spec/lib/onetime/jobs/workers/envelope_spec.rb
#
# frozen_string_literal: true

# Purpose:
#   Verifies Onetime::Jobs::Workers::Envelope, the frozen value a worker
#   builds from (delivery_info, metadata) at the top of work_with_params
#   and passes to the BaseWorker helpers.
#
# Test Categories:
#   - Nil envelope: every reader answers without raising
#   - Message id, delivery tag, routing key, redelivered?
#   - Schema version: known, unknown, missing header, nil headers
#   - Trace headers
#   - Log summary and inspect output
#
# Setup Requirements:
#   - None: no datastore, no broker

require 'spec_helper'
require 'support/amqp_stubs'
require 'onetime/jobs/workers/envelope'

RSpec.describe Onetime::Jobs::Workers::Envelope do
  subject(:envelope) { described_class.new(delivery_info, metadata) }

  let(:delivery_info) do
    DeliveryInfoStub.new(delivery_tag: 7, routing_key: 'email.message.send', redelivered?: false)
  end
  let(:headers) { { 'x-schema-version' => 1 } }
  let(:metadata) { MetadataStub.new(message_id: 'msg-12345-abcde', headers: headers) }

  it 'is frozen' do
    expect(envelope).to be_frozen
  end

  it 'exposes the delivery info and properties it was built from' do
    expect(envelope.delivery_info).to equal(delivery_info)
    expect(envelope.metadata).to equal(metadata)
  end

  describe 'built from nil delivery info and nil properties' do
    { 'explicit nils' => [nil, nil], 'no arguments' => [] }.each do |label, args|
      it "answers every reader without raising (#{label})" do
        empty = described_class.new(*args)

        expect(empty.message_id).to be_nil
        expect(empty.delivery_tag).to be_nil
        expect(empty.routing_key).to be_nil
        expect(empty.redelivered?).to be_nil
        expect(empty.headers).to be_nil
        expect(empty.schema_version_header).to be_nil
        expect(empty.trace_headers).to eq({})
        expect(empty).to be_frozen
      end
    end

    it 'reads as schema version 1, which is known' do
      empty = described_class.new(nil, nil)

      expect(empty.schema_version).to eq(1)
      expect(empty.schema_version_known?).to be true
    end

    it 'summarizes to nil fields' do
      expect(described_class.new(nil, nil).summary).to eq(
        delivery_tag: nil,
        routing_key: nil,
        redelivered: nil,
        message_id: nil,
        schema_version: nil,
      )
    end
  end

  describe '#message_id' do
    it 'is the AMQP message_id property' do
      expect(envelope.message_id).to eq('msg-12345-abcde')
    end

    it 'is nil when the message was published without one' do
      expect(described_class.new(delivery_info, MetadataStub.new(message_id: nil, headers: headers)).message_id).to be_nil
    end

    it 'does not depend on the delivery info' do
      expect(described_class.new(nil, metadata).message_id).to eq('msg-12345-abcde')
    end
  end

  describe 'delivery facts' do
    it 'reads the delivery tag and routing key' do
      expect(envelope.delivery_tag).to eq(7)
      expect(envelope.routing_key).to eq('email.message.send')
    end

    it 'is not redelivered on a first delivery' do
      expect(envelope.redelivered?).to be false
    end

    it 'is redelivered when the broker says so' do
      redelivered = DeliveryInfoStub.new(delivery_tag: 8, routing_key: 'email.message.send', redelivered?: true)

      expect(described_class.new(redelivered, metadata).redelivered?).to be true
    end
  end

  describe 'schema version' do
    context 'with a version this build understands' do
      it 'is known' do
        expect(envelope.schema_version_header).to eq(1)
        expect(envelope.schema_version).to eq(1)
        expect(envelope.schema_version_known?).to be true
      end
    end

    context 'with an unknown version' do
      let(:headers) { { 'x-schema-version' => 999 } }

      it 'is not known and keeps the published value' do
        expect(envelope.schema_version).to eq(999)
        expect(envelope.schema_version_known?).to be false
      end
    end

    context 'with a version that is not a version number' do
      let(:headers) { { 'x-schema-version' => '1; drop' } }

      it 'is not known' do
        expect(envelope.schema_version_known?).to be false
      end
    end

    context 'with no version header' do
      let(:headers) { {} }

      it 'reads as version 1' do
        expect(envelope.schema_version_header).to be_nil
        expect(envelope.schema_version).to eq(1)
        expect(envelope.schema_version_known?).to be true
      end
    end

    context 'with nil headers' do
      let(:headers) { nil }

      it 'reads as version 1' do
        expect(envelope.headers).to be_nil
        expect(envelope.schema_version).to eq(1)
        expect(envelope.schema_version_known?).to be true
      end
    end
  end

  describe '#trace_headers' do
    context 'when the message carries trace headers' do
      let(:headers) do
        {
          'x-schema-version' => 1,
          'sentry-trace' => '00-abcd1234-5678ef90-01',
          'baggage' => 'sentry-environment=production',
        }
      end

      it 'returns only the trace headers' do
        expect(envelope.trace_headers).to eq(
          'sentry-trace' => '00-abcd1234-5678ef90-01',
          'baggage' => 'sentry-environment=production',
        )
      end
    end

    context 'when the message carries none' do
      it 'is empty' do
        expect(envelope.trace_headers).to eq({})
      end
    end

    context 'when headers are nil' do
      let(:headers) { nil }

      it 'is empty' do
        expect(envelope.trace_headers).to eq({})
      end
    end
  end

  describe '#summary' do
    it 'holds the envelope fields workers put in log lines' do
      expect(envelope.summary).to eq(
        delivery_tag: 7,
        routing_key: 'email.message.send',
        redelivered: false,
        message_id: 'msg-12345-abcde',
        schema_version: 1,
      )
    end
  end

  describe '#inspect' do
    it 'shows the summary and not the delivery info or properties objects' do
      expect(envelope.inspect).to include('msg-12345-abcde')
      expect(envelope.inspect).not_to include('DeliveryInfoStub', 'MetadataStub')
      expect(envelope.to_s).to eq(envelope.inspect)
    end
  end
end
