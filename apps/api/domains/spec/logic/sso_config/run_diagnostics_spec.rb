# apps/api/domains/spec/logic/sso_config/run_diagnostics_spec.rb
#
# frozen_string_literal: true

# Unit tests for RunDiagnostics: checks against the SAVED SsoConfig record,
# one check per layer (stored_configuration, discovery, certificate,
# credential), with an overall verdict.
#
# Hermetic: the stored record is an instance_double, the discovery fetcher is
# replaced at its seam (DiscoveryCheck#discovery_fetcher), and the Entra token
# endpoint is stubbed with WebMock so the real EntraCredentialProbe runs
# against it. No live DNS or network.
#
# Run:
#   tests/lanes/run unit --only apps/api/domains/spec/logic/sso_config/run_diagnostics_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'
require_relative '../../../../../web/auth/spec/support/domain_sso_test_fixtures'

RSpec.describe DomainsAPI::Logic::SsoConfig::RunDiagnostics do
  include DomainSsoTestFixtures

  let(:tenant_id) { '12345678-1234-1234-1234-123456789abc' }
  let(:client_id) { 'stored-client-id' }
  let(:secret) { 'stored+secret%with:punctuation' }
  let(:issuer) { '' }
  let(:provider_type) { 'entra_id' }
  let(:validation_errors) { [] }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:private_description) { 'private description Trace ID: 11111111-aaaa Correlation ID: 22222222-bbbb' }

  let(:owner) do
    instance_double(Onetime::Customer, custid: 'owner123', objid: 'owner123', extid: 'ext-owner123', anonymous?: false)
  end

  let(:custom_domain) do
    instance_double(Onetime::CustomDomain, identifier: 'domain123', extid: 'ext-domain123', display_domain: 'example.com')
  end

  let(:strategy_result) do
    double('StrategyResult', session: { 'authenticated' => true }, user: owner, authenticated?: true, metadata: {})
  end

  # A Familia concealed value: #reveal yields the plaintext to the block.
  def concealed(value)
    double('ConcealedString').tap do |c|
      allow(c).to receive(:reveal) { |&blk| blk.call(value) }
    end
  end

  let(:sso_config) do
    instance_double(
      Onetime::CustomDomain::SsoConfig,
      provider_type: provider_type,
      validation_errors: validation_errors,
      tenant_id: tenant_id,
      issuer: issuer,
      token_endpoint_auth_method: '',
      client_id: concealed(client_id),
      client_secret: concealed(secret),
      updated: '1760000000',
    )
  end

  let(:logic) { described_class.new(strategy_result, { 'extid' => 'ext-domain123' }) }

  # Everything OT logs during a run, for the "never leaks" assertions.
  let(:logged) { [] }

  before do
    %i[info ld le li].each do |level|
      allow(OT).to receive(level) { |*args| logged << args.inspect }
    end

    allow(logic).to receive(:authorize_domain_sso!) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
    end
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain123').and_return(sso_config)
  end

  # ── discovery seam ──────────────────────────────────────────────────────

  let(:discovery_fetcher) { instance_double(Onetime::SsoProvider::DiscoveryFetcher, max_bytes: 65_536) }

  def discovery_result(status, body: nil, error: nil, http_status: nil)
    Onetime::SsoProvider::DiscoveryFetcher::Result.new(
      status: status, url: 'https://idp.example.com/.well-known/openid-configuration',
      http_status: http_status, http_message: nil, content_type: 'application/json', body: body, error: error,
    )
  end

  def discovery_document(discovered_issuer)
    {
      issuer: discovered_issuer,
      authorization_endpoint: "#{discovered_issuer}/authorize",
      token_endpoint: "#{discovered_issuer}/token",
      jwks_uri: "#{discovered_issuer}/jwks",
      token_endpoint_auth_methods_supported: %w[client_secret_post client_secret_basic],
    }.to_json
  end

  def stub_discovery(result)
    allow(logic).to receive(:discovery_fetcher).and_return(discovery_fetcher)
    allow(discovery_fetcher).to receive(:fetch).and_return(result)
  end

  def stub_discovery_ok(discovered_issuer = "https://login.microsoftonline.com/#{tenant_id}/v2.0")
    stub_discovery(discovery_result(:ok, body: discovery_document(discovered_issuer), http_status: 200))
  end

  # ── token endpoint ──────────────────────────────────────────────────────

  def accept_credentials
    stub_request(:post, token_url).to_return(
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(token_type: 'Bearer', expires_in: 3599, access_token: 'private-access-token'),
    )
  end

  def refuse_credentials(aadsts, status: 401)
    stub_request(:post, token_url).to_return(
      status: status,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(error: 'invalid_client', error_description: "#{aadsts}: #{private_description} #{secret}"),
    )
  end

  def run
    logic.raise_concerns
    logic.process
  end

  def check(result, name)
    result[:checks].find { |c| c[:check] == name } or raise "no check #{name} in #{result[:checks].map { it[:check] }}"
  end

  def expect_no_leak(result)
    everything = [result.inspect, *logged].join("\n")
    expect(everything).not_to include(secret)
    expect(everything).not_to include('private-access-token')
    expect(everything).not_to include('private description')
    expect(everything).not_to include('Correlation ID')
  end

  describe '#raise_concerns' do
    it 'requires an authenticated user' do
      allow(owner).to receive(:anonymous?).and_return(true)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.error_type).to eq(:authentication_required)
      end
      expect(logic).not_to have_received(:authorize_domain_sso!)
    end

    it 'reports a domain without a saved SSO configuration as a missing domain_id form error' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain123').and_return(nil)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.message).to eq('No SSO configuration is saved for this domain')
        expect(error.field).to eq(:domain_id)
        expect(error.error_type).to eq(:missing)
      end
    end

    describe 'per-customer rate limit (SsoDiagnosticsRateLimiter)' do
      it 'charges the acting customer by public id, last, after the record is found' do
        order = []
        allow(logic).to receive(:authorize_domain_sso!) do
          order << :authorize
          logic.instance_variable_set(:@custom_domain, custom_domain)
        end
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain123') do
          order << :find_record
          sso_config
        end
        allow(logic).to receive(:enforce_sso_diagnostics_rate_limit!) { |extid| order << [:charge, extid] }

        logic.raise_concerns

        expect(order).to eq([:authorize, :find_record, [:charge, 'ext-owner123']])
      end

      it 'does not charge a request that has no saved configuration' do
        allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain123').and_return(nil)
        allow(logic).to receive(:enforce_sso_diagnostics_rate_limit!)

        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
        expect(logic).not_to have_received(:enforce_sso_diagnostics_rate_limit!)
      end

      it 'does not charge an anonymous request' do
        allow(owner).to receive(:anonymous?).and_return(true)
        allow(logic).to receive(:enforce_sso_diagnostics_rate_limit!)

        expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
        expect(logic).not_to have_received(:enforce_sso_diagnostics_rate_limit!)
      end

      it 'raises LimitExceeded out of raise_concerns and contacts nobody when the customer is locked' do
        allow(logic).to receive(:enforce_sso_diagnostics_rate_limit!).and_raise(
          Onetime::LimitExceeded.new('Too many saved-configuration checks. Please try again later.',
                                     retry_after: 1234, max_attempts: 10),
        )
        stub_discovery_ok
        accept_credentials

        expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded) do |error|
          expect(error.retry_after).to eq(1234)
          expect(error.max_attempts).to eq(10)
        end
        expect(discovery_fetcher).not_to have_received(:fetch)
        expect(a_request(:post, token_url)).not_to have_been_made
      end

      # The real limiter, against the lane's Valkey: the test config ships it
      # disabled, so it is enabled here in-process with a cap of one, which
      # makes the second run the locked one.
      it 'enforces through the real module when enabled: the run over the cap is refused' do
        saved_conf = YAML.load(YAML.dump(OT.conf))
        new_conf   = YAML.load(YAML.dump(OT.conf))
        ((new_conf['features'] ||= {})['organizations'] ||= {})['sso_diagnostics_rate_limit'] =
          { 'enabled' => true, 'max_per_customer' => 1, 'window' => 60, 'lockout' => 60 }
        OT.send(:conf=, new_conf)
        redis = Onetime::Customer.dbclient
        redis.del('sso_diagnostics:attempts:ext-owner123', 'sso_diagnostics:locked:ext-owner123')
        stub_discovery_ok
        accept_credentials

        begin
          expect(run[:overall]).to eq('passed')

          second = described_class.new(strategy_result, { 'extid' => 'ext-domain123' })
          allow(second).to receive(:authorize_domain_sso!) do
            second.instance_variable_set(:@custom_domain, custom_domain)
          end
          expect { second.raise_concerns }.to raise_error(Onetime::LimitExceeded)
          expect(a_request(:post, token_url)).to have_been_made.once
        ensure
          redis.del('sso_diagnostics:attempts:ext-owner123', 'sso_diagnostics:locked:ext-owner123')
          OT.send(:conf=, saved_conf)
        end
      end
    end
  end

  describe 'response envelope' do
    before do
      stub_discovery_ok
      accept_credentials
    end

    it 'reports the user, provider, UTC timestamp, revision and ordered checks' do
      result = run

      expect(result[:user_id]).to eq('ext-owner123')
      expect(result[:provider_type]).to eq('entra_id')
      expect(result[:checked_at]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      expect(result[:configuration_revision]).to eq('1760000000')
      expect(result[:checks].map { it[:check] }).to eq(%w[stored_configuration discovery credential])
      expect(result[:checks]).to all(include(:check, :status, :message, :details))
    end

    it 'logs one info line with the domain, provider, overall and per-check statuses, and nothing sensitive' do
      run

      line = logged.find { it.include?('[RunDiagnostics] Saved configuration check') }
      expect(line).to include('ext-domain123')
      expect(line).to include(':overall => "passed"').or include('overall: "passed"')
      expect(line).to include('"credential" => "passed"').or include('"credential"=>"passed"')
      expect_no_leak(run)
    end
  end

  describe 'stored_configuration' do
    context 'when validation_errors is not empty' do
      let(:validation_errors) { ['client_secret is required', 'tenant_id is required for Entra ID provider'] }

      it 'fails with the error list and skips every later check without touching the network' do
        probe_stub = stub_request(:post, token_url)
        allow(logic).to receive(:discovery_fetcher).and_return(discovery_fetcher)
        allow(discovery_fetcher).to receive(:fetch)

        result = run

        expect(check(result, 'stored_configuration')).to include(
          status: 'failed',
          details: { errors: validation_errors },
        )
        %w[discovery credential].each do |name|
          expect(check(result, name)).to include(status: 'skipped', message: 'Fix the stored configuration first')
        end
        expect(result[:overall]).to eq('failed')
        expect(discovery_fetcher).not_to have_received(:fetch)
        expect(probe_stub).not_to have_been_requested
      end
    end

    it 'passes when validation_errors is empty' do
      stub_discovery_ok
      accept_credentials

      expect(check(run, 'stored_configuration')[:status]).to eq('passed')
    end

    context 'when the stored entra_id tenant_id is not a UUID' do
      # SsoConfig#validation_errors only requires tenant_id to be non-empty;
      # a non-UUID value would otherwise reach discovery as a raw path segment
      # while the credential probe refuses it, so the two checks would disagree.
      let(:tenant_id) { 'contoso.onmicrosoft.com' }

      it 'fails with a tenant_id error and skips discovery and credential without touching the network' do
        probe_stub = stub_request(:post, /login\.microsoftonline\.com/)
        allow(logic).to receive(:discovery_fetcher).and_return(discovery_fetcher)
        allow(discovery_fetcher).to receive(:fetch)

        result = run

        expect(check(result, 'stored_configuration')).to include(
          status: 'failed',
          details: { errors: ['tenant_id must be a valid UUID for Entra ID provider'] },
        )
        %w[discovery credential].each do |name|
          expect(check(result, name)[:status]).to eq('skipped')
        end
        expect(result[:overall]).to eq('failed')
        expect(discovery_fetcher).not_to have_received(:fetch)
        expect(probe_stub).not_to have_been_requested
      end
    end

    context 'when an oidc record has no tenant_id' do
      let(:provider_type) { 'oidc' }
      let(:issuer) { 'https://idp.example.com' }
      let(:tenant_id) { '' }

      it 'does not apply the Entra tenant_id shape check' do
        allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
        stub_discovery_ok(issuer)

        expect(check(run, 'stored_configuration')[:status]).to eq('passed')
      end
    end
  end

  describe 'discovery (entra_id, from the stored tenant_id)' do
    before { accept_credentials }

    it 'fetches the tenant discovery document and reports the same details Test Connection does' do
      stub_discovery_ok

      discovery = check(run, 'discovery')

      expect(discovery_fetcher).to have_received(:fetch)
        .with("https://login.microsoftonline.com/#{tenant_id}/v2.0/.well-known/openid-configuration")
      expect(discovery[:status]).to eq('passed')
      expect(discovery[:details]).to include(
        issuer: "https://login.microsoftonline.com/#{tenant_id}/v2.0",
        token_endpoint_auth_methods_supported: %w[client_secret_post client_secret_basic],
        token_endpoint_auth_method_supported: nil,
      )
    end

    it 'fails on a missing document' do
      stub_discovery(discovery_result(:not_found, http_status: 404))

      result = run

      expect(check(result, 'discovery')).to include(status: 'failed')
      expect(check(result, 'discovery')[:details]).to include(error_code: 'discovery_not_found', http_status: 404)
      expect(result[:overall]).to eq('failed')
    end

    %i[timeout connection_failed ssl_error].each do |status|
      it "is inconclusive, not failed, when the IdP cannot be reached (#{status})" do
        stub_discovery(discovery_result(status, error: StandardError.new('unreachable')))

        result = run

        expect(check(result, 'discovery')[:status]).to eq('inconclusive')
        expect(check(result, 'discovery')[:details][:error_code]).to eq(status.to_s)
        expect(check(result, 'credential')[:status]).to eq('passed')
        expect(result[:overall]).to eq('inconclusive')
      end
    end
  end

  describe 'credential (entra_id)' do
    before { stub_discovery_ok }

    it 'passes when Entra accepts the stored secret, with the sign-in caveat, and leaks nothing' do
      request = accept_credentials

      result     = run
      credential = check(result, 'credential')

      expect(credential[:status]).to eq('passed')
      expect(credential[:message]).to eq('The identity provider accepted the saved client secret.')
      expect(credential[:details][:note]).to eq(
        'This does not test a full sign-in (redirect URI, user assignment, Conditional Access, claims). ' \
        'Sign in once on the custom domain to confirm.',
      )
      expect(credential[:details]).not_to have_key(:secret_shape)
      expect(result[:overall]).to eq('passed')

      # The STORED credentials, sent the way sign-in sends them (request body).
      expect(request.with do |wire|
        params = URI.decode_www_form(wire.body).to_h
        params.values_at('grant_type', 'client_id', 'client_secret') == ['client_credentials', client_id, secret] &&
          wire.headers['Authorization'].nil?
      end).to have_been_requested.once

      expect_no_leak(result)
    end

    it 'fails with invalid_client_secret on AADSTS7000215 and reports only the code' do
      refuse_credentials('AADSTS7000215')

      result     = run
      credential = check(result, 'credential')

      expect(credential[:status]).to eq('failed')
      expect(credential[:details]).to include(error_code: 'invalid_client_secret', aadsts_code: 'AADSTS7000215', http_status: 401)
      expect(credential[:message]).to include('rejected the saved client secret')
      expect(result[:overall]).to eq('failed')
      expect_no_leak(result)
    end

    it 'fails with client_secret_expired on AADSTS7000222' do
      refuse_credentials('AADSTS7000222')

      credential = check(run, 'credential')

      expect(credential[:status]).to eq('failed')
      expect(credential[:details]).to include(error_code: 'client_secret_expired', aadsts_code: 'AADSTS7000222')
    end

    it 'fails with app_not_found_in_tenant on AADSTS700016' do
      refuse_credentials('AADSTS700016', status: 400)

      expect(check(run, 'credential')[:details]).to include(error_code: 'app_not_found_in_tenant', aadsts_code: 'AADSTS700016')
    end

    it 'is inconclusive with provider_error and the bare AADSTS code on any other Entra error' do
      refuse_credentials('AADSTS50059', status: 400)

      result     = run
      credential = check(result, 'credential')

      expect(credential[:status]).to eq('inconclusive')
      expect(credential[:details]).to include(error_code: 'provider_error', aadsts_code: 'AADSTS50059')
      expect(result[:overall]).to eq('inconclusive')
      expect_no_leak(result)
    end

    it 'is inconclusive with timeout when Entra does not answer' do
      stub_request(:post, token_url).to_timeout

      result = run

      expect(check(result, 'credential')).to include(status: 'inconclusive')
      expect(check(result, 'credential')[:details]).to include(error_code: 'timeout')
      expect(result[:overall]).to eq('inconclusive')
    end

    context 'when the stored secret has the shape of an Entra Secret ID' do
      let(:secret) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }

      it 'adds secret_shape uuid and the Secret ID note, whatever the probe says' do
        refuse_credentials('AADSTS7000215')

        credential = check(run, 'credential')

        expect(credential[:status]).to eq('failed')
        expect(credential[:details][:secret_shape]).to eq('uuid')
        expect(credential[:details][:note]).to include('shape of an Entra Secret ID (a UUID)')
        expect(credential[:details][:note]).to include('Entra needs the secret Value')
      end

      it 'keeps the sign-in caveat ahead of the Secret ID note on a pass' do
        accept_credentials

        note = check(run, 'credential')[:details][:note]

        expect(note).to start_with('This does not test a full sign-in')
        expect(note).to end_with('shown once when the secret is created.')
      end
    end

    context 'when a stored credential cannot be revealed' do
      before do
        allow(sso_config).to receive(:client_secret).and_return(
          double('ConcealedString').tap { |c| allow(c).to receive(:reveal).and_raise(StandardError, "key #{secret}") },
        )
      end

      it 'fails with unreadable_credentials without contacting Entra and without the message' do
        probe_stub = stub_request(:post, token_url)

        result = run

        expect(check(result, 'credential')[:details]).to eq(error_code: 'unreadable_credentials')
        expect(probe_stub).not_to have_been_requested
        expect_no_leak(result)
      end
    end
  end

  describe 'credential (oidc)' do
    let(:provider_type) { 'oidc' }
    let(:issuer) { 'https://idp.example.com' }
    let(:tenant_id) { '' }

    before do
      # DiscoveryCheck#test_oidc_connection runs valid_issuer_host? first
      # (Resolv-based); the fetch itself is stubbed at the fetcher seam.
      allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
      stub_discovery_ok(issuer)
    end

    it 'runs discovery from the stored issuer and reports the credential check as unsupported' do
      token_stub = stub_request(:post, /login\.microsoftonline\.com/)

      result = run

      expect(result[:checks].map { it[:check] }).to eq(%w[stored_configuration discovery credential])
      expect(discovery_fetcher).to have_received(:fetch).with('https://idp.example.com/.well-known/openid-configuration')
      expect(check(result, 'discovery')[:status]).to eq('passed')
      expect(check(result, 'credential')).to include(
        status: 'unsupported',
        message: 'There is no safe credential probe for a generic OIDC provider. ' \
                 'Sign in once on the custom domain to confirm the client secret.',
      )
      expect(result[:overall]).to eq('passed')
      expect(token_stub).not_to have_been_requested
    end

    it 'fails discovery on an issuer mismatch, from the stored issuer' do
      stub_discovery_ok('https://idp.example.com/')

      result = run

      expect(check(result, 'discovery')[:details]).to include(
        error_code: 'issuer_mismatch',
        configured_issuer: 'https://idp.example.com',
        discovery_issuer: 'https://idp.example.com/',
      )
      expect(result[:overall]).to eq('failed')
    end
  end

  describe 'certificate (saml)' do
    let(:provider_type) { 'saml' }
    let(:tenant_id) { '' }
    let(:cert_pem) { DomainSsoTestFixtures.saml_cert_pem }

    before do
      allow(sso_config).to receive(:reveal_saml_field).with(:idp_cert).and_return(cert_pem)
    end

    it 'runs only stored_configuration and certificate, with no network' do
      result = run

      expect(result[:checks].map { it[:check] }).to eq(%w[stored_configuration certificate])
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'passes a certificate inside its validity window and reports subject and expiry' do
      certificate = check(run, 'certificate')

      expect(certificate[:status]).to eq('passed')
      expect(certificate[:details][:certificate_subject]).to be_a(String)
      expect(Time.iso8601(certificate[:details][:certificate_not_after])).to be > Time.now
      expect(certificate[:details][:certificate_expires_in_days]).to be >= 0
      expect(certificate[:details]).not_to have_key(:error_code)
    end

    context 'with an expired certificate' do
      let(:cert_pem) { expired_saml_cert_pem }

      it 'fails with certificate_expired' do
        result = run

        expect(check(result, 'certificate')[:status]).to eq('failed')
        expect(check(result, 'certificate')[:details][:error_code]).to eq('certificate_expired')
        expect(check(result, 'certificate')[:message]).to match(/expired on \d{4}-\d{2}-\d{2}/)
        expect(result[:overall]).to eq('failed')
      end
    end

    context 'with a certificate that is not yet valid' do
      let(:cert_pem) { not_yet_valid_saml_cert_pem }

      it 'fails with certificate_not_yet_valid' do
        expect(check(run, 'certificate')[:details][:error_code]).to eq('certificate_not_yet_valid')
      end
    end

    context 'with a value that is not a certificate' do
      let(:cert_pem) { 'not a certificate' }

      it 'fails with invalid_certificate' do
        expect(check(run, 'certificate')[:details]).to eq(error_code: 'invalid_certificate')
      end
    end
  end

  describe 'overall' do
    it 'is failed when any check failed, even if another is inconclusive' do
      stub_discovery(discovery_result(:timeout, error: StandardError.new('slow')))
      refuse_credentials('AADSTS7000215')

      expect(run[:overall]).to eq('failed')
    end
  end
end
