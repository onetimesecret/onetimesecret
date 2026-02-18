# spec/unit/onetime/cli/queue/status_command_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/cli'
require 'onetime/cli/queue/status_command'

RSpec.describe Onetime::CLI::Queue::StatusCommand do
  subject(:command) { described_class.new }

  describe '#check_dlq_policies' do
    let(:http_instance) { instance_double(Net::HTTP) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('RABBITMQ_URL', anything).and_return('amqp://guest:guest@localhost:5672')
      allow(ENV).to receive(:fetch).with('RABBITMQ_MANAGEMENT_URL', anything).and_return('http://localhost:15672')
      allow(Net::HTTP).to receive(:new).and_return(http_instance)
      allow(http_instance).to receive(:use_ssl=)
      allow(http_instance).to receive(:open_timeout=)
      allow(http_instance).to receive(:read_timeout=)
    end

    context 'when API returns 200 with DLQ policies' do
      let(:policies_json) do
        [
          { 'name' => 'dlq-ttl', 'pattern' => '^dlq\\.', 'definition' => { 'message-ttl' => 604_800_000 }, 'apply-to' => 'queues' },
          { 'name' => 'ha-all', 'pattern' => '.*', 'definition' => { 'ha-mode' => 'all' }, 'apply-to' => 'all' },
        ].to_json
      end
      let(:response) { instance_double(Net::HTTPSuccess, code: '200', body: policies_json) }

      before { allow(http_instance).to receive(:request).and_return(response) }

      it 'returns only policies whose pattern contains dlq' do
        result = command.send(:check_dlq_policies)
        expect(result.length).to eq(1)
        expect(result.first['name']).to eq('dlq-ttl')
      end
    end

    context 'when API returns 200 with no DLQ policies' do
      let(:policies_json) do
        [{ 'name' => 'ha-all', 'pattern' => '.*', 'definition' => {}, 'apply-to' => 'all' }].to_json
      end
      let(:response) { instance_double(Net::HTTPSuccess, code: '200', body: policies_json) }

      before { allow(http_instance).to receive(:request).and_return(response) }

      it 'returns empty array' do
        expect(command.send(:check_dlq_policies)).to eq([])
      end
    end

    context 'when API returns non-200 status' do
      let(:response) { instance_double(Net::HTTPForbidden, code: '403', body: 'Forbidden') }

      before { allow(http_instance).to receive(:request).and_return(response) }

      it 'returns empty array' do
        expect(command.send(:check_dlq_policies)).to eq([])
      end
    end

    context 'when connection is refused' do
      before { allow(http_instance).to receive(:request).and_raise(Errno::ECONNREFUSED) }

      it 'returns nil' do
        expect(command.send(:check_dlq_policies)).to be_nil
      end
    end

    context 'when connection times out' do
      before { allow(http_instance).to receive(:request).and_raise(Net::OpenTimeout) }

      it 'returns nil for open timeout' do
        expect(command.send(:check_dlq_policies)).to be_nil
      end
    end

    context 'when read times out' do
      before { allow(http_instance).to receive(:request).and_raise(Net::ReadTimeout) }

      it 'returns nil for read timeout' do
        expect(command.send(:check_dlq_policies)).to be_nil
      end
    end

    context 'when an unexpected error occurs' do
      before { allow(http_instance).to receive(:request).and_raise(StandardError, 'boom') }

      it 'returns nil' do
        expect(command.send(:check_dlq_policies)).to be_nil
      end
    end

    it 'requests GET /api/policies/{vhost}' do
      response = instance_double(Net::HTTPSuccess, code: '200', body: '[]')
      allow(http_instance).to receive(:request).and_return(response)

      command.send(:check_dlq_policies)

      expect(http_instance).to have_received(:request) do |req|
        expect(req).to be_a(Net::HTTP::Get)
        expect(req.path).to eq('/api/policies/%2F')
      end
    end
  end

  describe '#format_ttl' do
    it 'formats milliseconds >= 1 day as Nms (Nd)' do
      expect(command.send(:format_ttl, 604_800_000)).to eq('604800000ms (7d)')
    end

    it 'formats milliseconds >= 1 hour as Nms (Nh)' do
      expect(command.send(:format_ttl, 7_200_000)).to eq('7200000ms (2h)')
    end

    it 'formats milliseconds < 1 hour as Nms' do
      expect(command.send(:format_ttl, 30_000)).to eq('30000ms')
    end

    it 'treats exactly 1 day boundary correctly' do
      one_day_ms = 86_400 * 1000
      expect(command.send(:format_ttl, one_day_ms)).to eq('86400000ms (1d)')
    end

    it 'treats exactly 1 hour boundary correctly' do
      one_hour_ms = 3600 * 1000
      expect(command.send(:format_ttl, one_hour_ms)).to eq('3600000ms (1h)')
    end
  end

  describe '#display_text_status (DLQ Policies section)' do
    let(:base_status) do
      {
        timestamp: '2026-02-18T00:00:00Z',
        rabbitmq: { connected: false, error: 'test' },
        exchanges: {},
        queues: {},
        dlq_policies: dlq_policies,
        scheduler: { running: false },
      }
    end

    context 'when policies is nil (API unavailable)' do
      let(:dlq_policies) { nil }

      it 'shows Management API unavailable' do
        output = capture_stdout { command.send(:display_text_status, base_status) }
        expect(output).to include('Management API unavailable')
      end
    end

    context 'when policies is empty array' do
      let(:dlq_policies) { [] }

      it 'shows none' do
        output = capture_stdout { command.send(:display_text_status, base_status) }
        expect(output).to match(/DLQ Policies:\n\s+none/)
      end
    end

    context 'when policies are present' do
      let(:dlq_policies) do
        [
          {
            'name' => 'dlq-ttl',
            'pattern' => '^dlq\\.',
            'definition' => { 'message-ttl' => 604_800_000 },
          },
        ]
      end

      it 'shows policy name, pattern, and formatted TTL' do
        output = capture_stdout { command.send(:display_text_status, base_status) }
        expect(output).to include('dlq-ttl')
        expect(output).to include('pattern=^dlq\\.')
        expect(output).to include('message-ttl=604800000ms (7d)')
      end
    end

    context 'when policy has no message-ttl' do
      let(:dlq_policies) do
        [{ 'name' => 'dlq-no-ttl', 'pattern' => 'dlq', 'definition' => {} }]
      end

      it 'shows n/a for TTL' do
        output = capture_stdout { command.send(:display_text_status, base_status) }
        expect(output).to include('message-ttl=n/a')
      end
    end
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
