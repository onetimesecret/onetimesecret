# spec/unit/onetime/mail/delivery/smtp_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/delivery/smtp'

RSpec.describe Onetime::Mail::Delivery::SMTP do
  let(:config) { { host: 'localhost', port: 2525 } }
  let(:smtp) { described_class.new(config) }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello, world',
    }
  end

  # Stub out the actual SMTP delivery so we can test error handling
  # without needing a real SMTP server
  before do
    allow(smtp).to receive(:deliver_with_settings).and_return(true)
    allow(smtp).to receive(:log_delivery)
    allow(smtp).to receive(:log_error)
  end

  describe '#deliver error classification' do
    context 'when a transient error occurs' do
      described_class::TRANSIENT_ERRORS.each do |error_class|
        it "wraps #{error_class} as a transient DeliveryError" do
          allow(smtp).to receive(:deliver_with_settings)
            .and_raise(error_class, 'connection failed')

          expect { smtp.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be true
              expect(err.original_error).to be_a(error_class)
              expect(err.message).to include('SMTP delivery error')
            end
        end
      end

      it 'produces DeliveryError with transient?=true for Errno::ECONNREFUSED' do
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end
    end

    context 'when a fatal error occurs' do
      # Net::SMTPAuthenticationError is handled specially in perform_delivery:
      # it triggers handle_auth_failure (retry without auth) before reaching
      # Base's error handler. Test it separately below.
      fatal_errors_without_auth = described_class::FATAL_ERRORS - [Net::SMTPAuthenticationError]

      fatal_errors_without_auth.each do |error_class|
        it "wraps #{error_class} as a non-transient DeliveryError" do
          allow(smtp).to receive(:deliver_with_settings)
            .and_raise(error_class, '550 mailbox not found')

          expect { smtp.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be false
              expect(err.original_error).to be_a(error_class)
              expect(err.message).to include('SMTP delivery error')
            end
        end
      end

      it 'produces DeliveryError with transient?=false for Net::SMTPFatalError' do
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(Net::SMTPFatalError, '550 permanent rejection')

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
          end
      end

      it 'retries without auth on Net::SMTPAuthenticationError then wraps fallback failure' do
        # deliver_with_settings raises auth error (triggers handle_auth_failure),
        # which calls mail.deliver! directly. Stub at the Mail::Message level
        # to simulate the fallback also failing.
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(Net::SMTPAuthenticationError, '535 bad credentials')
        allow(smtp).to receive(:handle_auth_failure)
          .and_raise(Net::SMTPFatalError, '550 rejected on retry')

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
            expect(err.original_error).to be_a(Net::SMTPFatalError)
          end
      end
    end

    context 'when a generic StandardError occurs' do
      it 'wraps as a non-transient DeliveryError' do
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(StandardError, 'unexpected error')

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
            expect(err.original_error).to be_a(StandardError)
            expect(err.message).to include('SMTP delivery error')
          end
      end
    end

    context 'when a DeliveryError is already raised' do
      it 'passes through without double-wrapping' do
        original = Onetime::Mail::DeliveryError.new(
          'already wrapped',
          original_error: RuntimeError.new('inner'),
          transient: true
        )

        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(original)

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err).to equal(original)
            expect(err.transient?).to be true
            expect(err.message).to eq('already wrapped')
          end
      end
    end

    context 'original_error preservation' do
      it 'preserves the original error on transient DeliveryError' do
        original_error = Errno::ETIMEDOUT.new('timed out')
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(original_error)

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.original_error).to be_a(Errno::ETIMEDOUT)
            expect(err.original_error.message).to include('timed out')
          end
      end

      it 'preserves the original error on fatal DeliveryError' do
        original_error = Net::SMTPFatalError.new('550 mailbox not found')
        allow(smtp).to receive(:deliver_with_settings)
          .and_raise(original_error)

        expect { smtp.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.original_error).to be_a(Net::SMTPFatalError)
            expect(err.original_error.message).to include('550 mailbox not found')
          end
      end
    end
  end

  describe 'TRANSIENT_ERRORS' do
    it 'is a frozen array' do
      expect(described_class::TRANSIENT_ERRORS).to be_frozen
    end

    it 'includes network-related error classes' do
      expect(described_class::TRANSIENT_ERRORS).to include(
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        SocketError
      )
    end
  end

  describe 'FATAL_ERRORS' do
    it 'is a frozen array' do
      expect(described_class::FATAL_ERRORS).to be_frozen
    end

    it 'includes SMTP protocol error classes' do
      expect(described_class::FATAL_ERRORS).to include(
        Net::SMTPAuthenticationError,
        Net::SMTPFatalError,
        Net::SMTPSyntaxError
      )
    end
  end
end
