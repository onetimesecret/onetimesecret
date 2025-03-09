# tests/unit/ruby/rspec/onetime/app/mail/smtp_mailer_spec.rb

require_relative '../../../spec_helper'
require 'onetime/app/mail/smtp_mailer'

RSpec.describe Onetime::App::Mail::SMTPMailer do
  let(:from_email) { 'sender@example.com' }
  let(:from_name) { 'Test Sender' }
  let(:to_email) { 'recipient@example.com' }
  let(:subject) { 'Test Subject' }
  let(:content) { '<p>Test Content</p>' }

  let(:mailer) { described_class.new(from_email, from_name) }
  let(:mail_double) { instance_double(::Mail::Message) }
  let(:delivery_method) { double('delivery_method', response_code: '250 OK') }
  let(:mail_attrs) { {from: nil, reply_to: nil, to: nil, subject: nil, body: nil} }
  let(:mail_object) do
    mail = double('Mail::Message')

    # Define setter methods that capture values in the mail_attrs hash
    allow(mail).to receive(:from=) { |val| mail_attrs[:from] = [val] }
    allow(mail).to receive(:reply_to=) { |val| mail_attrs[:reply_to] = [val] }
    allow(mail).to receive(:to=) { |val| mail_attrs[:to] = [val] }
    allow(mail).to receive(:subject=) { |val| mail_attrs[:subject] = val }
    allow(mail).to receive(:body=) { |val| mail_attrs[:body] = val }

    # Define getter methods that return the captured values
    allow(mail).to receive(:from) { mail_attrs[:from] }
    allow(mail).to receive(:reply_to) { mail_attrs[:reply_to] }
    allow(mail).to receive(:to) { mail_attrs[:to] }
    allow(mail).to receive(:subject) { mail_attrs[:subject] }
    allow(mail).to receive(:body) { double('body', decoded: mail_attrs[:body]) }

    # Other mock setup remains the same
    allow(mail).to receive(:text_part).and_yield(mail)
    allow(mail).to receive(:html_part).and_yield(mail)
    allow(mail).to receive(:content_type=)
    allow(mail).to receive(:delivery_method).and_return(double('delivery_method', response_code: '250 OK'))
    allow(mail).to receive(:header).and_return(double('header', fields: []))

    mail
  end


  before do
    # Mock the Mail configuration
    allow(OT).to receive(:conf).and_return({
      emailer: {
        from: 'system@onetimesecret.com',
        host: 'smtp.example.com',
        port: 587,
        user: 'testuser',
        pass: 'testpass',
        auth: 'plain',
        tls: 'true'
      },
      site: {
        domain: 'onetimesecret.com'
      }
    })

    # Mock the obscure_email utility
    allow(OT::Utils).to receive(:obscure_email).with(to_email).and_return('r***@example.com')

    # Set up the mail_object with the necessary attributes/methods for testing
    allow(mail_object).to receive(:delivery_method).and_return(delivery_method)
    allow(mail_object).to receive(:text_part).and_yield(mail_object)
    allow(mail_object).to receive(:html_part).and_yield(mail_object)

    # Mock the Mail.deliver method
    allow(::Mail).to receive(:deliver) do |&block|
      # Run the block with the mail_object
      block.call(mail_object)
      # Return the mail_object for assertions
      mail_object
    end

    # Setup mail_double methods
    allow(mail_double).to receive(:from=)
    allow(mail_double).to receive(:reply_to=)
    allow(mail_double).to receive(:to=)
    allow(mail_double).to receive(:subject=)
    allow(mail_double).to receive(:text_part).and_yield(mail_double)
    allow(mail_double).to receive(:html_part).and_yield(mail_double)
    allow(mail_double).to receive(:content_type=)
    allow(mail_double).to receive(:body=)

    # Return values for inspection
    allow(mail_double).to receive(:from).and_return(['system@onetimesecret.com'])
    allow(mail_double).to receive(:to).and_return([to_email])
    allow(mail_double).to receive(:subject).and_return(subject)
    allow(mail_double).to receive(:body).and_return(double(decoded: content))
    allow(mail_double).to receive(:header).and_return(double(fields: []))
    allow(mail_double).to receive(:delivery_method).and_return(double(response_code: '250 OK'))
  end

  describe '#initialize' do
    it 'sets from and fromname attributes' do
      expect(mailer.from).to eq(from_email)
      expect(mailer.fromname).to eq(from_name)
    end
  end

  describe '#send_email' do
    it 'sends an email with the correct parameters' do
      # Execute the method
      response = mailer.send_email(to_email, subject, content)

      # Verify mail_object was properly configured
      expect(mail_object.from).to eq(['system@onetimesecret.com'])
      expect(mail_object.reply_to).to eq(["#{from_name} <#{from_email}>"])
      expect(mail_object.to).to eq([to_email])
      expect(mail_object.subject).to eq(subject)

      # Verify response
      expect(response).to eq(mail_object)
    end

    it 'logs the email sending process' do
      expect(OT).to receive(:info).with("> [send-start] r***@example.com")
      expect(OT).to receive(:info).with("> [send-success] Email sent successfully to r***@example.com")
      expect(OT).to receive(:ld).at_least(5).times

      mailer.send_email(to_email, subject, content)
    end

    context 'when from_email is nil or empty' do
      let(:from_email) { nil }

      it 'logs an error and returns nil' do
        expect(OT).to receive(:info).with("> [send-exception] No from address r***@example.com")
        expect(::Mail).not_to receive(:deliver)

        result = mailer.send_email(to_email, subject, content)
        expect(result).to be_nil
      end
    end

    context 'when SMTP error occurs' do
      before do
        allow(::Mail).to receive(:deliver).and_raise(Net::SMTPFatalError.new('550 Mailbox not found'))
      end

      it 'catches the error and logs it' do
        expect(OT).to receive(:info).with("> [send-exception-smtperror] r***@example.com")
        expect(OT).to receive(:ld).with(/Net::SMTPFatalError 550 Mailbox not found/)

        result = mailer.send_email(to_email, subject, content)
        expect(result).to be_nil
      end
    end

    context 'when other error occurs' do
      before do
        allow(::Mail).to receive(:deliver).and_raise(StandardError.new('Unknown error'))
      end

      it 'catches the error and logs it' do
        expect(OT).to receive(:info).with("> [send-exception-sending] r***@example.com StandardError Unknown error")
        expect(OT).to receive(:ld)

        result = mailer.send_email(to_email, subject, content)
        expect(result).to be_nil
      end
    end
  end

  describe '.setup' do
    it 'configures Mail defaults with correct SMTP settings' do
      smtp_settings = {
        address: 'smtp.example.com',
        port: 587,
        domain: 'onetimesecret.com',
        user_name: 'testuser',
        password: 'testpass',
        authentication: 'plain',
        enable_starttls_auto: true
      }

      # Expect Mail.defaults to be called with a block
      expect(::Mail).to receive(:defaults) do |&block|
        # Create a context where delivery_method can be called
        context = Object.new
        allow(context).to receive(:delivery_method)

        # Expect delivery_method to be called with the correct parameters
        expect(context).to receive(:delivery_method).with(:smtp, smtp_settings)

        # Execute the block in the context
        context.instance_eval(&block)
      end

      described_class.setup
    end
  end
end
