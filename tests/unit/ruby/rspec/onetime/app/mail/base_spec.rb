# tests/unit/ruby/rspec/onetime/app/mail/base_spec.rb

require_relative '../../../spec_helper'

RSpec.describe Onetime::App::Mail::Welcome do
  let(:config) do
    {
      emailer: {
        mode: :smtp,
        from: 'sender@example.com',
        fromname: 'Test Sender',
        host: 'smtp.example.com',
        port: 587,
        user: 'testuser',
        tls: true,
        auth: true
      },
      site: {
        host: 'example.com',
        ssl: true
      }
    }
  end

  let(:locales) do
    {
      'en' => {
        email: {
          base: {
            subject: 'Test Email',
            body: 'Test email body'
          }
        },
        web: {
          COMMON: {
            description: 'Test Description',
            keywords: 'test,keywords'
          }
        }
      }
    }
  end

  let(:customer) do
    instance_double('Customer',
      identifier: 'test@example.com',
      email: 'test@example.com',
      custid: 'test@example.com'
    )
  end

  let(:secret) do
    instance_double('Secret',
      identifier: 'secret123',
      key: 'testkey123',
      share_domain: nil
    )
  end

  let(:emailer) do
    instance_double('SMTPMailer',
      send_email: { status: 'sent' }
    )
  end

  subject(:mail_base) do
    described_class.new(customer, 'en').tap do |base|
      base.instance_variable_set(:@emailer, emailer)
      base[:email_address] = 'recipient@example.com'
      base[:secret] = secret
      base[:cust] = customer
    end
  end

  before do
    allow(OT).to receive(:conf).and_return(config)
    allow(OT).to receive(:locales).and_return(locales)
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(Onetime::EmailReceipt).to receive(:create)
  end

  describe '#initialize' do
    it 'sets up mailer with correct config' do
      expect(mail_base.mode).to eq(:smtp)
      expect(mail_base.locale).to eq('en')
    end
  end

  describe '#i18n' do
    it 'loads correct locale data' do
      i18n_data = mail_base.i18n
      expect(i18n_data[:locale]).to eq('en')
      expect(i18n_data[:COMMON]).to include(
        description: 'Test Description',
        keywords: 'test,keywords'
      )
    end
  end

  describe '#deliver_email' do
    it 'sends email and creates receipt for successful delivery' do
      response = mail_base.deliver_email

      expect(emailer).to have_received(:send_email)
        .with('recipient@example.com', anything, anything)
      expect(Onetime::EmailReceipt).to have_received(:create)
        .with('test@example.com', 'secret123', anything)
      expect(response).to eq({ status: 'sent' })
    end

    it 'skips email delivery when token is provided' do
      mail_base.deliver_email('skip_token')

      expect(emailer).not_to have_received(:send_email)
      expect(Onetime::EmailReceipt).not_to have_received(:create)
    end

    context 'with delivery failures' do
      it 'handles socket errors' do
        allow(emailer).to receive(:send_email).and_raise(SocketError.new('Connection failed'))

        expect {
          mail_base.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)

        expect(Onetime::EmailReceipt).to have_received(:create)
          .with('test@example.com', 'secret123', anything)
      end

      it 'handles general exceptions' do
        allow(emailer).to receive(:send_email).and_raise(StandardError.new('Unknown error'))

        expect {
          mail_base.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)

        expect(Onetime::EmailReceipt).to have_received(:create)
          .with('test@example.com', 'secret123', anything)
      end
    end
  end
end
