# tests/unit/ruby/rspec/onetime/app/mail/mail_module_spec.rb

require_relative '../../../spec_helper'
require 'onetime/app/mail'

RSpec.describe Onetime::App::Mail do
  before do
    # Reset the mailer before each test
    described_class.reset_mailer

    # Mock the OT configuration
    allow(OT).to receive(:conf).and_return({
      emailer: {
        from: 'test@example.com',
        fromname: 'Test Sender'
      }
    })

    # Mock the mailer setup methods
    allow(Onetime::App::Mail::SMTPMailer).to receive(:setup)
    allow(Onetime::App::Mail::SendGridMailer).to receive(:setup)
    allow(Onetime::App::Mail::AmazonSESMailer).to receive(:setup)

    # Mock the mailer initialization
    allow(Onetime::App::Mail::SMTPMailer).to receive(:new).and_return(double('smtp_mailer'))
    allow(Onetime::App::Mail::SendGridMailer).to receive(:new).and_return(double('sendgrid_mailer'))
    allow(Onetime::App::Mail::AmazonSESMailer).to receive(:new).and_return(double('amazon_ses_mailer'))
  end

  describe '.mailer' do
    context 'with default configuration' do
      it 'returns an SMTP mailer' do
        expect(Onetime::App::Mail::SMTPMailer).to receive(:setup)
        expect(Onetime::App::Mail::SMTPMailer).to receive(:new).with('test@example.com', 'Test Sender')

        mailer = described_class.mailer
        expect(mailer).to be_a_kind_of(RSpec::Mocks::Double)
      end
    end

    context 'with SendGrid configuration' do
      before do
        allow(OT).to receive(:conf).and_return({
          emailer: {
            provider: 'sendgrid',
            from: 'test@example.com',
            fromname: 'Test Sender'
          }
        })
      end

      it 'returns a SendGrid mailer' do
        expect(Onetime::App::Mail::SendGridMailer).to receive(:setup)
        expect(Onetime::App::Mail::SendGridMailer).to receive(:new).with('test@example.com', 'Test Sender')

        mailer = described_class.mailer
        expect(mailer).to be_a_kind_of(RSpec::Mocks::Double)
      end
    end

    context 'with Amazon SES configuration' do
      before do
        allow(OT).to receive(:conf).and_return({
          emailer: {
            provider: 'amazon_ses',
            from: 'test@example.com',
            fromname: 'Test Sender'
          }
        })
      end

      it 'returns an Amazon SES mailer' do
        expect(Onetime::App::Mail::AmazonSESMailer).to receive(:setup)
        expect(Onetime::App::Mail::AmazonSESMailer).to receive(:new).with('test@example.com', 'Test Sender')

        mailer = described_class.mailer
        expect(mailer).to be_a_kind_of(RSpec::Mocks::Double)
      end
    end

    context 'with case-insensitive provider configuration' do
      before do
        allow(OT).to receive(:conf).and_return({
          emailer: {
            provider: 'AMAZON_SES',
            from: 'test@example.com',
            fromname: 'Test Sender'
          }
        })
      end

      it 'handles case-insensitive provider names' do
        expect(Onetime::App::Mail::AmazonSESMailer).to receive(:setup)
        expect(Onetime::App::Mail::AmazonSESMailer).to receive(:new).with('test@example.com', 'Test Sender')

        mailer = described_class.mailer
        expect(mailer).to be_a_kind_of(RSpec::Mocks::Double)
      end
    end

    context 'with unknown provider configuration' do
      before do
        allow(OT).to receive(:conf).and_return({
          emailer: {
            provider: 'unknown_provider',
            from: 'test@example.com',
            fromname: 'Test Sender'
          }
        })
      end

      it 'defaults to SMTP mailer for unknown providers' do
        expect(Onetime::App::Mail::SMTPMailer).to receive(:setup)
        expect(Onetime::App::Mail::SMTPMailer).to receive(:new).with('test@example.com', 'Test Sender')

        mailer = described_class.mailer
        expect(mailer).to be_a_kind_of(RSpec::Mocks::Double)
      end
    end
  end

  describe.skip '.reset_mailer' do
    it 'clears the cached mailer instance' do
      # First call to cache the mailer
      first_mailer = described_class.mailer

      # Reset the mailer
      described_class.reset_mailer

      # Should create a new mailer
      expect(Onetime::App::Mail::SMTPMailer).to receive(:setup)
      expect(Onetime::App::Mail::SMTPMailer).to receive(:new).with('test@example.com', 'Test Sender')

      second_mailer = described_class.mailer
      expect(second_mailer).not_to be(first_mailer)
    end
  end
end
