# spec/unit/onetime/mail/sender_strategies/sendgrid_sender_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/sender_strategies/sendgrid_sender_strategy'

RSpec.describe Onetime::Mail::SenderStrategies::SendGridSenderStrategy do
  let(:strategy) { described_class.new }
  let(:credentials) { { 'api_key' => 'SG.test-api-key-example' } }
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end

  before do
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_error)
  end

  def mock_http_response(code, body)
    response = instance_double('Net::HTTPResponse')
    allow(response).to receive(:code).and_return(code.to_s)
    allow(response).to receive(:body).and_return(body.is_a?(String) ? body : body.to_json)
    response
  end

  describe '#provision_dns_records' do
    context 'with valid from_address' do
      let(:sendgrid_response) do
        {
          'id' => 123,
          'domain' => 'example.com',
          'subdomain' => 'em1234',
          'valid' => false,
          'dns' => {
            'mail_cname' => {
              'host' => 'em1234.example.com',
              'type' => 'cname',
              'data' => 'u1234.wl.sendgrid.net',
            },
            'dkim1' => {
              'host' => 's1._domainkey.example.com',
              'type' => 'cname',
              'data' => 's1.domainkey.u1234.wl.sendgrid.net',
            },
            'dkim2' => {
              'host' => 's2._domainkey.example.com',
              'type' => 'cname',
              'data' => 's2.domainkey.u1234.wl.sendgrid.net',
            },
          },
        }
      end

      before do
        allow(strategy).to receive(:post_request)
          .with('/whitelabel/domains', { domain: 'example.com', automatic_security: true }, api_key: credentials['api_key'])
          .and_return({ success: true, data: sendgrid_response })
      end

      it 'returns success with DNS records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records]).to contain_exactly(
          { type: 'CNAME', name: 'em1234.example.com', value: 'u1234.wl.sendgrid.net', purpose: 'mail_cname' },
          { type: 'CNAME', name: 's1._domainkey.example.com', value: 's1.domainkey.u1234.wl.sendgrid.net', purpose: 'dkim1' },
          { type: 'CNAME', name: 's2._domainkey.example.com', value: 's2.domainkey.u1234.wl.sendgrid.net', purpose: 'dkim2' }
        )
      end

      it 'includes provider_data with domain_id' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:provider_data][:domain_id]).to eq(123)
        expect(result[:provider_data][:subdomain]).to eq('em1234')
        expect(result[:provider_data][:valid]).to be false
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: 'invalid-email') }

      it 'returns error for missing domain' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('invalid_from_address')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'with empty from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: '') }

      it 'returns error for empty address' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('invalid_from_address')
      end
    end

    context 'with missing api_key' do
      let(:credentials) { { 'api_key' => nil } }

      it 'returns error for missing key' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_api_key')
      end
    end

    context 'with empty api_key' do
      let(:credentials) { { 'api_key' => '' } }

      it 'returns error for empty key' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_api_key')
      end
    end

    context 'when SendGrid API fails' do
      before do
        allow(strategy).to receive(:post_request)
          .and_return({
            success: false,
            data: { 'errors' => [{ 'message' => 'Domain already authenticated' }] },
            error: 'Domain already authenticated',
          })
      end

      it 'returns error with message' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Domain already authenticated')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(strategy).to receive(:post_request)
          .and_raise(StandardError, 'Network timeout')
      end

      it 'returns error with exception message' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:message]).to include('Network timeout')
      end
    end
  end

  describe '#check_provider_verification_status' do
    context 'when domain is verified' do
      before do
        allow(strategy).to receive(:find_domain_id)
          .with('example.com', api_key: credentials['api_key'])
          .and_return(123)

        allow(strategy).to receive(:post_request)
          .with('/whitelabel/domains/123/validate', {}, api_key: credentials['api_key'])
          .and_return({
            success: true,
            data: {
              'valid' => true,
              'validation_results' => {
                'mail_cname' => { 'valid' => true },
                'dkim1' => { 'valid' => true },
                'dkim2' => { 'valid' => true },
              },
            },
          })
      end

      it 'returns verified status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
      end
    end

    context 'when domain is pending verification' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(123)
        allow(strategy).to receive(:post_request)
          .and_return({
            success: true,
            data: {
              'valid' => false,
              'validation_results' => {
                'mail_cname' => { 'valid' => true },
                'dkim1' => { 'valid' => false },
                'dkim2' => { 'valid' => false },
              },
            },
          })
      end

      it 'returns pending status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('pending')
      end

      it 'includes validation details' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:details]).to include('mail_cname', 'dkim1', 'dkim2')
      end
    end

    context 'when domain_id is provided in credentials' do
      let(:credentials_with_id) { { 'api_key' => 'SG.test-key', 'domain_id' => 456 } }

      before do
        allow(strategy).to receive(:post_request)
          .with('/whitelabel/domains/456/validate', {}, api_key: credentials_with_id['api_key'])
          .and_return({ success: true, data: { 'valid' => true } })
      end

      it 'uses provided domain_id' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials_with_id)

        expect(result[:verified]).to be true
        expect(strategy).not_to have_received(:find_domain_id) if strategy.respond_to?(:find_domain_id)
      end
    end

    context 'when domain not found' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(nil)
      end

      it 'returns not_found status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('not_found')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: 'invalid') }

      it 'returns invalid status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('invalid')
      end
    end

    context 'with missing api_key' do
      let(:credentials) { {} }

      it 'returns verified: nil — the check could not run' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
      end
    end

    context 'when the validate request fails (provider API error)' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(123)
        allow(strategy).to receive(:post_request)
          .and_return({ success: false, error: 'unauthorized' })
      end

      it 'returns verified: nil — indeterminate, never an authoritative false' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to eq('unauthorized')
      end
    end

    context 'when the domain lookup fails (provider API error)' do
      it 'returns an indeterminate error instead of not_found' do
        allow(strategy).to receive(:get_request)
          .and_return({ success: false, error: 'Rate limited' })

        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Rate limited')
      end
    end

    context 'when an unexpected error occurs (transport failure)' do
      before do
        allow(strategy).to receive(:find_domain_id).and_raise(StandardError.new('connection reset'))
      end

      it 'returns verified: nil — indeterminate, never an authoritative false' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('connection reset')
      end
    end
  end

  describe '#delete_sender_identity' do
    context 'when deletion succeeds' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(123)
        allow(strategy).to receive(:delete_request)
          .with('/whitelabel/domains/123', api_key: credentials['api_key'])
          .and_return({ success: true, data: {} })
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('deleted')
      end
    end

    context 'when domain_id is provided in credentials' do
      let(:credentials_with_id) { { 'api_key' => 'SG.test-key', 'domain_id' => 789 } }

      before do
        allow(strategy).to receive(:delete_request)
          .with('/whitelabel/domains/789', api_key: credentials_with_id['api_key'])
          .and_return({ success: true, data: {} })
      end

      it 'uses provided domain_id' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials_with_id)

        expect(result[:deleted]).to be true
      end
    end

    context 'when domain not found' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(nil)
      end

      it 'returns deleted false with message' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('not found')
      end
    end

    context 'when API returns error' do
      before do
        allow(strategy).to receive(:find_domain_id).and_return(123)
        allow(strategy).to receive(:delete_request)
          .and_return({ success: false, error: 'Forbidden' })
      end

      it 'returns deleted false with error' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Forbidden')
        expect(result[:error]).to eq('Forbidden')
      end
    end

    context 'when the domain lookup fails' do
      [0, 50].each do |failed_offset|
        it "reports an error instead of absence when page offset #{failed_offset} is rate limited" do
          if failed_offset.positive?
            page = 50.times.map { |i| { 'id' => i + 1, 'domain' => "other#{i}.com" } }
            allow(strategy).to receive(:get_request)
              .with('/whitelabel/domains?limit=50&offset=0', api_key: credentials['api_key'])
              .and_return({ success: true, data: page })
          end
          allow(strategy).to receive(:get_request)
            .with("/whitelabel/domains?limit=50&offset=#{failed_offset}", api_key: credentials['api_key'])
            .and_return({ success: false, error: 'Rate limited' })
          expect(strategy).not_to receive(:delete_request)

          result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

          expect(result[:deleted]).to be false
          expect(result[:error]).to include('Rate limited')
          expect(result[:message]).not_to include('not found')
        end
      end

      it 'reports malformed list data as an error instead of absence' do
        allow(strategy).to receive(:get_request).and_return({ success: true, data: {} })
        expect(strategy).not_to receive(:delete_request)

        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:error]).to include('Invalid domain authentication list')
        expect(result[:message]).not_to include('not found')
      end

      it 'reports transport failures as errors' do
        allow(strategy).to receive(:get_request).and_raise(Net::ReadTimeout)
        expect(strategy).not_to receive(:delete_request)

        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:error]).to include('Net::ReadTimeout')
      end
    end

    context 'with invalid from_address' do
      let(:mailer_config) { double('MailerConfig', from_address: '') }

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
      end
    end

    context 'with missing api_key' do
      let(:credentials) { { 'api_key' => nil } }

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('required')
      end
    end
  end

  describe '#strategy_name' do
    it 'returns sendgrid' do
      expect(strategy.strategy_name).to eq('sendgrid')
    end
  end

  describe '#supports_provisioning?' do
    it 'returns true' do
      expect(strategy.supports_provisioning?).to be true
    end
  end

  describe 'HTTP client methods' do
    describe '#build_dns_records (private)' do
      it 'converts SendGrid DNS response to standard format' do
        data = {
          'dns' => {
            'mail_cname' => { 'host' => 'em.example.com', 'type' => 'cname', 'data' => 'sendgrid.net' },
            'dkim1' => { 'host' => 's1._domainkey.example.com', 'type' => 'cname', 'data' => 'dkim.sendgrid.net' },
          },
        }

        records = strategy.send(:build_dns_records, data)

        expect(records).to contain_exactly(
          { type: 'CNAME', name: 'em.example.com', value: 'sendgrid.net', purpose: 'mail_cname' },
          { type: 'CNAME', name: 's1._domainkey.example.com', value: 'dkim.sendgrid.net', purpose: 'dkim1' }
        )
      end

      it 'handles empty dns hash' do
        records = strategy.send(:build_dns_records, { 'dns' => {} })
        expect(records).to eq([])
      end

      it 'handles missing dns key' do
        records = strategy.send(:build_dns_records, {})
        expect(records).to eq([])
      end
    end

    describe '#all_records_valid? (private)' do
      it 'returns true when all records are valid' do
        results = {
          'mail_cname' => { 'valid' => true },
          'dkim1' => { 'valid' => true },
        }

        expect(strategy.send(:all_records_valid?, results)).to be true
      end

      it 'returns false when any record is invalid' do
        results = {
          'mail_cname' => { 'valid' => true },
          'dkim1' => { 'valid' => false },
        }

        expect(strategy.send(:all_records_valid?, results)).to be false
      end

      it 'returns false for nil input' do
        expect(strategy.send(:all_records_valid?, nil)).to be false
      end

      it 'returns false for non-hash input' do
        expect(strategy.send(:all_records_valid?, 'string')).to be false
      end
    end

    describe '#extract_error_message (private)' do
      it 'extracts message from errors array' do
        data = { 'errors' => [{ 'message' => 'Domain conflict' }] }
        expect(strategy.send(:extract_error_message, data)).to eq('Domain conflict')
      end

      it 'extracts error string' do
        data = { 'error' => 'Rate limited' }
        expect(strategy.send(:extract_error_message, data)).to eq('Rate limited')
      end

      it 'returns nil for empty errors array' do
        data = { 'errors' => [] }
        expect(strategy.send(:extract_error_message, data)).to be_nil
      end

      it 'returns nil for non-hash input' do
        expect(strategy.send(:extract_error_message, 'string')).to be_nil
      end
    end
  end

  describe '#find_domain_id (private, paginated)' do
    let(:api_key) { 'SG.test-api-key-example' }

    def make_domains(count, start_id: 1, domain_prefix: 'other')
      count.times.map do |i|
        { 'id' => start_id + i, 'domain' => "#{domain_prefix}#{start_id + i}.com" }
      end
    end

    context 'when domain is found on the first page' do
      before do
        domains = make_domains(3) + [{ 'id' => 42, 'domain' => 'example.com' }]
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: domains })
      end

      it 'returns the domain id' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to eq(42)
      end

      it 'makes only one API call' do
        strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(strategy).to have_received(:get_request).once
      end
    end

    context 'when domain is found on the second page' do
      before do
        # First page: 50 domains, none matching
        page1 = make_domains(50, start_id: 1)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: page1 })

        # Second page: fewer than 50, includes the target
        page2 = make_domains(5, start_id: 51) + [{ 'id' => 99, 'domain' => 'example.com' }]
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
          .and_return({ success: true, data: page2 })
      end

      it 'returns the domain id from the second page' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to eq(99)
      end

      it 'makes exactly two API calls' do
        strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(strategy).to have_received(:get_request).twice
      end
    end

    context 'when domain is not found across all pages' do
      before do
        # First page: exactly 50 (triggers next page)
        page1 = make_domains(50, start_id: 1)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: page1 })

        # Second page: fewer than 50 (last page, no match)
        page2 = make_domains(10, start_id: 51)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
          .and_return({ success: true, data: page2 })
      end

      it 'returns nil' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to be_nil
      end
    end

    context 'when first page has fewer than limit results (single page)' do
      before do
        domains = make_domains(3)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: domains })
      end

      it 'returns nil without requesting a second page' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to be_nil
        expect(strategy).to have_received(:get_request).once
      end
    end

    context 'when first page returns exactly limit results (boundary)' do
      before do
        page1 = make_domains(50, start_id: 1)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: page1 })

        # Second page is empty
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
          .and_return({ success: true, data: [] })
      end

      it 'requests a second page since size == limit' do
        strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(strategy).to have_received(:get_request).twice
      end

      it 'returns nil when second page is empty' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to be_nil
      end
    end

    context 'when API returns failure on first request' do
      before do
        allow(strategy).to receive(:get_request)
          .and_return({ success: false, error: 'Unauthorized', status_code: 401 })
      end

      it 'raises an API error instead of reporting absence' do
        expect { strategy.send(:find_domain_id, 'example.com', api_key: api_key) }
          .to raise_error(described_class::APIError, 'Unauthorized') { |error| expect(error.status_code).to eq(401) }
      end
    end

    context 'when API returns failure on second page' do
      before do
        page1 = make_domains(50, start_id: 1)
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: page1 })

        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
          .and_return({ success: false, error: 'Rate limited' })
      end

      it 'raises an API error instead of reporting absence' do
        expect { strategy.send(:find_domain_id, 'example.com', api_key: api_key) }
          .to raise_error(described_class::APIError, 'Rate limited')
      end
    end

    context 'when API returns non-array data' do
      before do
        allow(strategy).to receive(:get_request)
          .and_return({ success: true, data: { 'error' => 'unexpected format' } })
      end

      it 'raises an API error instead of reporting absence' do
        expect { strategy.send(:find_domain_id, 'example.com', api_key: api_key) }
          .to raise_error(described_class::APIError, /Invalid domain authentication list/)
      end
    end

    context 'when API returns empty first page' do
      before do
        allow(strategy).to receive(:get_request)
          .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
          .and_return({ success: true, data: [] })
      end

      it 'returns nil without requesting more pages' do
        result = strategy.send(:find_domain_id, 'example.com', api_key: api_key)

        expect(result).to be_nil
        expect(strategy).to have_received(:get_request).once
      end
    end
  end

  describe '#domain_authentications (private, paginated)' do
    let(:api_key) { 'SG.test-api-key-example' }

    def make_domains(count, start_id: 1)
      count.times.map { |i| { 'id' => start_id + i, 'domain' => "other#{start_id + i}.com" } }
    end

    it 'concatenates every page and matches entries like find_domain_id' do
      page1 = make_domains(50, start_id: 1)
      page2 = make_domains(4, start_id: 51) + [{ 'id' => 99, 'domain' => 'example.com' }]
      allow(strategy).to receive(:get_request)
        .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
        .and_return({ success: true, data: page1 })
      allow(strategy).to receive(:get_request)
        .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
        .and_return({ success: true, data: page2 })

      listing = strategy.send(:domain_authentications, api_key: api_key)

      expect(listing.size).to eq(55)
      expect(strategy).to have_received(:get_request).twice
      expect(strategy.send(:domain_authentication_id, listing, 'example.com')).to eq(99)
      expect(strategy.send(:domain_authentication_id, listing, 'other7.com')).to eq(7)
      expect(strategy.send(:domain_authentication_id, listing, 'missing.com')).to be_nil
    end

    it 'raises, never returning a partial list, when a later page fails' do
      allow(strategy).to receive(:get_request)
        .with('/whitelabel/domains?limit=50&offset=0', api_key: api_key)
        .and_return({ success: true, data: make_domains(50) })
      allow(strategy).to receive(:get_request)
        .with('/whitelabel/domains?limit=50&offset=50', api_key: api_key)
        .and_return({ success: false, error: 'HTTP 503' })

      expect { strategy.send(:domain_authentications, api_key: api_key) }.to raise_error(described_class::APIError)
    end

    it 'raises when a page is not a list' do
      allow(strategy).to receive(:get_request).and_return({ success: true, data: { 'errors' => [] } })

      expect { strategy.send(:domain_authentications, api_key: api_key) }.to raise_error(described_class::APIError)
    end
  end

  describe 'lookup evidence and deletion outcomes' do
    [0, 49, 50, 51, 1000].each do |count|
      it "walks #{count} entries with 50-item offsets, including a terminal empty page for exact multiples" do
        entries = count.times.map { |i| { 'id' => i + 1, 'domain' => "other#{i}.com" } }
        calls = []
        allow(strategy).to receive(:get_request) do |path, api_key:|
          offset = path.split('offset=').last.to_i
          calls << offset
          { success: true, data: entries.slice(offset, 50) || [] }
        end
        expect(strategy.send(:domain_authentications, api_key: 'key')).to eq(entries)
        expect(calls).to eq((0..(count / 50)).map { |i| i * 50 })
        calls.clear
        expect(strategy.send(:find_domain_id, 'missing.com', api_key: 'key')).to be_nil
        expect(calls).to eq((0..(count / 50)).map { |i| i * 50 })
      end
    end

    [nil, 'bad', {}, { 'domain' => '' }, { 'id' => 1 },
     { 'domain' => 'example.com' }, { 'domain' => 'other.com', 'id' => nil },
     { 'domain' => 'example.com', 'id' => '' }, { 'domain' => 'example.com', 'id' => false },
     { 'domain' => 'example.com', 'id' => -1 }, { 'domain' => 'example.com', 'id' => '1/path' }].each do |entry|
      it "rejects malformed entry #{entry.inspect} in both lookup paths" do
        allow(strategy).to receive(:get_request).and_return(success: true, data: [entry])
        expect { strategy.send(:find_domain_id, 'example.com', api_key: 'key') }.to raise_error(described_class::APIError)
        expect { strategy.send(:domain_authentications, api_key: 'key') }.to raise_error(described_class::APIError)
        expect { strategy.send(:domain_authentication_id, [entry], 'example.com') }.to raise_error(described_class::APIError)
        expect(strategy).not_to receive(:delete_request)
        expect(strategy).not_to receive(:post_request)
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)
        expect(result).to include(outcome: :failed, deleted: false, error: a_string_matching(/\S/))
        expect(strategy.check_provider_verification_status(mailer_config, credentials: credentials)).to include(verified: nil, status: 'error')
      end
    end

    it 'allows an individual early match but requires a complete inventory' do
      page = 50.times.map { |i| { 'id' => i + 1, 'domain' => i.zero? ? 'example.com' : "other#{i}.com" } }
      allow(strategy).to receive(:get_request).with('/whitelabel/domains?limit=50&offset=0', api_key: 'key').and_return(success: true, data: page)
      allow(strategy).to receive(:get_request).with('/whitelabel/domains?limit=50&offset=50', api_key: 'key').and_return(success: true, data: [{ 'domain' => 'example.com' }])
      expect(strategy.send(:find_domain_id, 'example.com', api_key: 'key')).to eq(1)
      expect(strategy).to have_received(:get_request).once
      expect { strategy.send(:domain_authentications, api_key: 'key') }.to raise_error(described_class::APIError)
    end

    it 'does not accept an early match on a malformed page' do
      allow(strategy).to receive(:get_request).and_return(success: true, data: [{ 'id' => 1, 'domain' => 'example.com' }, {}])
      expect { strategy.send(:find_domain_id, 'example.com', api_key: 'key') }.to raise_error(described_class::APIError)
    end

    it 'returns a plain absent result only for a validated empty listing' do
      allow(strategy).to receive(:get_request).and_return(success: true, data: [])
      result = strategy.delete_sender_identity(mailer_config, credentials: credentials)
      expect(result.class).to eq(Hash)
      expect(result).to match(outcome: :absent, deleted: false, message: a_string_matching(/\S/), error: nil)
    end

    it 'retains the configured domain_id override and reports actual deletion' do
      expect(strategy).not_to receive(:get_request)
      expect(strategy).to receive(:delete_request).with('/whitelabel/domains/789', api_key: credentials['api_key']).and_return(success: true, data: {})
      expect(strategy.delete_sender_identity(mailer_config, credentials: credentials.merge('domain_id' => 789)))
        .to match(outcome: :deleted, deleted: true, message: a_string_matching(/\S/), error: nil)
    end

    [nil, '', '   '].each do |message|
      it "keeps a nonempty error for rejected deletion #{message.inspect}" do
        allow(strategy).to receive(:get_request).and_return(success: true, data: [{ 'domain' => 'example.com', 'id' => 123 }])
        allow(strategy).to receive(:delete_request).and_return(success: false, error: message)
        expect(strategy.delete_sender_identity(mailer_config, credentials: credentials))
          .to include(outcome: :failed, deleted: false, message: a_string_matching(/\S/), error: a_string_matching(/\S/))
      end
    end

    ['', '   '].each do |message|
      it "keeps a nonempty error for exception #{message.inspect}" do
        allow(strategy).to receive(:get_request).and_raise(StandardError.new(message))
        expect(strategy).not_to receive(:delete_request)
        expect(strategy.delete_sender_identity(mailer_config, credentials: credentials))
          .to include(outcome: :failed, deleted: false, message: a_string_matching(/\S/), error: a_string_matching(/\S/))
      end
    end
  end

  describe 'APIError' do
    it 'carries status_code and response_body' do
      error = described_class::APIError.new(
        'test error',
        status_code: 401,
        response_body: '{"error":"unauthorized"}'
      )

      expect(error.status_code).to eq(401)
      expect(error.response_body).to eq('{"error":"unauthorized"}')
      expect(error.message).to eq('test error')
    end
  end
end
