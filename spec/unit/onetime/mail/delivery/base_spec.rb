# spec/unit/onetime/mail/delivery/base_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/delivery/base'

RSpec.describe Onetime::Mail::Delivery::Base do
  # Anonymous subclass for testing the template method contract
  let(:test_class) do
    Class.new(described_class) do
      attr_accessor :delivery_result

      def perform_delivery(email)
        @delivery_result || { status: 'sent' }
      end

      def provider_name
        'TestBackend'
      end
    end
  end
  let(:backend) { test_class.new }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello',
    }
  end

  before do
    allow(backend).to receive(:log_delivery)
    allow(backend).to receive(:log_error)
  end

  describe '#deliver template method' do
    it 'normalizes email, calls perform_delivery, logs, and returns result' do
      result = backend.deliver(email)
      expect(result).to eq({ status: 'sent' })
      expect(backend).to have_received(:log_delivery)
    end

    it 'wraps StandardError as DeliveryError' do
      allow(backend).to receive(:perform_delivery)
        .and_raise(RuntimeError, 'kaboom')

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.message).to include('TestBackend delivery error')
          expect(err.message).to include('kaboom')
          expect(err.original_error).to be_a(RuntimeError)
        end
    end

    it 'passes through DeliveryError without double-wrapping' do
      original = Onetime::Mail::DeliveryError.new(
        'already wrapped',
        original_error: RuntimeError.new('inner'),
        transient: true,
      )
      allow(backend).to receive(:perform_delivery).and_raise(original)

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err).to equal(original)
          expect(err.transient?).to be true
        end
    end

    it 'delegates classification to classify_error' do
      allow(backend).to receive(:perform_delivery)
        .and_raise(Errno::ECONNREFUSED, 'refused')

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.transient?).to be true
        end
    end

    it 'treats :unknown classification as non-transient' do
      allow(backend).to receive(:perform_delivery)
        .and_raise(ArgumentError, 'bad arg')

      expect { backend.deliver(email) }
        .to raise_error(Onetime::Mail::DeliveryError) do |err|
          expect(err.transient?).to be false
        end
    end
  end

  describe '#classify_error' do
    described_class::NETWORK_ERRORS.each do |error_class|
      it "classifies #{error_class} as :transient" do
        error = error_class.new('network issue')
        expect(backend.classify_error(error)).to eq(:transient)
      end
    end

    it 'classifies unknown errors as :unknown' do
      expect(backend.classify_error(RuntimeError.new('wat'))).to eq(:unknown)
    end
  end

  describe '#perform_delivery' do
    it 'raises NotImplementedError on the base class directly' do
      base = described_class.new
      expect { base.perform_delivery({}) }
        .to raise_error(NotImplementedError, /must implement #perform_delivery/)
    end
  end

  describe '#normalize_email' do
    it 'handles nil optional fields (reply_to, html_body)' do
      minimal = { to: 'a@b.com', from: 'c@d.com', subject: 'Hi', text_body: 'body' }
      normalized = backend.send(:normalize_email, minimal)
      expect(normalized[:reply_to]).to be_nil
      expect(normalized[:html_body]).to be_nil
      expect(normalized[:to]).to eq('a@b.com')
    end

    it 'coerces all fields to strings when present' do
      full = {
        to: 'a@b.com', from: 'c@d.com', reply_to: 'e@f.com',
        subject: 'Hi', text_body: 'body', html_body: '<p>body</p>',
      }
      normalized = backend.send(:normalize_email, full)
      expect(normalized[:reply_to]).to eq('e@f.com')
      expect(normalized[:html_body]).to eq('<p>body</p>')
    end
  end

  describe 'NETWORK_ERRORS' do
    it 'is a frozen array' do
      expect(described_class::NETWORK_ERRORS).to be_frozen
    end

    it 'includes standard network error classes' do
      expect(described_class::NETWORK_ERRORS).to include(
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        Net::ReadTimeout,
        IOError,
        SocketError,
      )
    end
  end
end
