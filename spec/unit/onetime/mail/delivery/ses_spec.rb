# spec/unit/onetime/mail/delivery/ses_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/delivery/ses'

RSpec.describe Onetime::Mail::Delivery::SES do
  let(:config) do
    {
      access_key_id: 'AKIAIOSFODNN7EXAMPLE',
      secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
    }
  end
  let(:ses) { described_class.new(config) }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello',
    }
  end
  let(:mock_client) { instance_double('Aws::SESV2::Client') }

  before do
    allow(ses).to receive(:ses_client).and_return(mock_client)
    allow(mock_client).to receive(:send_email).and_return(double('response'))
    allow(ses).to receive(:log_delivery)
    allow(ses).to receive(:log_error)
  end

  describe '#deliver success' do
    it 'delivers via SES client and logs' do
      ses.deliver(email)
      expect(mock_client).to have_received(:send_email)
      expect(ses).to have_received(:log_delivery)
    end
  end

  describe '#deliver error classification' do
    # Helper to create AWS-style errors with .code and .http_status_code
    def aws_error(code, http_status, message = 'AWS error')
      error = StandardError.new(message)
      error.define_singleton_method(:code) { code }
      error.define_singleton_method(:http_status_code) { http_status }
      error
    end

    context 'transient AWS error codes' do
      described_class::TRANSIENT_ERROR_CODES.each do |code|
        it "classifies #{code} as transient" do
          error = aws_error(code, 429)
          allow(mock_client).to receive(:send_email).and_raise(error)

          expect { ses.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be true
              expect(err.original_error).to equal(error)
            end
        end
      end
    end

    context 'fatal AWS error codes' do
      described_class::FATAL_ERROR_CODES.each do |code|
        it "classifies #{code} as fatal" do
          error = aws_error(code, 400)
          allow(mock_client).to receive(:send_email).and_raise(error)

          expect { ses.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be false
            end
        end
      end
    end

    context 'HTTP status fallback' do
      it 'classifies 429 as transient' do
        error = aws_error('UnknownCode', 429)
        allow(mock_client).to receive(:send_email).and_raise(error)

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies 500+ as transient' do
        error = aws_error('UnknownCode', 503)
        allow(mock_client).to receive(:send_email).and_raise(error)

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies 400-499 (non-429) as fatal' do
        error = aws_error('UnknownCode', 403)
        allow(mock_client).to receive(:send_email).and_raise(error)

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
          end
      end
    end

    context 'network errors (inherited from Base)' do
      it 'classifies Errno::ECONNREFUSED as transient' do
        allow(mock_client).to receive(:send_email)
          .and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies SocketError as transient' do
        allow(mock_client).to receive(:send_email)
          .and_raise(SocketError, 'getaddrinfo failed')

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end
    end

    context 'unknown errors' do
      it 'classifies generic StandardError as non-transient' do
        allow(mock_client).to receive(:send_email)
          .and_raise(StandardError, 'something unexpected')

        expect { ses.deliver(email) }
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
        allow(mock_client).to receive(:send_email).and_raise(original)

        expect { ses.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err).to equal(original)
          end
      end
    end
  end

  describe 'TRANSIENT_ERROR_CODES' do
    it 'is a frozen array' do
      expect(described_class::TRANSIENT_ERROR_CODES).to be_frozen
    end
  end

  describe 'FATAL_ERROR_CODES' do
    it 'is a frozen array' do
      expect(described_class::FATAL_ERROR_CODES).to be_frozen
    end
  end
end
