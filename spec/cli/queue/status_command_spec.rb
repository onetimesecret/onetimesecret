# spec/cli/queue/status_command_spec.rb
#
# frozen_string_literal: true

require_relative '../cli_spec_helper'
require 'onetime/cli/queue/status_command'

RSpec.describe Onetime::CLI::Queue::StatusCommand, type: :cli do
  let(:command) { described_class.new }

  describe '#check_dlq_policies' do
    let(:response_200) { instance_double(Net::HTTPResponse, code: '200', body: policies_json) }
    let(:response_404) { instance_double(Net::HTTPResponse, code: '404', body: '') }

    let(:policies_json) do
      JSON.generate([
        { 'name' => 'dlq.ttl', 'pattern' => 'dlq.jobs', 'definition' => { 'message-ttl' => 86_400_000 } },
        { 'name' => 'other',   'pattern' => 'foo-dlq-bar', 'definition' => {} },
        { 'name' => 'unrelated', 'pattern' => 'workers', 'definition' => {} },
      ])
    end

    before do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(stubbed_response)
    end

    context 'when management API returns 200' do
      let(:stubbed_response) { response_200 }

      it 'returns only policies whose pattern starts with dlq.' do
        result = command.send(:check_dlq_policies)
        expect(result).to be_an(Array)
        expect(result.map { |p| p['pattern'] }).to eq(['dlq.jobs'])
      end

      it 'excludes policies with dlq elsewhere in the pattern' do
        result = command.send(:check_dlq_policies)
        patterns = result.map { |p| p['pattern'] }
        expect(patterns).not_to include('foo-dlq-bar')
      end
    end

    context 'when management API returns non-200' do
      let(:stubbed_response) { response_404 }

      it 'returns nil' do
        result = command.send(:check_dlq_policies)
        expect(result).to be_nil
      end
    end

    context 'when management API raises an error' do
      let(:stubbed_response) { response_200 } # won't be reached

      before do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns nil' do
        result = command.send(:check_dlq_policies)
        expect(result).to be_nil
      end
    end
  end

  describe '#display_text_status' do
    let(:base_status) do
      {
        timestamp: '2026-02-18T00:00:00Z',
        rabbitmq: { connected: false, error: 'connection refused' },
        exchanges: {},
        queues: {},
        scheduler: { running: false },
      }
    end

    it 'prints "Management API unavailable" when dlq_policies is nil' do
      status = base_status.merge(dlq_policies: nil)
      output = capture_output { command.send(:display_text_status, status) }
      expect(output[:stdout]).to include('Management API unavailable')
    end

    it 'prints "none" when dlq_policies is an empty array' do
      status = base_status.merge(dlq_policies: [])
      output = capture_output { command.send(:display_text_status, status) }
      expect(output[:stdout]).to include('none')
    end

    it 'prints policy details when dlq_policies has entries' do
      policy = {
        'name' => 'dlq.ttl',
        'pattern' => 'dlq.jobs',
        'definition' => { 'message-ttl' => 3_600_000 },
      }
      status = base_status.merge(dlq_policies: [policy])
      output = capture_output { command.send(:display_text_status, status) }
      expect(output[:stdout]).to include('dlq.ttl')
      expect(output[:stdout]).to include('dlq.jobs')
    end
  end
end
