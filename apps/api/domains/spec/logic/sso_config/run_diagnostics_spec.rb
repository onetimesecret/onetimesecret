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
      enabled?: false,
      credential_fingerprint: 'fingerprint-checked',
    )
  end

  let(:logic) { described_class.new(strategy_result, { 'extid' => 'ext-domain123' }) }

  # Everything OT logs during a run, for the "never leaks" assertions.
  let(:logged) { [] }

  # Every audit event a run records: the kwargs handed to record_security,
  # and the event the real build_event makes of them (redaction applied),
  # which is what the trail stores. Stubbed at the write, so no run writes
  # the lane's trail.
  let(:audited) { [] }
  let(:stored) { [] }

  before do
    %i[info ld le li].each do |level|
      allow(OT).to receive(level) { |*args| logged << args.inspect }
    end
    # An owner, not a colonel: the audit write goes to the security trail.
    allow(logic).to receive(:has_system_role?).with('colonel').and_return(false)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security) do |**kwargs|
      audited << kwargs
      stored << Onetime::ColonelAuditEvent.send(:build_event, **kwargs)
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
    everything = [result.inspect, *logged, *audited.map(&:inspect), *stored.map(&:to_json)].join("\n")
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

  describe 'activation (activate: true)' do
    let(:logic) { described_class.new(strategy_result, { 'extid' => 'ext-domain123', 'activate' => 'true' }) }

    # The record update_for_domain_if re-reads under WATCH.
    let(:stored_fingerprint) { 'fingerprint-checked' }
    let(:stored_enabled) { false }
    let(:stored_record) do
      instance_double(
        Onetime::CustomDomain::SsoConfig,
        credential_fingerprint: stored_fingerprint,
        enabled?: stored_enabled,
      )
    end
    let(:writes) { [] }

    before do
      allow(stored_record).to receive(:enabled=) { |value| writes << [:enabled, value] }
      allow(stored_record).to receive(:updated=) { |value| writes << [:updated, value] }
      # The feature's contract: nil without calling the block when the
      # condition refuses; otherwise the block assigns and the write commits.
      allow(Onetime::CustomDomain::SsoConfig).to receive(:update_for_domain_if)
        .with('domain123', anything) do |_id, condition, &block|
          next nil unless condition.call(stored_record)

          block.call(stored_record)
          [stored_record, nil]
        end
      allow(logic).to receive(:log_sso_change_event)
      stub_discovery_ok
    end

    context 'when every check passes' do
      before { accept_credentials }

      it 'turns the record on and reports it' do
        result = run

        expect(result).to include(overall: 'passed', activation: 'activated', enabled: true)
        expect(writes.assoc(:enabled)).to eq([:enabled, true])
        expect(writes.assoc(:updated)).not_to be_nil
      end

      # configuration_revision ties the result to the record the client
      # loaded; activated_revision lets that client follow the write.
      it 'reports the checked revision and the one the activation wrote' do
        result = run

        expect(result[:configuration_revision]).to eq('1760000000')
        expect(result[:activated_revision]).to eq(writes.assoc(:updated).last.to_s)
        expect(result[:activated_revision]).not_to eq('1760000000')
      end

      it 'emits the same domain_sso_config_enabled change event as PUT/PATCH' do
        run

        expect(logic).to have_received(:log_sso_change_event)
          .with(hash_including(event: :domain_sso_config_enabled, actor: owner, provider_type: 'entra_id'))
      end

      it 'records the activation outcome on the audit event' do
        run

        expect(stored.first['detail']['activation']).to eq('activated')
      end

      it 'fingerprints the record the checks ran against' do
        run

        expect(sso_config).to have_received(:credential_fingerprint).once
      end

      context 'when the credentials changed while the checks ran' do
        let(:stored_fingerprint) { 'fingerprint-after-edit' }

        it 'leaves the record off' do
          result = run

          expect(result).to include(overall: 'passed', activation: 'configuration_changed', enabled: false)
          expect(result).not_to have_key(:activated_revision)
          expect(writes).to be_empty
          expect(logic).not_to have_received(:log_sso_change_event)
        end

        context 'and the stored record was turned on meanwhile' do
          let(:stored_enabled) { true }

          it 'reports the stored state, not the request copy' do
            expect(run).to include(activation: 'configuration_changed', enabled: true)
          end
        end
      end

      context 'when the record is already on' do
        let(:stored_enabled) { true }

        it 'writes nothing and logs no enable event' do
          result = run

          expect(result).to include(activation: 'already_enabled', enabled: true)
          expect(result).not_to have_key(:activated_revision)
          expect(writes).to be_empty
          expect(logic).not_to have_received(:log_sso_change_event)
        end
      end

      context 'when the record was deleted while the checks ran' do
        before do
          allow(Onetime::CustomDomain::SsoConfig).to receive(:update_for_domain_if).and_return(nil)
        end

        it 'reports configuration_changed' do
          expect(run).to include(activation: 'configuration_changed', enabled: false)
        end
      end
    end

    # PUT/PATCH refuse to switch these records on (validate_provider_type,
    # reject_saml_disabled!); a passing check must not either.
    context 'when the stored provider type is no longer supported' do
      let(:provider_type) { 'github' }

      it 'refuses to activate a passing run' do
        result = run

        expect(result).to include(overall: 'passed', activation: 'not_permitted', enabled: false)
        expect(result).not_to have_key(:activated_revision)
        expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:update_for_domain_if)
      end
    end

    context 'when a saml record passes while SAML is off on the install' do
      let(:provider_type) { 'saml' }
      let(:tenant_id) { '' }

      before do
        allow(sso_config).to receive(:reveal_saml_field).with(:idp_cert).and_return(DomainSsoTestFixtures.saml_cert_pem)
        allow(Onetime::SsoProvider::Saml).to receive(:enabled?).and_return(false)
      end

      it 'refuses to activate' do
        result = run

        expect(result).to include(overall: 'passed', activation: 'not_permitted', enabled: false)
        expect(result).not_to have_key(:activated_revision)
        expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:update_for_domain_if)
      end

      it 'activates once SAML is on' do
        allow(Onetime::SsoProvider::Saml).to receive(:enabled?).and_return(true)

        expect(run).to include(overall: 'passed', activation: 'activated', enabled: true)
      end
    end

    context 'when a check fails' do
      before { refuse_credentials('AADSTS7000215') }

      it 'does not activate' do
        result = run

        expect(result).to include(overall: 'failed', activation: 'not_passed', enabled: false)
        expect(result).not_to have_key(:activated_revision)
        expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:update_for_domain_if)
      end
    end

    context 'when a check is inconclusive' do
      before do
        stub_discovery(discovery_result(:timeout, error: StandardError.new('unreachable')))
        accept_credentials
      end

      it 'does not activate' do
        result = run

        expect(result).to include(overall: 'inconclusive', activation: 'not_passed', enabled: false)
        expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:update_for_domain_if)
      end
    end

    context 'when activate is not sent' do
      let(:logic) { described_class.new(strategy_result, { 'extid' => 'ext-domain123' }) }

      before { accept_credentials }

      it 'reports not_requested, writes nothing and does not fingerprint' do
        result = run

        expect(result).to include(overall: 'passed', activation: 'not_requested', enabled: false)
        expect(result).not_to have_key(:activated_revision)
        expect(Onetime::CustomDomain::SsoConfig).not_to have_received(:update_for_domain_if)
        expect(sso_config).not_to have_received(:credential_fingerprint)
      end
    end
  end

  describe 'audit trail (sso.diagnostics_run)' do
    # The stored detail, as the trail keeps it: string keys, redacted.
    def stored_detail
      stored.first['detail']
    end

    def stored_check(name)
      stored_detail['checks'].find { it['check'] == name }
    end

    it 'records one security-trail event per completed run, never the operator trail' do
      stub_discovery_ok
      accept_credentials

      result = run

      expect(audited.size).to eq(1)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      expect(audited.first).to include(
        actor: owner,
        verb: 'sso.diagnostics_run',
        target: 'domain123',
        result: :success,
      )
      expect(stored.first).to include('actor' => 'ext-owner123', 'target' => 'domain123', 'result' => 'success')
      expect(stored_detail).to include(
        'display_domain' => 'example.com',
        'provider_type' => 'entra_id',
        'overall' => 'passed',
        'checked_at' => result[:checked_at],
        'configuration_revision' => '1760000000',
        'checks' => [
          { 'check' => 'stored_configuration', 'status' => 'passed' },
          { 'check' => 'discovery', 'status' => 'passed' },
          { 'check' => 'credential', 'status' => 'passed' },
        ],
      )
    end

    it 'stores a failed verdict as result failure with the bare error and AADSTS codes, none redacted' do
      stub_discovery_ok
      refuse_credentials('AADSTS7000215')

      result = run

      expect(result[:overall]).to eq('failed')
      expect(stored.first).to include('verb' => 'sso.diagnostics_run', 'result' => 'failure')
      expect(stored_detail['overall']).to eq('failed')
      expect(stored_check('credential')).to eq(
        'check' => 'credential', 'status' => 'failed',
        'error_code' => 'invalid_client_secret', 'aadsts_code' => 'AADSTS7000215'
      )
      expect(stored.first.to_json).not_to include(Onetime::ColonelAuditEvent::REDACTED)
      expect_no_leak(result)
    end

    it 'stores an inconclusive verdict as result success with overall in the detail' do
      stub_discovery_ok
      stub_request(:post, token_url).to_timeout

      result = run

      expect(result[:overall]).to eq('inconclusive')
      expect(stored.first['result']).to eq('success')
      expect(stored_detail['overall']).to eq('inconclusive')
      expect(stored_check('credential')).to include('status' => 'inconclusive', 'error_code' => 'timeout')
    end

    context 'when the stored secret has the shape of an Entra Secret ID' do
      let(:secret) { 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' }

      it 'keeps the shape flag through the trail redaction pass' do
        stub_discovery_ok
        refuse_credentials('AADSTS7000215')

        run

        expect(stored_check('credential')).to include('shape' => 'uuid')
        expect(stored.first.to_json).not_to include(Onetime::ColonelAuditEvent::REDACTED)
      end
    end

    context 'when the stored configuration fails' do
      let(:validation_errors) { ['client_secret is required', 'tenant_id is required for Entra ID provider'] }

      it 'stores the later checks as skipped and never the validation messages' do
        run

        expect(stored.first['result']).to eq('failure')
        expect(stored_detail['checks']).to eq(
          [
            { 'check' => 'stored_configuration', 'status' => 'failed' },
            { 'check' => 'discovery', 'status' => 'skipped' },
            { 'check' => 'credential', 'status' => 'skipped' },
          ],
        )
        expect(stored.first.to_json).not_to include('is required')
        expect(stored.first.to_json).not_to include(Onetime::ColonelAuditEvent::REDACTED)
      end
    end

    context 'for an oidc record' do
      let(:provider_type) { 'oidc' }
      let(:issuer) { 'https://idp.example.com' }
      let(:tenant_id) { '' }

      before do
        allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
        stub_discovery_ok(issuer)
      end

      it 'stores discovery and the unsupported credential check, none redacted' do
        run

        expect(stored.first['result']).to eq('success')
        expect(stored_detail).to include('provider_type' => 'oidc', 'overall' => 'passed')
        expect(stored_detail['checks']).to eq(
          [
            { 'check' => 'stored_configuration', 'status' => 'passed' },
            { 'check' => 'discovery', 'status' => 'passed' },
            { 'check' => 'credential', 'status' => 'unsupported' },
          ],
        )
        expect(stored.first.to_json).not_to include(Onetime::ColonelAuditEvent::REDACTED)
      end

      it 'stores an issuer mismatch as the bare code, without either issuer' do
        stub_discovery_ok('https://idp.example.com/')

        run

        expect(stored.first['result']).to eq('failure')
        expect(stored_check('discovery')).to eq(
          'check' => 'discovery', 'status' => 'failed', 'error_code' => 'issuer_mismatch',
        )
        expect(stored.first.to_json).not_to include('idp.example.com')
      end
    end

    context 'for a saml record' do
      let(:provider_type) { 'saml' }
      let(:tenant_id) { '' }
      let(:cert_pem) { DomainSsoTestFixtures.saml_cert_pem }

      before do
        allow(sso_config).to receive(:reveal_saml_field).with(:idp_cert).and_return(cert_pem)
      end

      it 'stores the certificate check without the certificate subject or expiry' do
        result = run

        expect(stored.first['result']).to eq('success')
        expect(stored_detail).to include('provider_type' => 'saml', 'overall' => 'passed')
        expect(stored_detail['checks']).to eq(
          [
            { 'check' => 'stored_configuration', 'status' => 'passed' },
            { 'check' => 'certificate', 'status' => 'passed' },
          ],
        )
        expect(stored.first.to_json).not_to include(check(result, 'certificate')[:details][:certificate_subject])
        expect(stored.first.to_json).not_to include(Onetime::ColonelAuditEvent::REDACTED)
      end

      context 'with an expired certificate' do
        let(:cert_pem) { expired_saml_cert_pem }

        it 'stores result failure with the bare certificate_expired code' do
          run

          expect(stored.first['result']).to eq('failure')
          expect(stored_check('certificate')).to eq(
            'check' => 'certificate', 'status' => 'failed', 'error_code' => 'certificate_expired',
          )
        end
      end
    end

    it 'never copies a check message into the event' do
      stub_discovery_ok
      refuse_credentials('AADSTS7000215')

      run

      expect(stored.size).to eq(1)
      expect(stored.first.to_json).not_to include('rejected the saved client secret')
    end

    # A colonel passes the entitlement check on any domain, and that run is
    # operator activity.
    it 'records a colonel run on the operator trail' do
      allow(logic).to receive(:has_system_role?).with('colonel').and_return(true)
      allow(Onetime::ColonelAuditEvent).to receive(:record) { |**kwargs| audited << kwargs }
      stub_discovery_ok
      accept_credentials

      run

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
      expect(audited.size).to eq(1)
      expect(audited.first).to include(verb: 'sso.diagnostics_run', result: :success)
    end

    it 'does not record when the run is refused before any check' do
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain123').and_return(nil)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError)
      expect(audited).to be_empty
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
        probe_stub = stub_request(:post, %r{\Ahttps://login\.microsoftonline\.com/})
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

    # validation_errors exempts an oidc secret (public clients) and so says
    # nothing when a stored one will not decrypt; build_oidc_options reveals
    # it and raises at sign-in.
    context 'when a stored oidc client_secret cannot be revealed' do
      let(:provider_type) { 'oidc' }
      let(:issuer) { 'https://idp.example.com' }
      let(:tenant_id) { '' }

      before do
        allow(sso_config).to receive(:client_secret).and_return(
          double('ConcealedString').tap { |c| allow(c).to receive(:reveal).and_raise(StandardError, "key #{secret}") },
        )
      end

      it 'fails as unreadable and skips discovery, without the exception message' do
        allow(logic).to receive(:discovery_fetcher).and_return(discovery_fetcher)
        allow(discovery_fetcher).to receive(:fetch)

        result = run

        expect(check(result, 'stored_configuration')).to include(
          status: 'failed',
          details: { errors: ['client_secret cannot be read (re-enter the value)'] },
        )
        expect(check(result, 'discovery')[:status]).to eq('skipped')
        expect(result[:overall]).to eq('failed')
        expect(discovery_fetcher).not_to have_received(:fetch)
        expect_no_leak(result)
      end
    end

    context 'when an oidc public client has no stored client_secret' do
      let(:provider_type) { 'oidc' }
      let(:issuer) { 'https://idp.example.com' }
      let(:tenant_id) { '' }

      it 'passes' do
        allow(sso_config).to receive(:client_secret).and_return(nil)
        allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
        stub_discovery_ok(issuer)

        expect(check(run, 'stored_configuration')[:status]).to eq('passed')
      end
    end

    context 'when a stored entra_id client_secret cannot be revealed' do
      # What validation_errors says of it: missing, not unreadable.
      let(:validation_errors) { ['client_secret is required'] }

      before do
        allow(sso_config).to receive(:client_secret).and_return(
          double('ConcealedString').tap { |c| allow(c).to receive(:reveal).and_raise(StandardError, "key #{secret}") },
        )
      end

      it 'reports it as unreadable instead of missing' do
        probe_stub = stub_request(:post, token_url)

        result = run

        expect(check(result, 'stored_configuration')[:details]).to eq(
          errors: ['client_secret cannot be read (re-enter the value)'],
        )
        expect(probe_stub).not_to have_been_requested
        expect_no_leak(result)
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

    # stored_configuration reveals it first; this is a reveal that starts
    # failing between that read and the probe's.
    context 'when a stored credential stops revealing after stored_configuration' do
      before do
        reveals = 0
        allow(sso_config).to receive(:client_secret).and_return(
          double('ConcealedString').tap do |c|
            allow(c).to receive(:reveal) do |&blk|
              raise StandardError, "key #{secret}" if (reveals += 1) > 1

              blk.call(secret)
            end
          end,
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
      token_stub = stub_request(:post, %r{\Ahttps://login\.microsoftonline\.com/})

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
