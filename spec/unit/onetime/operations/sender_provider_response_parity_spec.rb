# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/delete_sender_domain'

RSpec.describe 'Sender provider response parity through DeleteSenderDomain' do
  let(:logger) { double('logger', info: nil, error: nil) }
  let(:credentials) { { 'api_key' => 'provider-test-key' } }
  let(:config) do
    double('MailerConfig', domain_id: 'parity-domain', effective_provider: provider, from_address: 'sender@example.com')
  end

  before do
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with(provider).and_return(credentials)
    allow(Onetime).to receive(:get_logger).and_return(logger)
  end

  def call_operation
    Onetime::Operations::DeleteSenderDomain.new(mailer_config: config).call
  end

  def expect_disposition(result, outcome)
    expect(result.success?).to eq(outcome != :failed)
    if outcome == :failed
      expect(result.error).to match(/\S/)
      expect(logger).to have_received(:error).with('Sender domain deletion failed', hash_including(outcome: :failed))
      expect(logger).not_to have_received(:info).with('Sender domain deleted', anything)
    else
      expect(result.error).to be_nil
      event = outcome == :deleted ? 'Sender domain deleted' : 'Sender domain already absent'
      expect(logger).to have_received(:info).with(event, hash_including(outcome: outcome))
      expect(logger).not_to have_received(:error)
    end
  end

  context 'with the real SendGrid adapter' do
    let(:provider) { 'sendgrid' }
    let(:listing_url) { 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=0' }
    let(:delete_url) { 'https://api.sendgrid.com/v3/whitelabel/domains/123' }

    it 'logs absence, not deletion, after a validated empty inventory' do
      stub_request(:get, listing_url).to_return(status: 200, body: '[]')
      expect_disposition(call_operation, :absent)
      expect(a_request(:delete, delete_url)).not_to have_been_made
    end

    it 'logs actual deletion after a matching ID and successful DELETE' do
      stub_request(:get, listing_url).to_return(status: 200, body: '[{"domain":"example.com","id":123}]')
      stub_request(:delete, delete_url).to_return(status: 204, body: '')
      expect_disposition(call_operation, :deleted)
      expect(a_request(:delete, delete_url)).to have_been_made.once
    end

    ['{}', '[{"domain":"example.com"}]', '[{"id":123}]', '[null]'].each do |body|
      it "fails closed for malformed lookup #{body}" do
        stub_request(:get, listing_url).to_return(status: 200, body: body)
        expect_disposition(call_operation, :failed)
        expect(a_request(:delete, /api\.sendgrid\.com/)).not_to have_been_made
        expect(a_request(:post, /api\.sendgrid\.com/)).not_to have_been_made
      end
    end

    it 'does not delete after a later page is rejected' do
      entries = 50.times.map { |i| { 'id' => i + 1, 'domain' => "other#{i}.com" } }
      stub_request(:get, listing_url).to_return(status: 200, body: JSON.generate(entries))
      stub_request(:get, 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=50')
        .to_return(status: 429, body: '{"errors":[{"message":"rate limited"}]}')
      expect_disposition(call_operation, :failed)
      expect(a_request(:delete, /api\.sendgrid\.com/)).not_to have_been_made
    end

    it 'reports a rejected DELETE as failure' do
      stub_request(:get, listing_url).to_return(status: 200, body: '[{"domain":"example.com","id":123}]')
      stub_request(:delete, delete_url).to_return(status: 403, body: '{"errors":[{"message":"Forbidden"}]}')
      expect_disposition(call_operation, :failed)
    end

    it 'keeps blank transport exceptions as failures, not no-ops' do
      stub_request(:get, listing_url).to_raise(StandardError.new(''))
      expect_disposition(call_operation, :failed)
      expect(a_request(:delete, /api\.sendgrid\.com/)).not_to have_been_made
    end
  end

  context 'with the real SMTP2GO adapter and client' do
    let(:provider) { 'smtp2go' }
    let(:view_url) { 'https://api.smtp2go.com/v3/domain/view' }
    let(:remove_url) { 'https://api.smtp2go.com/v3/domain/remove' }
    let(:present_body) { '{"request_id":"test","data":{"domains":[{"domain":{"fulldomain":"example.com"}}]}}' }
    let(:absent_body) { '{"request_id":"test","data":{"domains":[]}}' }

    it 'logs absence, not deletion, after a validated filtered view' do
      stub_request(:post, view_url).with(body: { 'domain' => 'example.com' }).to_return(status: 200, body: absent_body)
      expect_disposition(call_operation, :absent)
      expect(a_request(:post, remove_url)).not_to have_been_made
    end

    it 'logs deletion from the documented removal acknowledgement without a third request' do
      # Official v3.0.2 /domain/remove 200 example: data.domains = []
      # https://developers.smtp2go.com/reference/remove-sender-domain
      stub_request(:post, view_url).to_return(status: 200, body: present_body)
      stub_request(:post, remove_url).with(body: { 'domain' => 'example.com' }).to_return(status: 200, body: absent_body)
      expect_disposition(call_operation, :deleted)
      expect(a_request(:post, remove_url)).to have_been_made.once
      expect(a_request(:post, view_url)).to have_been_made.once
    end

    ['', 'null', '{}', '{"data":{}}', '{"data":{"domains":null}}', '{"data":{"success":false,"domains":[]}}',
     '{"data":{"domains":[{}]}}', '{"data":{"domains":[{"domain":{"fulldomain":false}}]}}'].each do |body|
      it "fails closed for malformed lookup envelope #{body.inspect}" do
        stub_request(:post, view_url).to_return(status: 200, body: body)
        expect_disposition(call_operation, :failed)
        expect(a_request(:post, remove_url)).not_to have_been_made
        expect(a_request(:post, 'https://api.smtp2go.com/v3/domain/add')).not_to have_been_made
      end
    end

    [400, 404, 500].each do |status|
      it "does not turn HTTP #{status} lookup failure into absence" do
        stub_request(:post, view_url).to_return(status: status, body: '{"data":{"error":"Domain does not exist or request failed","error_code":"E_ApiResponseCodes.API_EXCEPTION"}}')
        expect_disposition(call_operation, :failed)
        expect(a_request(:post, remove_url)).not_to have_been_made
      end
    end

    it 'reports a 2xx API error envelope as failure' do
      stub_request(:post, view_url).to_return(status: 200, body: present_body)
      stub_request(:post, remove_url).to_return(status: 200, body: '{"data":{"error":"rejected","error_code":"API_EXCEPTION"}}')
      expect_disposition(call_operation, :failed)
    end

    ['', 'null', '{}', '{"data":{}}', '{"data":{"success":true}}',
     '{"data":{"domains":null}}', '{"data":{"domains":{}}}', '{"data":{"domains":[{}]}}',
     '{"data":{"domains":[{"domain":"other.com"},{}]}}'].each do |body|
      it "does not claim deletion for malformed removal acknowledgement #{body.inspect}" do
        stub_request(:post, view_url).to_return(status: 200, body: present_body)
        stub_request(:post, remove_url).to_return(status: 200, body: body)
        expect_disposition(call_operation, :failed)
        expect(a_request(:post, view_url)).to have_been_made.once
        expect(a_request(:post, remove_url)).to have_been_made.once
      end
    end

    it 'does not claim deletion if the removal acknowledgement retains the target' do
      stub_request(:post, view_url).to_return(status: 200, body: present_body)
      stub_request(:post, remove_url).to_return(status: 200, body: present_body)
      expect_disposition(call_operation, :failed)
      expect(a_request(:post, view_url)).to have_been_made.once
      expect(a_request(:post, remove_url)).to have_been_made.once
    end

    it 'keeps blank transport exceptions as failures, not no-ops' do
      stub_request(:post, view_url).to_raise(StandardError.new(''))
      expect_disposition(call_operation, :failed)
      expect(a_request(:post, remove_url)).not_to have_been_made
    end
  end
end
