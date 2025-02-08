# tests/unit/ruby/rspec/onetime/app/mail/welcome_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::App::Mail::Welcome do
  include_context "mail_test_context"

  subject(:welcome_email) do
    described_class.new(mail_customer, 'en', mail_secret).tap do |mail|
      mail.instance_variable_set(:@emailer, mail_emailer)
    end
  end

  describe '#initialize' do
    it 'sets up email with correct attributes' do
      expect(welcome_email[:secret]).to eq(mail_secret)
      expect(welcome_email[:email_address]).to eq('test@example.com')
    end

    it 'handles different locales' do
      french_email = described_class.new(mail_customer, 'fr', mail_secret)
      expect(french_email.subject).to eq('Bienvenue à OnetimeSecret')
    end

    it 'falls back to English for unsupported locale' do
      unsupported_email = described_class.new(mail_customer, 'es', mail_secret)
      expect(unsupported_email.subject).to eq('Welcome to OnetimeSecret')
    end
  end

  describe '#subject' do
    it 'returns localized welcome subject' do
      expect(welcome_email.subject).to eq('Welcome to OnetimeSecret')
    end

    it 'does not include any sensitive information' do
      expect(welcome_email.subject).not_to include(mail_secret.identifier)
      expect(welcome_email.subject).not_to include(mail_secret.key)
    end
  end

  describe '#verify_uri' do
    it 'returns correct verification URI' do
      expect(welcome_email.verify_uri).to eq('/secret/testkey123')
    end

    context 'with custom share domain' do
      let(:custom_secret) do
        instance_double('Secret',
          identifier: 'secret123',
          key: 'testkey123',
          share_domain: 'custom.example.com')
      end

      it 'uses the custom domain for the verification URI' do
        custom_email = described_class.new(mail_customer, 'en', custom_secret)
        expect(custom_email.verify_uri).to eq('/secret/testkey123')
        expect(custom_email.secret_display_domain(custom_secret)).to eq('https://custom.example.com')
      end
    end
  end

  describe '#deliver_email' do
    it 'sends welcome email with correct parameters' do
      response = welcome_email.deliver_email

      expect(mail_emailer).to have_received(:send_email)
        .with(
          'test@example.com',
          'Welcome to OnetimeSecret',
          match(/<!DOCTYPE html.*#{mail_secret.key}.*<\/html>/m),
        )

      expect(Onetime::EmailReceipt).to have_received(:create)
        .with('test@example.com', 'secret123', anything)

      expect(response).to include(
        status: 'sent',
        message_id: 'test123',
      )
    end

    context 'with delivery failures' do
      it 'handles socket errors with proper logging' do
        allow(mail_emailer).to receive(:send_email)
          .and_raise(SocketError.new('Connection failed'))

        expect(OT).to receive(:le).with(/Cannot send mail/)

        expect {
          welcome_email.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)

        expect(Onetime::EmailReceipt).to have_received(:create)
          .with('test@example.com', 'secret123', include('Connection failed'))
      end

      it 'handles timeout errors' do
        allow(mail_emailer).to receive(:send_email)
          .and_raise(Timeout::Error.new('Connection timed out'))

        expect {
          welcome_email.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)
      end

      it 'handles general SMTP errors' do
        # Net::SMTPError is a module, use Net::SMTPFatalError instead
        allow(mail_emailer).to receive(:send_email)
          .and_raise(Net::SMTPFatalError.new('554 SMTP error'))

        expect {
          welcome_email.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)
      end
    end

    context 'with token-based delivery' do
      it 'skips email sending when token is present' do
        welcome_email.deliver_email('skip_token')

        expect(mail_emailer).not_to have_received(:send_email)
        expect(Onetime::EmailReceipt).not_to have_received(:create)
      end
    end
  end
end
