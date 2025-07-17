# spec/unit/onetime/mail/mailer/ses_mailer_spec.rb

require_relative '../../../../spec_helper'
require 'aws-sdk-sesv2'
require 'onetime/mail/mailer/ses_mailer'

RSpec.describe Onetime::Mail::Mailer::SESMailer do
  let(:from_email) { 'sender@example.com' }
  let(:from_name) { 'Test Sender' }
  let(:to_email) { 'recipient@example.com' }
  let(:subject) { 'Test Subject' }
  let(:html_content) { '<p>Test Content</p>' }
  let(:text_content) { 'Test Content' }

  let(:mailer) {
    mailer = described_class.new(from_email, from_name)
    mailer.reply_to = from_email  # Set the reply_to attribute explicitly
    mailer
  }

  let(:ses_client_double) { instance_double(Aws::SESV2::Client) }
  let(:ses_response_double) { double('Aws::SESV2::Types::SendEmailResponse') }

  before do
    # Reset the class variable for each test
    described_class.instance_variable_set(:@ses_client, nil)

    # Mock AWS SES client
    allow(Aws::SESV2::Client).to receive(:new).and_return(ses_client_double)
    allow(ses_client_double).to receive(:send_email).and_return(ses_response_double)

    # Important: Set the accessor method correctly
    described_class.instance_variable_set(:@ses_client, ses_client_double)

    # Verify the accessor works as expected
    expect(described_class.ses_client).to eq(ses_client_double)

    # Using basic double instead of instance_double to avoid method existence checks
    allow(ses_response_double).to receive(:message_id).and_return('AMAZON_SES_MESSAGE_ID_123')
    allow(ses_response_double).to receive(:body).and_return(nil)
    allow(ses_response_double).to receive(:headers).and_return({})

    # Mock OT utilities
    allow(OT::Utils).to receive(:obscure_email).with(to_email).and_return('r***@example.com')
    allow(OT).to receive(:conf).and_return({
      emailer: {
        region: 'ca-central-1',
        user: 'AKIAEXAMPLE',
        pass: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
      }
    })

    # Allow all logging methods
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT).to receive(:li)
    allow(OT).to receive(:info)

    # Set up the instance variable that would normally be set in setup

    described_class.class_variable_set(:@@ses_client, ses_client_double)
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
                data: html_content,
                charset: 'UTF-8'
              },
              text: {
                data: text_content,
                charset: 'UTF-8'
              }
            }
          }
        },
        from_email_address: from_email,
        reply_to_addresses: [from_email]  # Needs to match what's set in the mailer
      }

      expect(ses_client_double).to receive(:send_email).with(expected_params)

      response = mailer.send_email(to_email, subject, html_content, text_content)
      expect(response).to eq(ses_response_double)
    end

    it 'logs the email sending process' do
      expect(OT).to receive(:li).with("> [send-start] [to: r***@example.com]")
      expect(OT).to receive(:info).with("> [send-success] Email sent successfully [to: r***@example.com]")

      mailer.send_email(to_email, subject, html_content, text_content)
    end

    context 'when SES service error occurs' do
      before do
        allow(ses_client_double).to receive(:send_email).and_raise(
          Aws::SESV2::Errors::ServiceError.new(
            'context',
            'Email address is not verified',
          ),
        )
      end

      it 'catches the error and logs it' do
        expect(OT).to receive(:li).with("> [send-start] [to: r***@example.com]")
        expect(OT).to receive(:le).with("> [send-exception-ses-error] Email address is not verified [to: r***@example.com]")

        result = mailer.send_email(to_email, subject, html_content, text_content)
        expect(result).to be_nil
      end
    end

    context 'when other error occurs' do
      before do
        allow(ses_client_double).to receive(:send_email).and_raise(StandardError.new('Unknown error'))
      end

      it 'catches the error and logs it' do
        expect(OT).to receive(:li).with("> [send-start] [to: r***@example.com]")
        expect(OT).to receive(:le).with("> [send-exception-sending] StandardError Unknown error [to: r***@example.com]")

        result = mailer.send_email(to_email, subject, html_content, text_content)
        expect(result).to be_nil
      end
    end
  end

  describe '.setup' do
    before do
      # Reset class variable to ensure setup runs fresh each time
      if described_class.class_variable_defined?(:@@ses_client)
        described_class.remove_class_variable(:@@ses_client)
      end

      # Allow the setup method to run without interference
      allow(described_class).to receive(:setup).and_call_original
    end

    it 'initializes the AWS SES client with the correct credentials' do
      # Setup the expectation before calling the method
      expect(Aws::Credentials).to receive(:new).with(
        'AKIAEXAMPLE',
        'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
      ).and_call_original

      expect(Aws::SESV2::Client).to receive(:new).with(
        hash_including(
          region: 'ca-central-1',
          credentials: instance_of(Aws::Credentials),
        ),
      )

      described_class.setup
    end

    it 'raises an error if region is not configured' do
      allow(OT).to receive(:conf).and_return({
        emailer: {
          user: 'AKIAEXAMPLE',
          pass: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
        }
      })

      expect { described_class.setup }.to raise_error(RuntimeError, "Region not configured")
    end
  end
end
