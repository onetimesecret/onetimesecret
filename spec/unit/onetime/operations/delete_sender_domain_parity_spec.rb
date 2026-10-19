# spec/unit/onetime/operations/delete_sender_domain_parity_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/delete_sender_domain'
require 'aws-sdk-sesv2'

RSpec.describe Onetime::Operations::DeleteSenderDomain, 'real SES strategy parity' do
  let(:config) do
    double('MailerConfig', domain_id: 'cd:ses-parity', effective_provider: 'ses', from_address: 'sender@example.com')
  end
  let(:credentials) do
    { 'access_key_id' => 'test-access-key', 'secret_access_key' => 'test-secret-key', 'region' => 'us-east-1' }
  end
  let(:log) { double('logger', info: nil, error: nil) }
  let(:endpoint) { 'https://email.us-east-1.amazonaws.com/v2/email/identities/example.com' }

  before do
    allow(Onetime).to receive(:get_logger).and_return(log)
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('ses').and_return(credentials)
    # Keep the real SDK request/response and exception mapping, without retry delays.
    allow(Aws::SESV2::Client).to receive(:new).and_wrap_original do |original, **options|
      original.call(**options, retry_limit: 0)
    end
  end

  def delete_domain
    described_class.new(mailer_config: config).call
  end

  it 'accepts the SDK empty success response and logs a deletion without a lookup' do
    stub_request(:delete, endpoint).to_return(status: 200, body: '')

    result = delete_domain

    expect(result.success?).to be true
    expect(result.error).to be_nil
    expect(result.message).to eq('Deleted sender identity example.com')
    expect(log).to have_received(:info).with('Sender domain deleted', hash_including(outcome: :deleted))
    expect(log).not_to have_received(:error)
    expect(a_request(:delete, endpoint)).to have_been_made.once
    expect(a_request(:get, /.*/)).not_to have_been_made
  end

  it 'maps the SDK NotFoundException to absence, not deletion or failure' do
    stub_request(:delete, endpoint).to_return(
      status: 404,
      headers: { 'x-amzn-errortype' => 'NotFoundException', 'content-type' => 'application/json' },
      body: { message: 'Identity not found' }.to_json,
    )

    result = delete_domain

    expect(result.success?).to be true
    expect(result.error).to be_nil
    expect(log).to have_received(:info).with('Sender domain already absent', hash_including(outcome: :absent))
    expect(log).not_to have_received(:info).with('Sender domain deleted', anything)
    expect(log).not_to have_received(:error)
    expect(a_request(:delete, endpoint)).to have_been_made.once
    expect(a_request(:get, /.*/)).not_to have_been_made
  end

  {
    'access denied' => [403, 'AccessDeniedException', 'Access denied'],
    'throttling' => [429, 'TooManyRequestsException', 'Rate limited'],
    'bad request mentioning absence' => [400, 'BadRequestException', 'Identity not found'],
    'untyped 404' => [404, nil, 'Unknown route'],
    'server failure' => [500, 'InternalServiceError', 'SES unavailable'],
    'blank provider error' => [400, 'BadRequestException', ''],
  }.each do |label, (status, type, message)|
    it "does not report success for #{label}" do
      headers = { 'content-type' => 'application/json' }
      headers['x-amzn-errortype'] = type if type
      stub_request(:delete, endpoint).to_return(status: status, headers: headers, body: { message: message }.to_json)

      result = delete_domain

      expect(result.failed?).to be true
      expect(result.error).to be_a(String)
      expect(result.error.strip).not_to be_empty
      expect(result.message).to include('SES deletion failed')
      expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(outcome: :failed, error: result.error))
      expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
      expect(a_request(:delete, endpoint)).to have_been_made.once
      expect(a_request(:get, /.*/)).not_to have_been_made
    end
  end

  it '[D05] does not report success for a connection timeout before the request is sent' do
    stub_request(:delete, endpoint).to_timeout

    result = delete_domain

    expect(result.failed?).to be true
    expect(result.error.strip).not_to be_empty
    expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(outcome: :failed))
    expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
  end

  it '[D05] does not report success for transport failure' do
    stub_request(:delete, endpoint).to_raise(Net::ReadTimeout)

    result = delete_domain

    expect(result.failed?).to be true
    expect(result.error.strip).not_to be_empty
    expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(outcome: :failed))
    expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
  end

  it 'reports an invalid sender address as failure without calling SES' do
    allow(config).to receive(:from_address).and_return('not-an-email')

    result = delete_domain

    expect(result.failed?).to be true
    expect(result.error).to eq('invalid_from_address')
    expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(outcome: :failed))
    expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end
end

RSpec.describe Onetime::Operations::DeleteSenderDomain, 'real provider strategy parity' do
  providers = {
    'sendgrid' => {
      credentials: { 'api_key' => 'SG.test-key' },
      lookup: [:get, 'https://api.sendgrid.com/v3/whitelabel/domains?limit=50&offset=0'],
      present: [{ id: 123, domain: 'example.com' }],
      absent: [],
      delete: [:delete, 'https://api.sendgrid.com/v3/whitelabel/domains/123'],
      deleted_status: 204,
      deleted_body: '',
      error: { errors: [{ message: 'provider denied' }] },
    },
    'smtp2go' => {
      credentials: { 'api_key' => 'api-0123456789abcdef0123456789abcdef' },
      lookup: [:post, 'https://api.smtp2go.com/v3/domain/view'],
      present: { data: { domains: [{ domain: { fulldomain: 'example.com' } }] } },
      absent: { data: { domains: [] } },
      delete: [:post, 'https://api.smtp2go.com/v3/domain/remove'],
      deleted_status: 200,
      deleted_body: { data: { domains: [] } }.to_json,
      error: { data: { error: 'provider denied', error_code: 'FORBIDDEN' } },
    },
    'lettermint' => {
      credentials: { 'team_token' => 'lm_team_test-team-token' },
      lookup: [:get, 'https://api.lettermint.co/v1/domains'],
      present: { data: [{ id: 'domain-uuid-123', domain: 'example.com' }], next_cursor: nil },
      absent: { data: [], next_cursor: nil },
      delete: [:delete, 'https://api.lettermint.co/v1/domains/domain-uuid-123'],
      deleted_status: 200,
      deleted_body: { message: 'Domain deleted successfully.' }.to_json,
      error: { message: 'provider denied' },
    },
  }

  let(:log) { double('logger', info: nil, error: nil) }

  before do
    allow(Onetime).to receive(:get_logger).and_return(log)
  end

  providers.each do |provider, api|
    context "with #{provider}" do
      let(:config) do
        double('MailerConfig', domain_id: 'cd:parity', effective_provider: provider, from_address: 'sender@example.com')
      end

      before do
        allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with(provider).and_return(api[:credentials])
      end

      def call_operation
        described_class.new(mailer_config: config).call
      end

      it 'reports an actual deletion through the real strategy and HTTP client' do
        lookup = stub_request(*api[:lookup])
          .to_return(status: 200, body: api[:present].to_json, headers: { 'content-type' => 'application/json' })
        unless provider == 'smtp2go'
          lookup.then.to_return(status: 200, body: api[:absent].to_json, headers: { 'content-type' => 'application/json' })
        end
        stub_request(*api[:delete]).to_return(
          status: api[:deleted_status], body: api[:deleted_body], headers: { 'content-type' => 'application/json' },
        )

        result = call_operation

        expect(result.success?).to be true
        expect(result.error).to be_nil
        expect(result.message.strip).not_to be_empty
        expect(log).to have_received(:info).with('Sender domain deleted', hash_including(provider: provider, outcome: :deleted))
        expect(log).not_to have_received(:error).with('Sender domain deletion failed', anything)
        expect(a_request(*api[:delete])).to have_been_made.once
        expect(a_request(*api[:lookup])).to have_been_made.once if provider == 'smtp2go'
      end

      it 'reports confirmed absence without attempting deletion' do
        stub_request(*api[:lookup]).to_return(
          status: 200, body: api[:absent].to_json, headers: { 'content-type' => 'application/json' },
        )

        result = call_operation

        expect(result.success?).to be true
        expect(result.error).to be_nil
        expect(log).to have_received(:info).with('Sender domain already absent', hash_including(provider: provider, outcome: :absent))
        expect(log).not_to have_received(:info).with('Sender domain deleted', anything)
        expect(a_request(*api[:delete])).not_to have_been_made
      end

      it 'reports lookup failure rather than absence' do
        stub_request(*api[:lookup]).to_return(
          status: 403, body: api[:error].to_json, headers: { 'content-type' => 'application/json' },
        )

        result = call_operation

        expect(result.failed?).to be true
        expect(result.error).to include('provider denied')
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(provider: provider, outcome: :failed))
        expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
        expect(a_request(*api[:delete])).not_to have_been_made
      end

      it '[D05] reports a lookup timeout, before any delete request, as failure' do
        stub_request(*api[:lookup]).to_timeout

        result = call_operation

        expect(result.failed?).to be true
        expect(result.error.strip).not_to be_empty
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(provider: provider, outcome: :failed))
        expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
        expect(a_request(*api[:delete])).not_to have_been_made
      end

      it '[D05] reports a timeout on the dispatched delete request as failure, not deletion' do
        stub_request(*api[:lookup]).to_return(
          status: 200, body: api[:present].to_json, headers: { 'content-type' => 'application/json' },
        )
        stub_request(*api[:delete]).to_raise(Net::ReadTimeout)

        result = call_operation

        expect(result.failed?).to be true
        expect(result.error.strip).not_to be_empty
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(provider: provider, outcome: :failed))
        expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
        expect(a_request(*api[:delete])).to have_been_made.once
      end

      it 'reports rejected deletion as failure' do
        stub_request(*api[:lookup]).to_return(
          status: 200, body: api[:present].to_json, headers: { 'content-type' => 'application/json' },
        )
        stub_request(*api[:delete]).to_return(
          status: 403, body: api[:error].to_json, headers: { 'content-type' => 'application/json' },
        )

        result = call_operation

        expect(result.failed?).to be true
        expect(result.error).to include('provider denied')
        expect(log).to have_received(:error).with('Sender domain deletion failed', hash_including(provider: provider, outcome: :failed))
        expect(log).not_to have_received(:info).with(/\ASender domain /, anything)
        expect(a_request(*api[:delete])).to have_been_made.once
      end
    end
  end
end
