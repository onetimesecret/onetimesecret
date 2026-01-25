# spec/integration/all/operations/dispatch_notification_spec.rb
#
# frozen_string_literal: true

# DispatchNotification Operation Test Suite
#
# Tests the notification dispatch operation that delivers notifications
# to multiple channels: via_bell (Redis), via_email (queue), via_webhook (HTTP).
#
# Test Categories:
#
#   1. In-app notification delivery (Integration)
#      - Verifies Redis list storage with correct structure
#      - Tests TTL and list trimming behavior
#
#   2. Email notification delivery (Unit)
#      - Verifies Publisher.publish is called with correct payload
#      - Tests email payload structure
#
#   3. Webhook notification delivery (Unit)
#      - Verifies HTTP POST is made with correct payload
#      - Tests error handling for failed webhooks
#
#   4. Multi-channel delivery (Integration)
#      - Tests delivery to all three channels simultaneously
#      - Tests partial success scenarios
#
#   5. Channel resolution (Unit)
#      - Tests default channel behavior
#      - Tests invalid channel filtering
#
# Setup Requirements:
#   - Redis test instance at VALKEY_URL='valkey://127.0.0.1:2121/0'
#   - Mocked Onetime::Jobs::Publisher for email queueing
#   - Mocked Net::HTTP for webhook delivery
#
# Run with: pnpm run test:rspec spec/onetime/operations/dispatch_notification_spec.rb

require 'spec_helper'
require 'onetime/operations/dispatch_notification'

RSpec.describe Onetime::Operations::DispatchNotification, type: :integration do
  let(:custid) { 'cust:test-user-456' }

  # Helper to stub Addrinfo for SSRF validation in webhook tests.
  # Must be called explicitly in webhook test contexts to avoid interfering with Redis client.
  # Uses and_call_original as fallback so Redis connections still work.
  def stub_public_ip_resolution
    addr = instance_double(Addrinfo)
    allow(addr).to receive(:ip_address).and_return('93.184.216.34') # example.com public IP

    # Stub for webhook hostnames, let other calls (e.g., Redis) pass through
    # Uses DomainParser.hostname_within_domain? for secure domain boundary checking
    # to prevent matching attacker-controlled domains like 'attacker-example.com'
    allow(Addrinfo).to receive(:getaddrinfo).and_call_original
    allow(Addrinfo).to receive(:getaddrinfo)
      .with(satisfy { |h| Onetime::Utils::DomainParser.hostname_within_domain?(h, 'example.com') }, anything, anything, anything)
      .and_return([addr])
  end

  let(:base_data) do
    {
      type: 'secret.viewed',
      addressee: {
        custid: custid,
        email: 'user@example.com',
        webhook_url: 'https://example.com/webhook'
      },
      template: 'secret_viewed',
      locale: 'en',
      channels: ['via_bell'],
      data: {
        secret_key: 'abc123',
        viewed_at: '2024-01-15T10:30:00Z'
      }
    }
  end


  describe '#call' do
    context 'in-app notification delivery' do
      let(:data) { base_data.merge(channels: ['via_bell']) }
      let(:operation) { described_class.new(data: data) }

      it 'stores notification in Redis list' do
        results = operation.call

        expect(results[:via_bell]).to eq(:success)

        notifications = Familia.dbclient.lrange("notifications:#{custid}", 0, -1)
        expect(notifications.length).to eq(1)

        notification = JSON.parse(notifications.first, symbolize_names: true)
        expect(notification[:type]).to eq('secret.viewed')
        expect(notification[:template]).to eq('secret_viewed')
        expect(notification[:data][:secret_key]).to eq('abc123')
        expect(notification[:read]).to be false
        expect(notification[:id]).to be_a(String)
        expect(notification[:created_at]).to be_a(String)
      end

      it 'sets TTL on notification key' do
        operation.call

        ttl = Familia.dbclient.ttl("notifications:#{custid}")
        expect(ttl).to be > 0
        expect(ttl).to be <= described_class::NOTIFICATION_TTL
      end

      it 'limits stored notifications to MAX_NOTIFICATIONS' do
        # Pre-populate with MAX_NOTIFICATIONS
        described_class::MAX_NOTIFICATIONS.times do |i|
          Familia.dbclient.lpush("notifications:#{custid}", { id: "old-#{i}" }.to_json)
        end

        operation.call

        count = Familia.dbclient.llen("notifications:#{custid}")
        expect(count).to eq(described_class::MAX_NOTIFICATIONS)
      end

      it 'skips when custid is missing' do
        data_without_custid = base_data.merge(
          addressee: { email: 'user@example.com' },
          channels: ['via_bell']
        )
        operation = described_class.new(data: data_without_custid)

        results = operation.call

        expect(results[:via_bell]).to eq(:skipped)
      end
    end

    context 'email notification delivery' do
      let(:publisher_instance) { instance_double(Onetime::Jobs::Publisher) }
      let(:data) { base_data.merge(channels: ['via_email']) }
      let(:operation) { described_class.new(data: data) }

      before do
        allow(Onetime::Jobs::Publisher).to receive(:new).and_return(publisher_instance)
        allow(publisher_instance).to receive(:publish).and_return('queued-msg-id')
      end

      it 'queues email via Publisher with correct payload' do
        results = operation.call

        expect(results[:via_email]).to eq(:success)
        expect(publisher_instance).to have_received(:publish).with(
          'email.message.send',
          hash_including(
            template: 'secret_viewed',
            data: hash_including(
              locale: 'en',
              to: 'user@example.com',
              secret_key: 'abc123'
            )
          )
        )
      end

      it 'uses provided locale in email payload' do
        data_with_locale = base_data.merge(channels: ['via_email'], locale: 'fr')
        operation = described_class.new(data: data_with_locale)

        operation.call

        expect(publisher_instance).to have_received(:publish).with(
          'email.message.send',
          hash_including(
            data: hash_including(locale: 'fr')
          )
        )
      end

      it 'skips when email is missing' do
        data_without_email = base_data.merge(
          addressee: { custid: custid },
          channels: ['via_email']
        )
        operation = described_class.new(data: data_without_email)

        results = operation.call

        expect(results[:via_email]).to eq(:skipped)
        expect(publisher_instance).not_to have_received(:publish)
      end
    end

    context 'webhook notification delivery' do
      let(:http_instance) { instance_double(Net::HTTP) }
      let(:response) { instance_double(Net::HTTPSuccess, code: '200', body: 'OK') }
      let(:data) { base_data.merge(channels: ['via_webhook']) }
      let(:operation) { described_class.new(data: data) }

      before do
        stub_public_ip_resolution
        allow(Net::HTTP).to receive(:new).and_return(http_instance)
        allow(http_instance).to receive(:use_ssl=)
        allow(http_instance).to receive(:use_ssl?).and_return(true)
        allow(http_instance).to receive(:verify_mode=)
        allow(http_instance).to receive(:verify_hostname=)
        allow(http_instance).to receive(:open_timeout=)
        allow(http_instance).to receive(:read_timeout=)
        allow(http_instance).to receive(:request).and_return(response)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it 'makes HTTP POST to webhook URL with correct payload' do
        results = operation.call

        expect(results[:via_webhook]).to eq(:success)
        expect(http_instance).to have_received(:request) do |request|
          expect(request).to be_a(Net::HTTP::Post)
          expect(request['Content-Type']).to eq('application/json')
          expect(request['User-Agent']).to eq(Onetime::VERSION.user_agent)

          body = JSON.parse(request.body, symbolize_names: true)
          expect(body[:event]).to eq('secret.viewed')
          expect(body[:template]).to eq('secret_viewed')
          expect(body[:data][:secret_key]).to eq('abc123')
          expect(body[:timestamp]).to be_a(String)
        end
      end

      it 'uses SSL for https URLs' do
        operation.call

        expect(http_instance).to have_received(:use_ssl=).with(true)
      end

      it 'sets appropriate timeouts' do
        operation.call

        expect(http_instance).to have_received(:open_timeout=).with(described_class::WEBHOOK_OPEN_TIMEOUT)
        expect(http_instance).to have_received(:read_timeout=).with(described_class::WEBHOOK_READ_TIMEOUT)
      end

      it 'returns error when webhook returns non-success status' do
        error_response = instance_double(Net::HTTPBadRequest, code: '400', body: 'Bad Request')
        allow(http_instance).to receive(:request).and_return(error_response)
        allow(error_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)

        results = operation.call

        expect(results[:via_webhook]).to eq(:error)
      end

      it 'skips when webhook_url is missing' do
        data_without_webhook = base_data.merge(
          addressee: { custid: custid, email: 'user@example.com' },
          channels: ['via_webhook']
        )
        operation = described_class.new(data: data_without_webhook)

        results = operation.call

        expect(results[:via_webhook]).to eq(:skipped)
      end
    end

    context 'multi-channel delivery' do
      let(:publisher_instance) { instance_double(Onetime::Jobs::Publisher) }
      let(:http_instance) { instance_double(Net::HTTP) }
      let(:response) { instance_double(Net::HTTPSuccess, code: '200', body: 'OK') }
      let(:data) { base_data.merge(channels: %w[via_bell via_email via_webhook]) }
      let(:operation) { described_class.new(data: data) }

      before do
        stub_public_ip_resolution
        allow(Onetime::Jobs::Publisher).to receive(:new).and_return(publisher_instance)
        allow(publisher_instance).to receive(:publish).and_return('msg-id')

        allow(Net::HTTP).to receive(:new).and_return(http_instance)
        allow(http_instance).to receive(:use_ssl=)
        allow(http_instance).to receive(:use_ssl?).and_return(true)
        allow(http_instance).to receive(:verify_mode=)
        allow(http_instance).to receive(:verify_hostname=)
        allow(http_instance).to receive(:open_timeout=)
        allow(http_instance).to receive(:read_timeout=)
        allow(http_instance).to receive(:request).and_return(response)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it 'delivers to all three channels' do
        results = operation.call

        expect(results[:via_bell]).to eq(:success)
        expect(results[:via_email]).to eq(:success)
        expect(results[:via_webhook]).to eq(:success)

        # Verify Redis storage
        notifications = Familia.dbclient.lrange("notifications:#{custid}", 0, -1)
        expect(notifications.length).to eq(1)

        # Verify Publisher was called
        expect(publisher_instance).to have_received(:publish)

        # Verify HTTP was called
        expect(http_instance).to have_received(:request)
      end

      it 'continues with other channels when one fails' do
        # Make webhook fail
        allow(http_instance).to receive(:request).and_raise(StandardError, 'Connection refused')

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
        expect(results[:via_email]).to eq(:success)
        expect(results[:via_webhook]).to eq(:error)
      end
    end

    context 'channel resolution' do
      it 'defaults to bell when no channels specified' do
        data_without_channels = base_data.reject { |k, _| k == :channels }
        operation = described_class.new(data: data_without_channels)

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
        expect(results.keys).to eq([:via_bell])
      end

      it 'filters out invalid channels' do
        data_with_invalid = base_data.merge(channels: %w[bell sms carrier_pigeon])
        operation = described_class.new(data: data_with_invalid)

        results = operation.call

        expect(results.keys).to eq([:via_bell])
      end

      it 'defaults to bell when all channels are invalid' do
        data_all_invalid = base_data.merge(channels: %w[sms carrier_pigeon])
        operation = described_class.new(data: data_all_invalid)

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
      end
    end

    context 'with empty addressee' do
      let(:data) { base_data.merge(addressee: {}, channels: %w[via_bell via_email via_webhook]) }
      let(:operation) { described_class.new(data: data) }

      it 'skips all channels gracefully' do
        results = operation.call

        expect(results[:via_bell]).to eq(:skipped)
        expect(results[:via_email]).to eq(:skipped)
        expect(results[:via_webhook]).to eq(:skipped)
      end
    end
  end

  describe '#results' do
    it 'returns empty hash before call' do
      operation = described_class.new(data: base_data)

      expect(operation.results).to eq({})
    end

    it 'returns results after call' do
      operation = described_class.new(data: base_data.merge(channels: ['via_bell']))
      operation.call

      expect(operation.results).to eq({ via_bell: :success })
    end
  end

  # === Additional Edge Case Coverage ===

  describe 'edge cases for data structure' do
    context 'with nil data fields' do
      it 'handles nil data hash gracefully' do
        data_with_nil = base_data.merge(data: nil, channels: ['via_bell'])
        operation = described_class.new(data: data_with_nil)

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
        notification = JSON.parse(Familia.dbclient.lrange("notifications:#{custid}", 0, 0).first, symbolize_names: true)
        expect(notification[:data]).to eq({})
      end

      it 'handles nil addressee gracefully' do
        data_nil_addressee = base_data.merge(addressee: nil, channels: ['via_bell'])
        operation = described_class.new(data: data_nil_addressee)

        results = operation.call

        expect(results[:via_bell]).to eq(:skipped)
      end
    end

    context 'with empty channels array' do
      it 'defaults to bell when channels is empty array' do
        data_empty_channels = base_data.merge(channels: [])
        operation = described_class.new(data: data_empty_channels)

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
      end
    end

    context 'channel type coercion' do
      let(:publisher_instance) { instance_double(Onetime::Jobs::Publisher) }

      before do
        allow(Onetime::Jobs::Publisher).to receive(:new).and_return(publisher_instance)
        allow(publisher_instance).to receive(:publish).and_return('queued-msg-id')
      end

      it 'handles symbol channels' do
        data_symbol_channels = base_data.merge(channels: [:via_bell, :via_email])
        operation = described_class.new(data: data_symbol_channels)

        results = operation.call

        expect(results[:via_bell]).to eq(:success)
        expect(results[:via_email]).to eq(:success)
      end
    end
  end

  describe 'webhook network errors' do
    let(:http_instance) { instance_double(Net::HTTP) }
    let(:data) { base_data.merge(channels: ['via_webhook']) }

    before do
      stub_public_ip_resolution
      allow(Net::HTTP).to receive(:new).and_return(http_instance)
      allow(http_instance).to receive(:use_ssl=)
      allow(http_instance).to receive(:use_ssl?).and_return(true)
      allow(http_instance).to receive(:verify_mode=)
      allow(http_instance).to receive(:verify_hostname=)
      allow(http_instance).to receive(:open_timeout=)
      allow(http_instance).to receive(:read_timeout=)
    end

    it 'handles connection timeout' do
      allow(http_instance).to receive(:request).and_raise(Net::OpenTimeout, 'execution expired')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'handles read timeout' do
      allow(http_instance).to receive(:request).and_raise(Net::ReadTimeout, 'Net::ReadTimeout')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'handles DNS resolution failure' do
      allow(Net::HTTP).to receive(:new).and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'handles SSL certificate error' do
      allow(http_instance).to receive(:request).and_raise(OpenSSL::SSL::SSLError, 'certificate verify failed')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end
  end

  describe 'HTTP vs HTTPS webhook URLs' do
    let(:http_instance) { instance_double(Net::HTTP) }
    let(:response) { instance_double(Net::HTTPSuccess, code: '200', body: 'OK') }

    before do
      stub_public_ip_resolution
      allow(Net::HTTP).to receive(:new).and_return(http_instance)
      allow(http_instance).to receive(:use_ssl=)
      allow(http_instance).to receive(:verify_mode=)
      allow(http_instance).to receive(:verify_hostname=)
      allow(http_instance).to receive(:open_timeout=)
      allow(http_instance).to receive(:read_timeout=)
      allow(http_instance).to receive(:request).and_return(response)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    end

    context 'with HTTP webhook URL' do
      let(:data) do
        base_data.merge(
          addressee: base_data[:addressee].merge(webhook_url: 'http://example.com/webhook'),
          channels: ['via_webhook']
        )
      end

      before do
        allow(http_instance).to receive(:use_ssl?).and_return(false)
      end

      it 'disables SSL for http URLs' do
        described_class.new(data: data).call

        expect(http_instance).to have_received(:use_ssl=).with(false)
      end
    end

    context 'with HTTPS webhook URL' do
      let(:data) do
        base_data.merge(
          addressee: base_data[:addressee].merge(webhook_url: 'https://secure.example.com/webhook'),
          channels: ['via_webhook']
        )
      end

      before do
        allow(http_instance).to receive(:use_ssl?).and_return(true)
      end

      it 'enables SSL for https URLs' do
        described_class.new(data: data).call

        expect(http_instance).to have_received(:use_ssl=).with(true)
      end

      it 'sets strict TLS verification' do
        described_class.new(data: data).call

        expect(http_instance).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
        expect(http_instance).to have_received(:verify_hostname=).with(true)
      end
    end
  end

  describe 'SSRF protection' do
    let(:http_instance) { instance_double(Net::HTTP) }
    let(:data) { base_data.merge(channels: ['via_webhook']) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(http_instance)
      allow(http_instance).to receive(:use_ssl=)
      allow(http_instance).to receive(:use_ssl?).and_return(true)
      allow(http_instance).to receive(:verify_mode=)
      allow(http_instance).to receive(:verify_hostname=)
      allow(http_instance).to receive(:open_timeout=)
      allow(http_instance).to receive(:read_timeout=)
    end

    # Helper to stub Addrinfo for specific IP while allowing Redis to work
    def stub_webhook_ip(ip_address)
      addr = instance_double(Addrinfo)
      allow(addr).to receive(:ip_address).and_return(ip_address)
      allow(Addrinfo).to receive(:getaddrinfo).and_call_original
      allow(Addrinfo).to receive(:getaddrinfo)
        .with(satisfy { |h| Onetime::Utils::DomainParser.hostname_within_domain?(h, 'example.com') }, anything, anything, anything)
        .and_return([addr])
    end

    it 'blocks loopback addresses' do
      stub_webhook_ip('127.0.0.1')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'blocks private network addresses' do
      stub_webhook_ip('192.168.1.1')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'blocks link-local addresses' do
      stub_webhook_ip('169.254.169.254') # AWS metadata

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end

    it 'allows public IP addresses' do
      response = instance_double(Net::HTTPSuccess, code: '200', body: 'OK')
      allow(http_instance).to receive(:request).and_return(response)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      stub_webhook_ip('93.184.216.34')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:success)
    end

    it 'handles DNS resolution failure' do
      allow(Addrinfo).to receive(:getaddrinfo).and_call_original
      allow(Addrinfo).to receive(:getaddrinfo)
        .with(satisfy { |h| Onetime::Utils::DomainParser.hostname_within_domain?(h, 'example.com') }, anything, anything, anything)
        .and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')

      results = described_class.new(data: data).call

      expect(results[:via_webhook]).to eq(:error)
    end
  end

  describe 'Publisher exception handling' do
    let(:publisher_instance) { instance_double(Onetime::Jobs::Publisher) }
    let(:data) { base_data.merge(channels: ['via_email']) }

    before do
      allow(Onetime::Jobs::Publisher).to receive(:new).and_return(publisher_instance)
      allow(publisher_instance).to receive(:publish).and_raise(StandardError, 'RabbitMQ unavailable')
    end

    it 'returns error status when Publisher raises exception' do
      results = described_class.new(data: data).call

      expect(results[:via_email]).to eq(:error)
    end
  end

  describe 'context parameter' do
    it 'accepts context without affecting delivery' do
      context = { source_message_id: 'msg-123', correlation_id: 'corr-456' }
      operation = described_class.new(data: base_data.merge(channels: ['via_bell']), context: context)

      results = operation.call

      expect(results[:via_bell]).to eq(:success)
    end
  end

  describe 'notification metadata format' do
    it 'generates valid UUID for notification id' do
      operation = described_class.new(data: base_data.merge(channels: ['via_bell']))
      operation.call

      notification = JSON.parse(Familia.dbclient.lrange("notifications:#{custid}", 0, 0).first, symbolize_names: true)

      expect(notification[:id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'generates ISO8601 timestamp for created_at' do
      operation = described_class.new(data: base_data.merge(channels: ['via_bell']))
      operation.call

      notification = JSON.parse(Familia.dbclient.lrange("notifications:#{custid}", 0, 0).first, symbolize_names: true)

      expect { Time.iso8601(notification[:created_at]) }.not_to raise_error
    end
  end
end
