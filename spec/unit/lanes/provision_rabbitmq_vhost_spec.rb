# spec/unit/lanes/provision_rabbitmq_vhost_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('../../../tests/lanes/support/provision_rabbitmq_vhost', __dir__)

RSpec.describe ProvisionRabbitmqVhost do
  let(:url) { 'amqp://lane-user:secret@127.0.0.1:2156/w123' }
  let(:http) { instance_double(Net::HTTP) }
  let(:requests) { [] }

  def response(code, message)
    instance_double(Net::HTTPResponse, code: code.to_s, body: '', message: message)
  end

  before do
    allow(described_class).to receive(:warn)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) do |request|
      requests << request
      responses.shift || raise('unexpected RabbitMQ management request')
    end
  end

  describe '.run' do
    context 'with the default reset mode' do
      let(:responses) do
        [
          response(204, 'No Content'),
          response(201, 'Created'),
          response(204, 'No Content'),
        ]
      end

      it 'deletes and recreates the vhost before applying permissions' do
        described_class.run(url)

        expect(requests.map(&:class)).to eq([
          Net::HTTP::Delete,
          Net::HTTP::Put,
          Net::HTTP::Put,
        ])
        expect(requests.map(&:path)).to eq([
          '/api/vhosts/w123',
          '/api/vhosts/w123',
          '/api/permissions/w123/lane-user',
        ])
      end
    end

    context 'when preserving an existing vhost' do
      let(:responses) do
        [
          response(204, 'No Content'),
          response(204, 'No Content'),
        ]
      end

      it 'does not delete the vhost and reapplies permissions' do
        described_class.run(url, preserve_existing: true)

        expect(requests.map(&:class)).to eq([Net::HTTP::Put, Net::HTTP::Put])
        expect(requests).not_to include(an_instance_of(Net::HTTP::Delete))
        expect(JSON.parse(requests.last.body)).to eq(
          'configure' => '.*',
          'write' => '.*',
          'read' => '.*',
        )
      end
    end

    context 'when preserving a missing vhost' do
      let(:responses) do
        [
          response(201, 'Created'),
          response(204, 'No Content'),
        ]
      end

      it 'creates the vhost without issuing a delete' do
        described_class.run(url, preserve_existing: true)

        expect(requests.map(&:class)).to eq([Net::HTTP::Put, Net::HTTP::Put])
        expect(requests.first.path).to eq('/api/vhosts/w123')
      end
    end
  end

  describe '.main' do
    let(:responses) { [] }

    before do
      allow(described_class).to receive(:run)
    end

    it 'uses reset mode by default' do
      status = described_class.main([], env: { 'RABBITMQ_URL' => url })

      expect(status).to eq(0)
      expect(described_class).to have_received(:run).with(url, preserve_existing: false)
    end

    it 'selects preserve mode explicitly' do
      status = described_class.main(['--preserve-existing'], env: { 'RABBITMQ_URL' => url })

      expect(status).to eq(0)
      expect(described_class).to have_received(:run).with(url, preserve_existing: true)
    end
  end
end
