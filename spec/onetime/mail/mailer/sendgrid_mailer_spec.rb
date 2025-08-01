# spec/onetime/mail/mailer/sendgrid_mailer_spec.rb

require_relative '../../../spec_helper'
require 'onetime/mail/mailer/sendgrid_mailer'

RSpec.describe Onetime::Mail::Mailer::SendGridMailer do
  let(:from_email) { 'sender@example.com' }
  let(:from_name) { 'Test Sender' }
  let(:to_address) { 'recipient@example.com' }
  let(:subject) { 'Test Email Subject' }
  let(:html_content) { '<p>Test Content</p>' }
  let(:text_content) { 'Test Content' }

  let(:sendgrid_mailer) { described_class.new(from_email, from_name) }
  let(:sendgrid_api_double) { instance_double(SendGrid::API) }
  let(:client_double) { double('client') }
  let(:mail_endpoint_double) { double('mail') }
  let(:send_endpoint_double) { double('send') }
  let(:response_double) { instance_double('SendGrid::Response', status_code: 202, body: '{"message":"success"}', headers: {}) }
  let(:mail_double) { double('mail', to_json: '{}') }

  before do
    # Configure class variable before instantiating mailer
    allow(OT).to receive(:conf).and_return({
      'emailer' => { 'pass' => 'SG.test_key' },
      'site' => { 'domain' => 'example.com' }
    })

    # Setup mocks for SendGrid API
    allow(SendGrid::API).to receive(:new).and_return(sendgrid_api_double)
    allow(sendgrid_api_double).to receive(:client).and_return(client_double)
    allow(client_double).to receive(:mail).and_return(mail_endpoint_double)
    allow(mail_endpoint_double).to receive(:_).with('send').and_return(send_endpoint_double)
    allow(send_endpoint_double).to receive(:post).and_return(response_double)

    # Setup the class
    described_class.setup

    # Logging mocks - allow all types of calls
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT).to receive(:li)
    allow(OT::Utils).to receive(:obscure_email).with(to_address).and_return('r********@example.com')

    # SendGrid object mocks
    allow(SendGrid::Email).to receive(:new).and_return(double('email'))
    allow(SendGrid::Content).to receive(:new).and_return(double('content'))
    allow(SendGrid::Mail).to receive(:new).and_return(mail_double)
    allow(mail_double).to receive(:add_content)
    allow(mail_double).to receive(:reply_to=)
    allow(mail_double).to receive(:mail_settings=)
  end

  describe '#send_email' do
    it 'sends an email with correct parameters and logs success' do
      # Expectations for SendGrid objects
      expect(SendGrid::Email).to receive(:new).with(email: to_address)
      expect(SendGrid::Email).to receive(:new).with(email: from_email, name: from_name)
      expect(SendGrid::Content).to receive(:new).with(type: 'text/html', value: html_content)
      expect(SendGrid::Content).to receive(:new).with(type: 'text/plain', value: text_content)
      expect(SendGrid::Mail).to receive(:new).and_return(mail_double)

      # Logging expectations
      expect(OT).to receive(:li).with("> [send-start] [to: r********@example.com]")
      expect(OT).to receive(:info).with("> [send-success] Email sent successfully [to: r********@example.com] (test mode: false)")

      result = sendgrid_mailer.send_email(to_address, subject, html_content, text_content, false)
      expect(result).to eq(response_double)
    end

    context 'when a SendGrid error occurs' do
      before do
        allow(send_endpoint_double).to receive(:post).and_raise(StandardError.new('SendGrid Error'))
      end

      it 'logs the error and returns nil' do
        expect(OT).to receive(:li).with("> [send-start] [to: r********@example.com]")
        expect(OT).to receive(:le).with("> [send-exception-sending] StandardError SendGrid Error [to: r********@example.com]")

        result = sendgrid_mailer.send_email(to_address, subject, html_content, text_content, false)
        expect(result).to be_nil
      end
    end

    context 'when from_email is empty' do
      let(:from_email) { '' }

      it 'logs an error and returns nil' do
        expect(OT).to receive(:le).with("> [send-exception] No from address [to: r********@example.com]")

        result = sendgrid_mailer.send_email(to_address, subject, html_content, text_content, false)
        expect(result).to be_nil
      end
    end
  end

  describe '.setup' do
    it 'configures SendGrid with API key from OT.conf' do
      expect(SendGrid::API).to receive(:new).with(api_key: 'SG.test_key')
      described_class.setup
    end
  end
end
