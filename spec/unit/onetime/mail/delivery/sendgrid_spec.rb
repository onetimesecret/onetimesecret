# spec/unit/onetime/mail/delivery/sendgrid_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/delivery/sendgrid'

RSpec.describe Onetime::Mail::Delivery::SendGrid do
  let(:config) { { api_key: 'SG.test-key-example' } }
  let(:sendgrid) { described_class.new(config) }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'sender@example.com',
      subject: 'Test email',
      text_body: 'Hello',
    }
  end

  def mock_response(code, body = nil)
    body ||= if code.to_i >= 400
               '{"errors":[{"message":"error","field":null,"help":null}]}'
             else
               ''
             end
    response = instance_double('Net::HTTPResponse')
    allow(response).to receive(:code).and_return(code.to_s)
    allow(response).to receive(:body).and_return(body)
    response
  end

  before do
    allow(sendgrid).to receive(:send_request).and_return(mock_response(202))
    allow(sendgrid).to receive(:log_delivery)
    allow(sendgrid).to receive(:log_error)
  end

  describe '#deliver success' do
    it 'delivers and logs on 2xx response' do
      sendgrid.deliver(email)
      expect(sendgrid).to have_received(:log_delivery)
    end
  end

  describe '#deliver error classification' do
    context 'when API returns 429 (rate limited)' do
      it 'raises transient DeliveryError' do
        allow(sendgrid).to receive(:send_request)
          .and_return(mock_response(429, '{"errors":[{"message":"rate limited","field":null,"help":null}]}'))

        expect { sendgrid.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
            expect(err.original_error).to be_a(described_class::APIError)
            expect(err.original_error.status_code).to eq(429)
          end
      end
    end

    context 'when API returns 5xx (server error)' do
      [500, 502, 503].each do |code|
        it "raises transient DeliveryError for #{code}" do
          allow(sendgrid).to receive(:send_request)
            .and_return(mock_response(code))

          expect { sendgrid.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be true
            end
        end
      end
    end

    context 'when API returns 4xx (client error, non-429)' do
      [400, 401, 403].each do |code|
        it "raises fatal DeliveryError for #{code}" do
          allow(sendgrid).to receive(:send_request)
            .and_return(mock_response(code))

          expect { sendgrid.deliver(email) }
            .to raise_error(Onetime::Mail::DeliveryError) do |err|
              expect(err.transient?).to be false
            end
        end
      end
    end

    context 'network errors (inherited from Base)' do
      it 'classifies Errno::ECONNREFUSED as transient' do
        allow(sendgrid).to receive(:send_request)
          .and_raise(Errno::ECONNREFUSED, 'Connection refused')

        expect { sendgrid.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end

      it 'classifies Net::OpenTimeout as transient' do
        allow(sendgrid).to receive(:send_request)
          .and_raise(Net::OpenTimeout, 'timed out')

        expect { sendgrid.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be true
          end
      end
    end

    context 'unknown errors' do
      it 'classifies generic StandardError as non-transient' do
        allow(sendgrid).to receive(:send_request)
          .and_raise(StandardError, 'unexpected')

        expect { sendgrid.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err.transient?).to be false
          end
      end
    end

    context 'DeliveryError pass-through' do
      it 'does not double-wrap DeliveryError' do
        original = Onetime::Mail::DeliveryError.new(
          'already wrapped',
          original_error: RuntimeError.new('inner'),
          transient: true,
        )
        allow(sendgrid).to receive(:send_request).and_raise(original)

        expect { sendgrid.deliver(email) }
          .to raise_error(Onetime::Mail::DeliveryError) do |err|
            expect(err).to equal(original)
          end
      end
    end
  end

  describe 'APIError' do
    it 'carries status_code and response_body' do
      body = '{"errors":[{"message":"rate limited","field":null,"help":null}]}'
      error = described_class::APIError.new(
        'test error',
        status_code: 429,
        response_body: body,
      )
      expect(error.status_code).to eq(429)
      expect(error.response_body).to eq(body)
      expect(error.message).to eq('test error')
    end
  end
end
