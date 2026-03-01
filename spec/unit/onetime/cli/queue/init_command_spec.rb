# spec/unit/onetime/cli/queue/init_command_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/cli'

RSpec.describe Onetime::CLI::Queue::InitCommand do
  subject(:command) { described_class.new }

  let(:vhost) { 'ots_test' }
  let(:amqp_url) { "amqp://admin:secret@rmq.example.com:5672/#{vhost}" }
  let(:management_base) { 'http://rmq.example.com:15672' }
  let(:policy) { Onetime::Jobs::QueueConfig::DLQ_POLICIES.first }
  let(:encoded_vhost) { URI.encode_www_form_component(vhost) }
  let(:encoded_name) { URI.encode_www_form_component(policy[:name]) }
  let(:policy_url) { "#{management_base}/api/policies/#{encoded_vhost}/#{encoded_name}" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RABBITMQ_URL', anything).and_return(amqp_url)
    allow(ENV).to receive(:fetch).with('RABBITMQ_MANAGEMENT_URL', anything).and_return(management_base)
    allow(command).to receive(:boot_application!)
    allow(command).to receive(:create_vhost)
    allow(command).to receive(:set_permissions)
    allow(command).to receive(:declare_infrastructure)
    allow(command).to receive(:puts)
    allow(command).to receive(:print)
  end

  describe '#set_dlq_policies (via call with force: true)' do
    before do
      allow(command).to receive(:set_dlq_policies).and_call_original
    end

    context 'when policy is applied successfully (HTTP 204)' do
      before { stub_request(:put, policy_url).to_return(status: 204, body: '') }

      it 'logs success for each policy' do
        expect(command).to receive(:puts).with(/Policy 'dlq-ttl' applied to vhost '#{vhost}'/)
        command.call(force: true, dry_run: false)
      end
    end

    context 'when policy is created new (HTTP 201)' do
      before { stub_request(:put, policy_url).to_return(status: 201, body: '') }

      it 'logs success' do
        expect(command).to receive(:puts).with(/Policy 'dlq-ttl' applied/)
        command.call(force: true, dry_run: false)
      end
    end

    context 'when Management API returns an error (HTTP 422)' do
      before { stub_request(:put, policy_url).to_return(status: 422, body: '{"error":"bad"}') }

      it 'logs a warning but does not raise' do
        expect(command).to receive(:puts).with(/WARNING: Failed to apply policy 'dlq-ttl': 422/)
        expect { command.call(force: true, dry_run: false) }.not_to raise_error
      end
    end

    context 'when connection is refused' do
      before { stub_request(:put, policy_url).to_raise(Errno::ECONNREFUSED) }

      it 'logs a warning with rabbitmqctl fallback' do
        expect(command).to receive(:puts).with(/WARNING: Cannot connect to RabbitMQ Management API/)
        expect(command).to receive(:puts).with(/rabbitmqctl set_policy/)
        expect { command.call(force: true, dry_run: false) }.not_to raise_error
      end
    end

    context 'request structure' do
      it 'sends PUT with correct URI, basic auth, and content type' do
        stub = stub_request(:put, policy_url)
          .with(
            basic_auth: %w[admin secret],
            headers: { 'Content-Type' => 'application/json' }
          )
          .to_return(status: 204, body: '')

        command.call(force: true, dry_run: false)
        expect(stub).to have_been_requested
      end

      it 'sends correct policy body matching DLQ_POLICIES config' do
        stub_request(:put, policy_url).to_return(status: 204, body: '')
        command.call(force: true, dry_run: false)

        expect(a_request(:put, policy_url).with { |req|
          body = JSON.parse(req.body)
          body['pattern'] == policy[:pattern] &&
            body['definition'] == policy[:definition] &&
            body['apply-to'] == policy[:apply_to] &&
            body['priority'] == policy[:priority]
        }).to have_been_made
      end

      it 'includes message-ttl matching DLQ_MESSAGE_TTL in definition' do
        stub_request(:put, policy_url).to_return(status: 204, body: '')
        command.call(force: true, dry_run: false)

        expect(a_request(:put, policy_url).with { |req|
          body = JSON.parse(req.body)
          body['definition']['message-ttl'] == Onetime::Jobs::QueueConfig::DLQ_MESSAGE_TTL
        }).to have_been_made
      end
    end

    context 'when dry_run is true' do
      it 'does not make any HTTP requests' do
        command.call(force: true, dry_run: true)
        expect(a_request(:put, policy_url)).not_to have_been_made
      end
    end
  end
end
