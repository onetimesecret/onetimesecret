# spec/unit/onetime/mail/delivery/lettermint_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'lettermint'
require 'onetime/mail'
require 'onetime/mail/delivery/lettermint'

RSpec.describe Onetime::Mail::Delivery::Lettermint do
  let(:config) { { api_token: 'lm_test-token-example' } }
  let(:backend) { described_class.new(config) }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello',
    }
  end

  let(:mock_response) { ::Lettermint::SendEmailResponse.new(message_id: 'msg_123', status: 'queued') }
  let(:mock_message) { instance_double('Lettermint::EmailMessage') }
  let(:mock_client) { instance_double('Lettermint::Client') }

  before do
    allow(mock_client).to receive(:email).and_return(mock_message)
    allow(mock_message).to receive_messages(from: mock_message, to: mock_message,
                                            subject: mock_message, text: mock_message,
                                            html: mock_message, reply_to: mock_message)
    allow(mock_message).to receive(:deliver).and_return(mock_response)
    allow(backend).to receive(:client).and_return(mock_client)
    allow(backend).to receive(:log_delivery)
    allow(backend).to receive(:log_error)
  end

  after do
    ::Lettermint.reset_configuration!
  end

  describe '#deliver success' do
    it 'delivers and logs on success' do
      result = backend.deliver(email)
      expect(result.message_id).to eq('msg_123')
      expect(result.status).to eq('queued')
      expect(backend).to have_received(:log_delivery)
    end

    it 'sets reply_to when present' do
      email_with_reply = email.merge(reply_to: 'reply@example.com')
      backend.deliver(email_with_reply)
      expect(mock_message).to have_received(:reply_to).with('reply@example.com')
    end

    it 'skips reply_to when absent' do
      backend.deliver(email)
      expect(mock_message).not_to have_received(:reply_to)
    end
  end

  describe '#deliver error classification' do
    context 'when SDK raises TimeoutError' do
      it 'raises transient DeliveryError' do
        allow(mock_message).to receive(:deliver)
          .and_raise(::Lettermint::TimeoutError, 'request timed out')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
            expect(err.original_error).to be_a(::Lettermint::TimeoutError)
          end
      end
    end

    context 'when SDK raises ValidationError (422)' do
      it 'raises fatal DeliveryError' do
        allow(mock_message).to receive(:deliver)
          .and_raise(::Lettermint::ValidationError.new(
                       message: 'invalid recipient',
                       error_type: 'validation_error',
                     ))

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
            expect(err.original_error).to be_a(::Lettermint::ValidationError)
          end
      end
    end

    context 'when SDK raises ClientError (400)' do
      it 'raises fatal DeliveryError' do
        allow(mock_message).to receive(:deliver)
          .and_raise(::Lettermint::ClientError.new(message: 'bad request'))

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
            expect(err.original_error).to be_a(::Lettermint::ClientError)
          end
      end
    end

    context 'when SDK raises HttpRequestError with 5xx' do
      [500, 502, 503].each do |code|
        it "raises transient DeliveryError for #{code}" do
          allow(mock_message).to receive(:deliver)
            .and_raise(::Lettermint::HttpRequestError.new(
                         message: 'server error',
                         status_code: code,
                       ))

          expect { backend.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be true
            end
        end
      end
    end

    context 'when SDK raises AuthenticationError (401/403)' do
      it 'raises fatal DeliveryError' do
        allow(mock_message).to receive(:deliver)
          .and_raise(::Lettermint::AuthenticationError.new(
                       message: 'invalid api token',
                       status_code: 401,
                     ))

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
            expect(err.original_error).to be_a(::Lettermint::AuthenticationError)
          end
      end
    end

    context 'when SDK raises RateLimitError (429)' do
      it 'raises transient DeliveryError' do
        allow(mock_message).to receive(:deliver)
          .and_raise(::Lettermint::RateLimitError.new(
                       message: 'too many requests',
                       retry_after: 30,
                     ))

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
            expect(err.original_error).to be_a(::Lettermint::RateLimitError)
          end
      end
    end

    context 'when SDK raises HttpRequestError with 4xx (generic)' do
      [400, 404].each do |code|
        it "raises fatal DeliveryError for #{code}" do
          allow(mock_message).to receive(:deliver)
            .and_raise(::Lettermint::HttpRequestError.new(
                         message: 'client error',
                         status_code: code,
                       ))

          expect { backend.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be false
            end
        end
      end
    end

    context 'network errors (inherited from Base)' do
      it 'classifies Errno::ECONNREFUSED as transient' do
        allow(mock_message).to receive(:deliver)
          .and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies Net::OpenTimeout as transient' do
        allow(mock_message).to receive(:deliver)
          .and_raise(Net::OpenTimeout, 'timed out')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end
    end

    context 'unknown errors' do
      it 'classifies generic StandardError as non-transient' do
        allow(mock_message).to receive(:deliver)
          .and_raise(StandardError, 'unexpected')

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
          end
      end
    end

    context 'DeliveryError pass-through' do
      it 'does not double-wrap DeliveryError' do
        original = Onetime::Mail::DeliveryError.new(
          'already wrapped',
          original_error: RuntimeError.new('inner'),
          transient: true,
        )
        allow(mock_message).to receive(:deliver).and_raise(original)

        expect { backend.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err).to equal(original)
          end
      end
    end
  end

  describe '#validate_config!' do
    it 'raises ArgumentError when api_token is missing' do
      expect { described_class.new({}) }
        .to raise_error(ArgumentError, /Lettermint API token must be configured/)
    end

    it 'raises ArgumentError when api_token is empty' do
      expect { described_class.new(api_token: '') }
        .to raise_error(ArgumentError, /Lettermint API token must be configured/)
    end

    it 'accepts token from ENV' do
      allow(ENV).to receive(:fetch).with('LETTERMINT_API_TOKEN', nil).and_return('lm_env-token')
      expect { described_class.new({}) }.not_to raise_error
    end
  end

  describe '#provider_name' do
    it 'returns Lettermint' do
      expect(backend.provider_name).to eq('Lettermint')
    end
  end

  describe 'Lettermint.configure integration' do
    it 'sets global base_url from config' do
      described_class.new(api_token: 'lm_test-token', base_url: 'https://custom.api.com/v1')
      expect(::Lettermint.configuration.base_url).to eq('https://custom.api.com/v1')
    end

    it 'sets global timeout from config' do
      described_class.new(api_token: 'lm_test-token', timeout: 45)
      expect(::Lettermint.configuration.timeout).to eq(45)
    end

    it 'does not override base_url when not provided' do
      ::Lettermint.configure { |c| c.base_url = 'https://existing.api.com' }
      described_class.new(api_token: 'lm_test-token')
      expect(::Lettermint.configuration.base_url).to eq('https://existing.api.com')
    end
  end
end
