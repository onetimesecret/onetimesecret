# spec/onetime/mail/views/welcome_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::Mail::Welcome do
  include_context "mail_test_context"
  it_behaves_like "mail delivery behavior"

  subject(:welcome_email) do
    with_emailer(
      described_class.new(mail_customer, 'en', mail_secret),
    )
  end

  let(:expected_content) do
    {
      secret: mail_secret,
      email_address: mail_customer.email,
      verify_uri: welcome_email.verify_uri
    }
  end

  # Tests that the welcome email template correctly renders Mustache variables
  # and includes the expected secret_link content in both HTML and plain text formats
  it_behaves_like "mustache template behavior", "secret_link"

  describe '#initialize' do
    it 'sets up email with correct attributes' do
      expect(welcome_email[:secret]).to eq(mail_secret)
      expect(welcome_email[:email_address]).to eq('test@example.com')
    end

    it 'handles different locales' do
      french_email = with_emailer(
        described_class.new(mail_customer, 'fr', mail_secret),
      )
      expect(french_email.subject).to eq('Bienvenue à OnetimeSecret')
    end

    it 'falls back to English for unsupported locale' do
      unsupported_email = with_emailer(
        described_class.new(mail_customer, 'humphreybogus', mail_secret),
      )
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
  end

  describe '#deliver_email' do
    it 'sends welcome email with correct parameters' do
      response = welcome_email.deliver_email

      expect(mail_emailer).to have_received(:send_email).with(
        'test@example.com',
        'Welcome to OnetimeSecret',
        satisfy { |content| content.is_a?(String) && !content.empty? },
        satisfy { |content| content.is_a?(String) && !content.empty? },
      )

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

      end
    end

    context 'with token-based delivery' do
      it 'skips email sending when token is present' do
        welcome_email.deliver_email('skip_token')

        expect(mail_emailer).not_to have_received(:send_email)
      end
    end
  end
end
