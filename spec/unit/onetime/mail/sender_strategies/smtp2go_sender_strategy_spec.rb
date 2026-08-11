# spec/unit/onetime/mail/sender_strategies/smtp2go_sender_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/sender_strategies/smtp2go_sender_strategy'

RSpec.describe Onetime::Mail::SenderStrategies::Smtp2goSenderStrategy do
  let(:strategy) { described_class.new }
  # Single API key covers both sending and domain provisioning
  let(:credentials) { { 'api_key' => 'api-0123456789abcdef0123456789abcdef', 'base_url' => 'https://api.smtp2go.com/v3' } }
  let(:mailer_config) do
    double('MailerConfig', from_address: 'sender@example.com')
  end
  # Mock the shared Smtp2goClient HTTP client
  let(:mock_client) { instance_double(Onetime::Mail::Smtp2goClient) }

  # Realistic /domain/add and /domain/view entry (SMTP2GO returns selector/value
  # pairs plus per-record verified booleans, wrapped in data.domains)
  let(:domain_entry) do
    {
      'from_master' => false,
      'domain' => {
        'fulldomain' => 'example.com',
        'dkim_selector' => 'em1234',
        'dkim_value' => 'dkim.smtp2go.net',
        'dkim_verified' => false,
        'rpath_selector' => 'bounce',
        'rpath_value' => 'return.smtp2go.net',
        'rpath_verified' => false,
      },
      'trackers' => [
        {
          'fulldomain' => 'track.example.com',
          'cname_value' => 'track.smtp2go.net',
          'cname_verified' => false,
          'enabled' => true,
        },
      ],
    }
  end
  let(:add_response) { { 'domains' => [domain_entry] } }
  let(:view_response) { { 'domains' => [domain_entry] } }

  def api_error(message, status_code:, error_code: nil)
    Onetime::Mail::Smtp2goClient::APIError.new(message, status_code: status_code, error_code: error_code)
  end

  before do
    allow(strategy).to receive(:build_client).and_return(mock_client)
    allow(strategy).to receive(:log_info)
    allow(strategy).to receive(:log_warn)
    allow(strategy).to receive(:log_error)
  end

  describe '#provision_dns_records' do
    context 'with valid from_address' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', {
            'domain' => 'example.com',
            'tracking_subdomain' => 'track',
            'returnpath_subdomain' => 'bounce',
          })
          .and_return(add_response)
      end

      it 'returns success with normalized CNAME records' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records]).to eq([
          { 'type' => 'CNAME', 'name' => 'em1234._domainkey.example.com', 'value' => 'dkim.smtp2go.net', 'status' => 'pending' },
          { 'type' => 'CNAME', 'name' => 'bounce.example.com', 'value' => 'return.smtp2go.net', 'status' => 'pending' },
          { 'type' => 'CNAME', 'name' => 'track.example.com', 'value' => 'track.smtp2go.net', 'status' => 'pending', 'optional' => true },
        ])
      end

      it 'marks only the tracking record optional (advisory, never gates verification)' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        required = result[:dns_records].reject { |r| r['optional'] }
        expect(required.map { |r| r['name'] })
          .to contain_exactly('em1234._domainkey.example.com', 'bounce.example.com')
      end

      it 'returns all three CNAME records (DKIM + Return-Path + Tracking)' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:dns_records].size).to eq(3)
        expect(result[:dns_records].all? { |r| r['type'] == 'CNAME' }).to be true
      end

      it 'constructs the DKIM hostname as <dkim_selector>._domainkey.<fulldomain>' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        dkim_record = result[:dns_records].find { |r| r['name'].include?('_domainkey') }
        expect(dkim_record['name']).to eq('em1234._domainkey.example.com')
        expect(dkim_record['value']).to eq('dkim.smtp2go.net')
      end

      it 'constructs the return-path hostname as <rpath_selector>.<fulldomain>' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        rpath_record = result[:dns_records].find { |r| r['value'] == 'return.smtp2go.net' }
        expect(rpath_record).not_to be_nil
        expect(rpath_record['name']).to eq('bounce.example.com')
      end

      it 'uses the tracker fulldomain for the tracking record' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        tracking_record = result[:dns_records].find { |r| r['value'] == 'track.smtp2go.net' }
        expect(tracking_record).not_to be_nil
        expect(tracking_record['name']).to eq('track.example.com')
      end

      it 'includes provider_data with domain info' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:provider_data]['domain']).to eq('example.com')
        expect(result[:provider_data]['dkim_selector']).to eq('em1234')
        expect(result[:provider_data]['dkim_verified']).to be false
        expect(result[:provider_data]['rpath_selector']).to eq('bounce')
        expect(result[:provider_data]['rpath_verified']).to be false
        expect(result[:provider_data]['trackers']).to eq([
          { 'fulldomain' => 'track.example.com', 'cname_verified' => false, 'enabled' => true },
        ])
      end

      it 'includes identity_id as the domain name (SMTP2GO keys domains by name)' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:identity_id]).to eq('example.com')
      end
    end

    context 'with custom subdomains in credentials' do
      let(:credentials) do
        {
          'api_key' => 'api-0123456789abcdef0123456789abcdef',
          'returnpath_subdomain' => 'mail-bounce',
          'tracking_subdomain' => 'link',
        }
      end

      it 'passes the configured subdomains to /domain/add' do
        allow(mock_client).to receive(:post)
          .with('/domain/add', {
            'domain' => 'example.com',
            'tracking_subdomain' => 'link',
            'returnpath_subdomain' => 'mail-bounce',
          })
          .and_return(add_response)

        result = strategy.provision_dns_records(mailer_config, credentials: credentials)
        expect(result[:success]).to be true
      end
    end

    context 'with blank subdomains in credentials' do
      let(:credentials) do
        {
          'api_key' => 'api-0123456789abcdef0123456789abcdef',
          'returnpath_subdomain' => '',
          'tracking_subdomain' => '   ',
        }
      end

      it 'treats them as absent and uses the defaults' do
        allow(mock_client).to receive(:post)
          .with('/domain/add', {
            'domain' => 'example.com',
            'tracking_subdomain' => 'track',
            'returnpath_subdomain' => 'bounce',
          })
          .and_return(add_response)

        result = strategy.provision_dns_records(mailer_config, credentials: credentials)
        expect(result[:success]).to be true
      end
    end

    context 'with malformed subdomains in credentials' do
      let(:credentials) do
        {
          'api_key' => 'api-0123456789abcdef0123456789abcdef',
          'returnpath_subdomain' => 'bad subdomain!',
          'tracking_subdomain' => 'trk.sub',
        }
      end

      it 'warns and falls back to the defaults' do
        allow(mock_client).to receive(:post)
          .with('/domain/add', {
            'domain' => 'example.com',
            'tracking_subdomain' => 'track',
            'returnpath_subdomain' => 'bounce',
          })
          .and_return(add_response)

        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(strategy).to have_received(:log_warn).twice
      end
    end

    context 'when domain already exists (add fails, view finds it)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('domain already exists', status_code: 400, error_code: 'E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD'))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
      end

      it 'falls back to /domain/view and returns the existing entry' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:dns_records].size).to eq(3)
        expect(result[:identity_id]).to eq('example.com')
      end
    end

    context 'when add fails with a 400 and view does not find the domain' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('invalid payload', status_code: 400, error_code: 'E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD'))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [] })
      end

      it 'surfaces the original add error as a result hash (never raises)' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_400: E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD')
        expect(result[:message]).to include('SMTP2GO API error')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when add fails with an auth error (403)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('Permission denied', status_code: 403, error_code: 'E_ApiResponseCodes.ENDPOINT_PERMISSION_DENIED'))
      end

      it 'surfaces the add error without probing /domain/view' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_403: E_ApiResponseCodes.ENDPOINT_PERMISSION_DENIED')
        expect(mock_client).not_to have_received(:post).with('/domain/view', anything)
      end
    end

    context 'when add fails with a quota/payment error (402)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('Payment required', status_code: 402))
      end

      it 'surfaces the add error without probing /domain/view' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_402: Payment required')
        expect(mock_client).not_to have_received(:post).with('/domain/view', anything)
      end
    end

    context 'when add fails with an "already exists" message on an unlisted status' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('Domain example.com already exists', status_code: 422))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
      end

      it 'probes /domain/view and adopts the matching entry' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:identity_id]).to eq('example.com')
      end
    end

    context 'when the recovery probe lists only another domain' do
      let(:other_entry) do
        {
          'domain' => domain_entry['domain'].merge('fulldomain' => 'other-customer.com'),
          'trackers' => [],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('domain quota exceeded, already at limit', status_code: 400))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [other_entry] })
      end

      it 'never adopts the sole other entry and surfaces the add error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_400: domain quota exceeded, already at limit')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when the probe entry name differs only by case' do
      let(:upcased_entry) do
        {
          'domain' => domain_entry['domain'].merge('fulldomain' => 'EXAMPLE.COM'),
          'trackers' => [],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('domain already exists', status_code: 409))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [upcased_entry] })
      end

      it 'matches the entry case-insensitively' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be true
        expect(result[:identity_id]).to eq('EXAMPLE.COM')
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

    context 'when SMTP2GO API fails (APIError)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_raise(api_error('Internal Server Error', status_code: 500))
      end

      it 'returns error with status code without probing /domain/view' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('http_500: Internal Server Error')
        expect(result[:message]).to include('SMTP2GO API error')
        expect(result[:dns_records]).to eq([])
        expect(mock_client).not_to have_received(:post).with('/domain/view', anything)
      end
    end

    context 'when the domain entry yields no DNS records' do
      let(:bare_entry) { { 'domain' => { 'fulldomain' => 'example.com' }, 'trackers' => [] } }

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_return({ 'domains' => [bare_entry] })
      end

      it 'fails with no_dns_records naming the entry keys' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('no_dns_records')
        expect(result[:message]).to include('["domain", "trackers"]')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when the API returns no domain entry' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/add', hash_including('domain' => 'example.com'))
          .and_return({ 'domains' => [] })
      end

      it 'returns missing_domain_entry error' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('missing_domain_entry')
        expect(result[:dns_records]).to eq([])
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(mock_client).to receive(:post)
          .and_raise(StandardError, 'Network failure')
      end

      it 'returns error with exception message' do
        result = strategy.provision_dns_records(mailer_config, credentials: credentials)

        expect(result[:success]).to be false
        expect(result[:message]).to include('Network failure')
        expect(result[:dns_records]).to eq([])
      end
    end
  end

  describe '#check_provider_verification_status' do
    # Entry with all per-record verified flags true — SMTP2GO has no
    # domain-level verified boolean, so verified is the AND of the DKIM
    # and Return-Path flags (tracking is advisory and never gates).
    let(:verified_entry) do
      {
        'from_master' => false,
        'domain' => domain_entry['domain'].merge('dkim_verified' => true, 'rpath_verified' => true),
        'trackers' => [domain_entry['trackers'].first.merge('cname_verified' => true)],
      }
    end

    before do
      allow(mock_client).to receive(:post)
        .with('/domain/verify', { 'domain' => 'example.com' })
        .and_return({ 'domains' => [domain_entry] })
    end

    context 'when all three records are verified' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [verified_entry] })
      end

      it 'returns verified status' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
        expect(result[:message]).to include('ready for sending')
      end

      it 'includes per-record details' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:details][:dkim_verified]).to be true
        expect(result[:details][:rpath_verified]).to be true
        expect(result[:details][:tracking_verified]).to be true
        expect(result[:details][:domain]).to eq('example.com')
        expect(result[:details][:dns_records].size).to eq(3)
      end

      it 'triggers a provider re-verification before reading status' do
        strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(mock_client).to have_received(:post).with('/domain/verify', { 'domain' => 'example.com' })
      end
    end

    context 'when only some records are verified' do
      let(:partial_entry) do
        {
          'domain' => domain_entry['domain'].merge('dkim_verified' => true, 'rpath_verified' => false),
          'trackers' => [domain_entry['trackers'].first.merge('cname_verified' => false)],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [partial_entry] })
      end

      it 'returns pending status naming the missing record but never Tracking' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('pending')
        expect(result[:message]).to include('Return-Path')
        expect(result[:message]).not_to include('DKIM,')
        expect(result[:message]).not_to include('Tracking')
      end
    end

    context 'when DKIM and Return-Path are verified but tracking is not' do
      let(:tracking_pending_entry) do
        {
          'domain' => domain_entry['domain'].merge('dkim_verified' => true, 'rpath_verified' => true),
          'trackers' => [domain_entry['trackers'].first.merge('cname_verified' => false)],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [tracking_pending_entry] })
      end

      it 'is verified — tracking affects link rewriting, not sender authentication' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
        expect(result[:message]).to include('ready for sending')
      end

      it 'still surfaces the tracker state in details' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:details][:tracking_verified]).to be false
      end
    end

    context 'when verified flags arrive as strings' do
      let(:stringly_entry) do
        {
          'domain' => domain_entry['domain'].merge('dkim_verified' => 'true', 'rpath_verified' => 'true'),
          'trackers' => [domain_entry['trackers'].first.merge('cname_verified' => 'true')],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [stringly_entry] })
      end

      it 'still reads them as verified' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
      end
    end

    context 'when the domain has no trackers' do
      let(:trackerless_entry) do
        {
          'domain' => domain_entry['domain'].merge('dkim_verified' => true, 'rpath_verified' => true),
          'trackers' => [],
        }
      end

      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [trackerless_entry] })
      end

      it 'treats tracking as verified' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:details][:tracking_verified]).to be true
      end
    end

    context 'when the verify trigger fails' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/verify', { 'domain' => 'example.com' })
          .and_raise(api_error('Server Error', status_code: 500))
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [verified_entry] })
      end

      it 'is non-fatal and still reads status from /domain/view' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be true
        expect(result[:status]).to eq('verified')
      end
    end

    context 'when domain is not found' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [] })
      end

      it 'returns not_found status — an authoritative negative, not an error' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be false
        expect(result[:status]).to eq('not_found')
        expect(result[:message]).to include('not found')
      end
    end

    context 'when API returns error (e.g. 401 from a rotated key, or 5xx)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_raise(api_error('Server Error', status_code: 500))
      end

      it 'returns verified: nil — indeterminate, never an authoritative false' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Verification check failed')
      end
    end

    context 'when an unexpected error occurs (transport failure)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_raise(StandardError.new('connection reset'))
      end

      it 'returns verified: nil — indeterminate, never an authoritative false' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('connection reset')
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
      let(:credentials) { { 'api_key' => nil } }

      it 'returns verified: nil — the check could not run' do
        result = strategy.check_provider_verification_status(mailer_config, credentials: credentials)

        expect(result[:verified]).to be_nil
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('SMTP2GO API key is required')
      end
    end
  end

  describe '#delete_sender_identity' do
    context 'when deletion succeeds' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
        allow(mock_client).to receive(:post)
          .with('/domain/remove', { 'domain' => 'example.com' })
          .and_return({})
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('removed')
      end
    end

    context 'when domain not found in view (idempotent)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return({ 'domains' => [] })
      end

      it 'returns deleted true without calling /domain/remove' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('already deleted')
        expect(mock_client).not_to have_received(:post).with('/domain/remove', anything)
      end
    end

    context 'when remove API returns 404 (idempotent)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
        allow(mock_client).to receive(:post)
          .with('/domain/remove', { 'domain' => 'example.com' })
          .and_raise(api_error('Not Found', status_code: 404))
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('already deleted')
      end
    end

    context 'when remove fails with a domain-scoped not-found message (idempotent)' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
        allow(mock_client).to receive(:post)
          .with('/domain/remove', { 'domain' => 'example.com' })
          .and_raise(api_error('Domain does not exist', status_code: 400))
      end

      it 'returns deleted true' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be true
        expect(result[:message]).to include('already deleted')
      end
    end

    context 'when remove fails with an unrelated "not found" message' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
        allow(mock_client).to receive(:post)
          .with('/domain/remove', { 'domain' => 'example.com' })
          .and_raise(api_error('API key not found', status_code: 400))
      end

      it 'does NOT read it as a missing domain' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Deletion failed')
      end
    end

    context 'when API returns error' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_return(view_response)
        allow(mock_client).to receive(:post)
          .with('/domain/remove', { 'domain' => 'example.com' })
          .and_raise(api_error('Forbidden', status_code: 403))
      end

      it 'returns deleted false with error' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Deletion failed')
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(mock_client).to receive(:post)
          .with('/domain/view', { 'domain' => 'example.com' })
          .and_raise(StandardError, 'Connection reset')
      end

      it 'returns deleted false' do
        result = strategy.delete_sender_identity(mailer_config, credentials: credentials)

        expect(result[:deleted]).to be false
        expect(result[:message]).to include('Deletion failed')
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
    it 'returns smtp2go' do
      expect(strategy.strategy_name).to eq('smtp2go')
    end
  end

  describe '#supports_provisioning?' do
    it 'returns true' do
      expect(strategy.supports_provisioning?).to be true
    end
  end

  describe 'not_found_error? (private)' do
    it 'matches 404s and NOT_FOUND/NONEXISTENT codes regardless of message' do
      expect(strategy.send(:not_found_error?, api_error('nope', status_code: 404))).to be true
      expect(strategy.send(:not_found_error?, api_error('nope', status_code: 400, error_code: 'E_NOT_FOUND'))).to be true
      expect(strategy.send(:not_found_error?, api_error('nope', status_code: 400, error_code: 'E_NONEXISTENT_DOMAIN'))).to be true
    end

    it 'matches free-text messages only with domain/sender context' do
      expect(strategy.send(:not_found_error?, api_error('domain not found', status_code: 400))).to be true
      expect(strategy.send(:not_found_error?, api_error('Sender does not exist', status_code: 400))).to be true
      expect(strategy.send(:not_found_error?, api_error('no such domain', status_code: 400))).to be true
      expect(strategy.send(:not_found_error?, api_error('unknown domain', status_code: 400))).to be true
    end

    it 'does not match unrelated not-found wording' do
      expect(strategy.send(:not_found_error?, api_error('API key not found', status_code: 400))).to be false
      expect(strategy.send(:not_found_error?, api_error('template not found', status_code: 400))).to be false
    end
  end

  describe 'build_dns_records (private)' do
    it 'maps status from per-record verified booleans' do
      entry = {
        'domain' => domain_entry['domain'].merge('dkim_verified' => true),
        'trackers' => domain_entry['trackers'],
      }

      records = strategy.send(:build_dns_records, entry)

      dkim = records.find { |r| r['name'].include?('_domainkey') }
      expect(dkim['status']).to eq('verified')
      expect(records.find { |r| r['name'] == 'bounce.example.com' }['status']).to eq('pending')
    end

    it 'marks tracker records optional but not DKIM/Return-Path' do
      records = strategy.send(:build_dns_records, domain_entry)

      tracking = records.find { |r| r['name'] == 'track.example.com' }
      expect(tracking['optional']).to be true
      expect(records.reject { |r| r['optional'] }.map { |r| r['name'] })
        .to contain_exactly('em1234._domainkey.example.com', 'bounce.example.com')
    end

    it 'does not double-append _domainkey when the selector already carries it' do
      entry = {
        'domain' => domain_entry['domain'].merge('dkim_selector' => 'em1234._domainkey'),
        'trackers' => [],
      }

      records = strategy.send(:build_dns_records, entry)

      expect(records.first['name']).to eq('em1234._domainkey.example.com')
    end

    it 'skips trackers without a cname_value' do
      entry = {
        'domain' => domain_entry['domain'],
        'trackers' => [{ 'fulldomain' => 'track.example.com', 'cname_value' => '' }],
      }

      records = strategy.send(:build_dns_records, entry)

      expect(records.size).to eq(2)
      expect(records.none? { |r| r['name'] == 'track.example.com' }).to be true
    end

    it 'returns empty array for a non-Hash entry' do
      expect(strategy.send(:build_dns_records, nil)).to eq([])
      expect(strategy.send(:build_dns_records, 'not a hash')).to eq([])
    end

    it 'omits records whose selector or value is missing' do
      entry = {
        'domain' => {
          'fulldomain' => 'example.com',
          'dkim_selector' => 'em1234',
          'dkim_value' => '',
          'rpath_selector' => '',
          'rpath_value' => 'return.smtp2go.net',
        },
        'trackers' => [],
      }

      expect(strategy.send(:build_dns_records, entry)).to eq([])
    end
  end
end
