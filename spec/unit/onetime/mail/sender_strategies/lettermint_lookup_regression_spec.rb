# frozen_string_literal: true

require 'spec_helper'
require 'lettermint'
require 'onetime/mail/sender_strategies/lettermint_sender_strategy'
require 'onetime/operations/delete_sender_domain'

# SDK 0.2.1: page_cursor becomes page[cursor]. The Team API OpenAPI schema
# /docs/api-reference/team/0.0.1/lettermint-team-openapi.json specifies a
# top-level next_cursor (null terminates), and MessageResponse for deletion.
RSpec.describe Onetime::Mail::SenderStrategies::LettermintSenderStrategy, 'lookup regressions' do
  let(:strategy) { described_class.new }
  let(:credentials) { { 'team_token' => 'test-team-token' } }
  let(:config) { double('config', from_address: 'sender@example.com', effective_provider: 'lettermint', domain_id: 'cd:test') }
  let(:resource) { double('domains') }
  let(:client) { instance_double(Lettermint::TeamAPI, domains: resource) }
  let(:target) { { 'domain' => 'example.com', 'id' => 'target-id' } }
  let(:other) { { 'domain' => 'other.example.com', 'id' => 'other-id' } }

  def page(entries, cursor = nil)
    { 'data' => entries, 'next_cursor' => cursor }
  end

  before do
    allow(strategy).to receive(:build_client).and_return(client)
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_error)
    allow(resource).to receive(:delete)
    allow(resource).to receive(:list).with(no_args).and_return(page([other], 'second'))
    allow(resource).to receive(:list).with(page_cursor: 'second').and_return(page([target]))
  end

  it '[L02] finds the later-page target with exact SDK continuation arguments' do
    expect(strategy.send(:find_domain_by_name, client, 'example.com')).to eq(target)
    expect(strategy.send(:list_domains, client)).to eq([other, target])
    expect(resource).to have_received(:list).with(no_args).twice
    expect(resource).to have_received(:list).with(page_cursor: 'second').twice
  end

  it '[L01/L12] stops an individual lookup early but never shortcuts inventory' do
    allow(resource).to receive(:list).with(no_args).and_return(page([target], 'second'))
    allow(resource).to receive(:list).with(page_cursor: 'second').and_raise(IOError, 'unavailable')
    expect(strategy.send(:find_domain_by_name, client, 'example.com')).to eq(target)
    expect(resource).not_to have_received(:list).with(page_cursor: 'second')
    expect { strategy.send(:list_domains, client) }.to raise_error(IOError, 'unavailable')
  end

  it '[L03/D02] exhausts a short page with a cursor before establishing absence' do
    allow(resource).to receive(:list).with(page_cursor: 'second').and_return(page([]))
    result = strategy.delete_sender_identity(config, credentials: credentials)
    expect(result).to include(outcome: :absent, deleted: false, error: nil)
    expect(resource).to have_received(:list).with(page_cursor: 'second').once
    expect(resource).not_to have_received(:delete)
  end

  it '[L04] accepts only a validated empty inventory' do
    allow(resource).to receive(:list).with(no_args).and_return(page([]))
    expect(strategy.send(:list_domains, client)).to eq([])
    expect(strategy.send(:find_domain_by_name, client, 'example.com')).to be_nil
  end

  [nil, {}, { 'next_cursor' => nil }, { 'data' => nil, 'next_cursor' => nil },
   { 'data' => {}, 'next_cursor' => nil }, { 'data' => [] },
   { 'data' => [], 'meta' => { 'next_cursor' => nil } },
   { 'data' => [], 'next_cursor' => false }, { 'data' => [], 'next_cursor' => ' ' },
   { 'data' => [nil], 'next_cursor' => nil },
   { 'data' => [{ 'id' => 'id' }], 'next_cursor' => nil },
   { 'data' => [{ 'domain' => 'example.com' }], 'next_cursor' => nil },
   { 'data' => [{ 'domain' => 'example.com', 'id' => ' ' }], 'next_cursor' => nil }].each_with_index do |malformed, i|
    it "[L06/L07/L08/L09/D06] fails closed on malformed later-page evidence #{i}" do
      allow(resource).to receive(:list).with(page_cursor: 'second').and_return(malformed)
      expect { strategy.send(:list_domains, client) }.to raise_error(described_class::LookupError)
      result = strategy.delete_sender_identity(config, credentials: credentials)
      expect(result).to include(outcome: :failed, deleted: false)
      expect(result[:error].strip).not_to be_empty
      expect(resource).not_to have_received(:delete)
    end
  end

  it '[L09] terminates a cursor cycle without fetching a repeated page' do
    allow(resource).to receive(:list).with(page_cursor: 'second').and_return(page([other], 'third'))
    allow(resource).to receive(:list).with(page_cursor: 'third').and_return(page([], 'second'))
    expect { strategy.send(:list_domains, client) }.to raise_error(described_class::LookupError, /cursor/i)
    expect(resource).to have_received(:list).with(page_cursor: 'second').once
    expect(resource).to have_received(:list).with(page_cursor: 'third').once
  end

  [401, 403, 404, 429, 500].each do |status|
    it "[L05/L13/D11] does not turn list HTTP #{status} into absence" do
      allow(resource).to receive(:list).with(no_args)
        .and_raise(Lettermint::HttpRequestError.new(message: 'Not found', status_code: status))
      result = strategy.delete_sender_identity(config, credentials: credentials)
      expect(result).to include(outcome: :failed, deleted: false)
      expect(resource).not_to have_received(:delete)
    end
  end

  it '[L13] does not turn a RESOURCE_NOT_FOUND from the list endpoint into absence' do
    allow(resource).to receive(:list).with(no_args).and_raise(
      Lettermint::NotFoundError.new(message: 'Resource not found.', code: 'RESOURCE_NOT_FOUND',
        response_body: { 'error' => { 'code' => 'RESOURCE_NOT_FOUND', 'message' => 'Resource not found.' } }),
    )
    result = strategy.delete_sender_identity(config, credentials: credentials)
    expect(result).to include(outcome: :failed, deleted: false, error: 'Resource not found.')
    expect(resource).not_to have_received(:delete)
  end

  # Error bodies as lettermint-ruby 0.2.1 captured them live on 2026-10-16
  # (spec/fixtures/errors/README.md in the gem): a missing domain answers with
  # an ApiError carrying code RESOURCE_NOT_FOUND; an unknown route answers
  # with a message-only ErrorMessage. The gem raises NotFoundError for both
  # and exposes the code; only the code establishes absence.
  it '[D03] recognizes documented structured not-found only at the delete endpoint' do
    allow(resource).to receive(:delete).with('target-id').and_raise(
      Lettermint::NotFoundError.new(message: 'Resource not found.', code: 'RESOURCE_NOT_FOUND',
        response_body: { 'error' => { 'code' => 'RESOURCE_NOT_FOUND', 'message' => 'Resource not found.' } }),
    )
    expect(strategy.delete_sender_identity(config, credentials: credentials))
      .to include(outcome: :absent, deleted: false, error: nil)
  end

  it '[D11] does not treat a message-only 404 body as absence' do
    message = 'The route v1/domains/target-id could not be found.'
    allow(resource).to receive(:delete).with('target-id').and_raise(
      Lettermint::NotFoundError.new(message: message, response_body: { 'message' => message }),
    )
    expect(strategy.delete_sender_identity(config, credentials: credentials))
      .to include(outcome: :failed, deleted: false, error: message)
    expect(resource).to have_received(:delete).once
  end

  it '[D11] does not treat a string-error 404 body as absence' do
    allow(resource).to receive(:delete).with('target-id').and_raise(
      Lettermint::NotFoundError.new(message: 'HTTP 404', code: 'not_found', response_body: { 'error' => 'not_found' }),
    )
    expect(strategy.delete_sender_identity(config, credentials: credentials))
      .to include(outcome: :failed, deleted: false, error: 'HTTP 404')
  end

  it '[D11] does not treat a proxy HTML 404 as absence' do
    allow(resource).to receive(:delete).with('target-id').and_raise(
      Lettermint::NotFoundError.new(message: 'HTTP 404', response_body: '<html><body>404 Not Found</body></html>'),
    )
    expect(strategy.delete_sender_identity(config, credentials: credentials))
      .to include(outcome: :failed, deleted: false, error: 'HTTP 404')
  end

  [nil, {}, { 'message' => '' }, { 'message' => 1 }, { 'message' => 'ok', 'error' => 'denied' }].each do |response|
    it "[D12] rejects an invalid delete acknowledgement #{response.inspect}" do
      allow(resource).to receive(:delete).with('target-id').and_return(response)
      expect(strategy.delete_sender_identity(config, credentials: credentials)).to include(outcome: :failed, deleted: false)
    end
  end

  it '[D09] supplies a fallback error for an exception with a blank message' do
    allow(resource).to receive(:delete).and_raise(StandardError.new(''))
    expect(strategy.delete_sender_identity(config, credentials: credentials))
      .to include(outcome: :failed, error: a_string_including('StandardError'))
  end

  it '[C12] recovers an existing later-page identity after duplicate creation' do
    allow(resource).to receive(:create).with(domain: 'example.com')
      .and_raise(Lettermint::HttpRequestError.new(message: 'Conflict', status_code: 409))
    allow(resource).to receive(:find).with('target-id', include: 'dnsRecords')
      .and_return(target.merge('dns_records' => []))
    expect(strategy.provision_dns_records(config, credentials: credentials)[:success]).to be true
    expect(resource).to have_received(:list).with(page_cursor: 'second').once
    expect(resource).to have_received(:create).once
  end

  it '[C13] fails duplicate recovery without another creation when lookup fails' do
    allow(resource).to receive(:create).with(domain: 'example.com')
      .and_raise(Lettermint::HttpRequestError.new(message: 'Conflict', status_code: 409))
    allow(resource).to receive(:list).with(page_cursor: 'second').and_raise(IOError, 'lookup failed')
    expect(strategy.provision_dns_records(config, credentials: credentials)[:success]).to be false
    expect(resource).to have_received(:create).once
  end

  it '[C15] reports verification indeterminate for malformed inventory, not unverified absence' do
    allow(resource).to receive(:list).with(page_cursor: 'second').and_return('next_cursor' => nil)
    expect(strategy.check_provider_verification_status(config, credentials: credentials))
      .to include(verified: nil, status: 'error')
  end

  context '[L15] domain names that differ only in case' do
    let(:target) { { 'domain' => 'Example.COM', 'id' => 'Dom_MixedCase-ID' } }

    it 'selects the same entry and unchanged ID in individual lookup and inventory matching' do
      expect(strategy.send(:find_domain_by_name, client, 'example.com')).to eq(target)
      inventory = strategy.send(:list_domains, client)
      expect(strategy.send(:domain_entry, inventory, 'example.com')).to equal(inventory.last)
      expect(strategy.send(:domain_entry, inventory, 'EXAMPLE.com')['id']).to eq('Dom_MixedCase-ID')
      expect(strategy.send(:domain_entry, inventory, 'OTHER.example.com')).to eq(other)
    end

    it 'does not match a partial or unrelated name' do
      inventory = strategy.send(:list_domains, client)
      %w[ample.com example.co sub.example.com example.com.evil].each do |name|
        expect(strategy.send(:domain_entry, inventory, name)).to be_nil
      end
    end

    it 'deletes the case-variant identity by its unchanged provider ID' do
      allow(resource).to receive(:delete).with('Dom_MixedCase-ID').and_return('message' => 'Domain deleted successfully.')
      expect(strategy.delete_sender_identity(config, credentials: credentials))
        .to include(outcome: :deleted, deleted: true, error: nil)
      expect(resource).to have_received(:delete).with('Dom_MixedCase-ID').once
    end

    it 'recovers the case-variant identity after duplicate creation' do
      allow(config).to receive(:from_address).and_return('sender@EXAMPLE.com')
      allow(resource).to receive(:create).with(domain: 'EXAMPLE.com')
        .and_raise(Lettermint::HttpRequestError.new(message: 'Conflict', status_code: 409))
      allow(resource).to receive(:find).with('Dom_MixedCase-ID', include: 'dnsRecords')
        .and_return(target.merge('dns_records' => []))
      result = strategy.provision_dns_records(config, credentials: credentials)
      expect(result).to include(success: true, identity_id: 'Example.COM')
      expect(resource).to have_received(:create).once
    end

    it 'checks verification on the case-variant identity' do
      allow(resource).to receive(:verify_dns).with('Dom_MixedCase-ID')
      allow(resource).to receive(:find).with('Dom_MixedCase-ID', include: 'dnsRecords')
        .and_return(target.merge('status' => 'verified', 'dns_records' => []))
      expect(strategy.check_provider_verification_status(config, credentials: credentials))
        .to include(verified: true, status: 'verified')
    end
  end

  it '[O08] does not reuse preflight evidence to mask a later cleanup lookup failure' do
    expect(strategy.send(:list_domains, client)).to eq([other, target])
    allow(resource).to receive(:list).with(page_cursor: 'second').and_raise(IOError, 'fresh failure')
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('lettermint').and_return(strategy)
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).with('lettermint').and_return(credentials)
    result = Onetime::Operations::DeleteSenderDomain.new(mailer_config: config).call
    expect(result.failed?).to be true
    expect(result.error).to include('fresh failure')
    expect(resource).not_to have_received(:delete)
  end
end

RSpec.describe 'Lettermint SDK pagination transport' do
  it 'maps the continuation keyword to page[cursor] using the installed SDK' do
    client = Lettermint::TeamAPI.new(team_token: 'lm_team_test-token')
    stub_request(:get, 'https://api.lettermint.co/v1/domains')
      .to_return(headers: { 'content-type' => 'application/json' },
        body: { data: [], next_cursor: 'next-page' }.to_json)
    continuation = stub_request(:get, 'https://api.lettermint.co/v1/domains')
      .with(query: { 'page[cursor]' => 'next-page' })
      .to_return(headers: { 'content-type' => 'application/json' }, body: { data: [], next_cursor: nil }.to_json)
    strategy = Onetime::Mail::SenderStrategies::LettermintSenderStrategy.new
    expect(strategy.send(:list_domains, client)).to eq([])
    expect(continuation).to have_been_requested.once
  end
end
