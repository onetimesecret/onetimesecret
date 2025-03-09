# tests/unit/ruby/rspec/onetime/app/mail/ses_mailer_spec.rb

require_relative '../../../spec_helper'
require 'aws-sdk-sesv2'
require 'onetime/app/mail/ses_mailer'

RSpec.describe Onetime::App::Mail::AmazonSESMailer do
  let(:from_email) { 'sender@example.com' }
  let(:from_name) { 'Test Sender' }
  let(:to_email) { 'recipient@example.com' }
  let(:subject) { 'Test Subject' }
  let(:content) { '<p>Test Content</p>' }

  let(:mailer) { described_class.new(from_email, from_name) }
  let(:ses_client_double) { instance_double(Aws::SESV2::Client) }
  let(:ses_response_double) { instance_double('Aws::SESV2::Types::SendEmailResponse') }
  let(:http_context_double) { instance_double('Seahorse::Client::RequestContext') }
  let(:http_response_double) { instance_double('Seahorse::Client::Http::Response') }

  before do
    # Mock AWS SES client
    allow(Aws::SESV2::Client).to receive(:new).and_return(ses_client_double)
    allow(ses_client_double).to receive(:send_email).and_return(ses_response_double)

    allow(ses_response_double).to receive(:message_id).and_return('AMAZON_SES_MESSAGE_ID_123')

    # Mock OT utilities
    allow(OT::Utils).to receive(:obscure_email).with(to_email).and_return('r***@example.com')
    allow(OT).to receive(:conf).and_return({
      emailer: {
        region: 'us-west-2',
        access_key_id: 'AKIAEXAMPLE',
        secret_access_key: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
      }
    })

    # Set up the instance variable that would normally be set in setup
    mailer.class.instance_variable_set(:@ses_client, ses_client_double)

    # Set up the instance variable that would normally be set in setup
    described_class.setup
  end

  describe '#initialize' do
    it 'sets from and fromname attributes' do
      expect(mailer.from).to eq(from_email)
      expect(mailer.fromname).to eq(from_name)
    end
  end

  describe '#send_email' do
    it 'sends an email with the correct parameters' do
      expected_params = {
        destination: {
          to_addresses: [to_email]
        },
        content: {
          simple: {
            subject: {
              data: subject,
              charset: 'UTF-8'
            },
            body: {
              html: {
                data: content,
                charset: 'UTF-8'
              },
              text: {
                data: content.gsub(/<\/?[^>]*>/, ''),
                charset: 'UTF-8'
              }
            }
          }
        },
        from_email_address: "#{from_name} <#{from_email}>",
        reply_to_addresses: [from_email]
      }

      expect(ses_client_double).to receive(:send_email).with(expected_params)

      response = mailer.send_email(to_email, subject, content)
      expect(response).to eq(ses_response_double)
    end

    it 'logs the email sending process' do
      expect(OT).to receive(:info).with('[email-send-start]')
      expect(OT).to receive(:ld).with("> [send-start] r***@example.com")
      expect(OT).to receive(:info).with('[email-sent]')
      expect(OT).to receive(:ld).with('AMAZON_SES_MESSAGE_ID_123')
      expect(OT).to receive(:ld).with('Email sent successfully')

      mailer.send_email(to_email, subject, content)
    end

    context 'when SES service error occurs' do
      before do
        allow(ses_client_double).to receive(:send_email).and_raise(
          Aws::SESV2::Errors::ServiceError.new(
            context: double('context'),
            message: 'Email address is not verified'
          )
        )
      end

      it 'catches the error and logs it' do
        expect(OT).to receive(:info).with("> [send-exception-ses-error] r***@example.com Aws::SESV2::Errors::ServiceError Email address is not verified")
        expect(OT).to receive(:ld)

        result = mailer.send_email(to_email, subject, content)
        expect(result).to be_nil
      end
    end

    context 'when other error occurs' do
      before do
        allow(ses_client_double).to receive(:send_email).and_raise(StandardError.new('Unknown error'))
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
    it 'initializes the AWS SES client with the correct credentials' do
      expect(Aws::SESV2::Client).to receive(:new).with(
        region: 'us-west-2',
        credentials: instance_of(Aws::Credentials)
      )

      # Verify credentials are created correctly
      expect(Aws::Credentials).to receive(:new).with(
        'AKIAEXAMPLE',
        'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
      )

      described_class.setup
    end

    it 'uses default region if not specified in config' do
      allow(OT).to receive(:conf).and_return({
        emailer: {
          access_key_id: 'AKIAEXAMPLE',
          secret_access_key: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
        }
      })

      expect(Aws::SESV2::Client).to receive(:new).with(
        region: 'us-east-1',
        credentials: instance_of(Aws::Credentials)
      )

      described_class.setup
    end
  end
end
