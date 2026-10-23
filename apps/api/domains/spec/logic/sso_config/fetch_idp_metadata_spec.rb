# apps/api/domains/spec/logic/sso_config/fetch_idp_metadata_spec.rb
#
# frozen_string_literal: true

# Unit tests for FetchIdpMetadata (POST /api/domains/:extid/sso/metadata):
# the guard order and where the per-customer rate limit is charged, the URL
# check before any fetch, the mapping of every DiscoveryFetcher status onto
# the response vocabulary, the tenant_level_entra_metadata advisory, and that
# the endpoint never touches the SSO record.
#
# Hermetic: the fetcher is replaced at its seam (#metadata_fetcher), the
# save-time DNS check (Resolv.getaddresses) is stubbed to a public address,
# and the documents are built here with certificates minted at runtime. The
# parser itself runs for real (spec/unit/onetime/sso_provider/
# idp_metadata_spec.rb covers it in depth). The one example that exercises
# the real rate limiter uses the lane's Valkey.
#
# Run:
#   tests/lanes/run unit --only apps/api/domains/spec/logic/sso_config/fetch_idp_metadata_spec.rb

require 'base64'
require 'openssl'
require 'securerandom'

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'
require 'onetime/operations/ratelimit/registry'

RSpec.describe DomainsAPI::Logic::SsoConfig::FetchIdpMetadata do
  FETCH_SPEC_NOW = Time.utc(2027, 3, 1, 12, 0, 0)

  around do |example|
    Timecop.freeze(FETCH_SPEC_NOW) { example.run }
  end

  let(:metadata_url) { 'https://idp.example.com/saml/metadata' }
  let(:params) { { 'extid' => 'ext-domain123', 'metadata_url' => "  #{metadata_url}  " } }

  let(:owner) do
    instance_double(Onetime::Customer, custid: 'owner123', objid: 'owner123', extid: 'ext-owner123', anonymous?: false)
  end

  # Strict: the endpoint must not read anything off the domain beyond what
  # authorization already did.
  let(:custom_domain) { instance_double(Onetime::CustomDomain, identifier: 'domain123', extid: 'ext-domain123') }

  let(:strategy_result) do
    double('StrategyResult', session: { 'authenticated' => true }, user: owner, authenticated?: true, metadata: {})
  end

  let(:logic) { build_logic(params) }
  let(:fetcher) { instance_double(Onetime::SsoProvider::DiscoveryFetcher, max_bytes: 262_144) }
  let(:logged) { [] }

  # process_params runs in the constructor, so a different request body
  # needs a new instance. Authorization and the fetcher are stubbed at
  # their seams.
  def build_logic(request_params)
    described_class.new(strategy_result, request_params).tap do |instance|
      allow(instance).to receive(:authorize_domain_sso!) do
        instance.instance_variable_set(:@custom_domain, custom_domain)
      end
      allow(instance).to receive(:metadata_fetcher).and_return(fetcher)
    end
  end

  before do
    %i[info ld le li lw].each do |level|
      allow(OT).to receive(level) { |*args| logged << args.inspect }
    end
    allow(Onetime::SsoProvider::Saml).to receive(:enabled?).and_return(true)
    allow(Resolv).to receive(:getaddresses).and_return(['203.0.113.10'])
    allow(fetcher).to receive(:fetch).and_return(fetched(:ok, body: metadata_document))

    # The endpoint never reads or writes the record.
    %i[find_by_domain_id load update_for_domain! update_for_domain_if create!].each do |method|
      allow(Onetime::CustomDomain::SsoConfig).to receive(method)
    end
  end

  def self.rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def signing_certificate_base64
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = SecureRandom.random_number(2**64)
    cert.subject    = OpenSSL::X509::Name.parse('/CN=fetch-spec-idp.example.com')
    cert.issuer     = cert.subject
    cert.public_key = self.class.rsa_key.public_key
    cert.not_before = FETCH_SPEC_NOW - 86_400
    cert.not_after  = FETCH_SPEC_NOW + (365 * 86_400)
    cert.sign(self.class.rsa_key, OpenSSL::Digest.new('SHA256'))
    Base64.strict_encode64(cert.to_der)
  end

  def metadata_document(entity_id: 'https://idp.example.com/saml/metadata')
    <<~XML
      <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" entityID="#{entity_id}">
        <md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          <md:KeyDescriptor use="signing"><ds:KeyInfo><ds:X509Data><ds:X509Certificate>#{signing_certificate_base64}</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor>
          <md:NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</md:NameIDFormat>
          <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://idp.example.com/saml/post"/>
          <md:SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://idp.example.com/saml/sso"/>
        </md:IDPSSODescriptor>
      </md:EntityDescriptor>
    XML
  end

  def fetched(status, body: nil, error: nil, http_status: nil, http_message: nil, content_type: 'text/xml')
    Onetime::SsoProvider::DiscoveryFetcher::Result.new(
      status: status, url: metadata_url, http_status: http_status, http_message: http_message,
      content_type: content_type, body: body, error: error,
    )
  end

  def run
    logic.raise_concerns
    logic.process
  end

  def expect_no_record_access
    %i[find_by_domain_id load update_for_domain! update_for_domain_if create!].each do |method|
      expect(Onetime::CustomDomain::SsoConfig).not_to have_received(method)
    end
  end

  describe '#raise_concerns' do
    def expect_form_error(field:, error_type:)
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.field).to eq(field)
        expect(error.error_type).to eq(error_type)
      end
    end

    before { allow(logic).to receive(:enforce_sso_metadata_fetch_rate_limit!) }

    it 'requires an authenticated user, before anything else' do
      allow(owner).to receive(:anonymous?).and_return(true)

      expect_form_error(field: :user_id, error_type: :authentication_required)
      expect(logic).not_to have_received(:authorize_domain_sso!)
      expect(logic).not_to have_received(:enforce_sso_metadata_fetch_rate_limit!)
    end

    context 'without a domain id' do
      let(:params) { { 'extid' => '', 'metadata_url' => metadata_url } }

      it 'refuses before authorization' do
        expect_form_error(field: :domain_id, error_type: :missing)
        expect(logic).not_to have_received(:authorize_domain_sso!)
      end
    end

    it 'stops at the ownership / entitlement check' do
      allow(logic).to receive(:authorize_domain_sso!).and_raise(Onetime::Forbidden, 'Not an owner')

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::SsoProvider::Saml).not_to have_received(:enabled?)
      expect(logic).not_to have_received(:enforce_sso_metadata_fetch_rate_limit!)
    end

    it 'refuses while SAML is switched off on the install, naming SAML_ENABLED' do
      allow(Onetime::SsoProvider::Saml).to receive(:enabled?).and_return(false)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.field).to eq(:provider_type)
        expect(error.message).to include('SAML_ENABLED')
      end
      expect(logic).not_to have_received(:enforce_sso_metadata_fetch_rate_limit!)
    end

    ['', '   ', nil].each do |blank|
      context "with metadata_url #{blank.inspect}" do
        let(:params) { { 'extid' => 'ext-domain123', 'metadata_url' => blank } }

        it 'refuses it as missing, uncharged' do
          expect_form_error(field: :metadata_url, error_type: :missing)
          expect(logic).not_to have_received(:enforce_sso_metadata_fetch_rate_limit!)
        end
      end
    end

    it 'runs the guards in order and charges the acting customer by public id, last' do
      order = []
      allow(logic).to receive(:authorize_domain_sso!) do
        order << :authorize
        logic.instance_variable_set(:@custom_domain, custom_domain)
      end
      allow(Onetime::SsoProvider::Saml).to receive(:enabled?) do
        order << :saml_enabled
        true
      end
      allow(logic).to receive(:enforce_sso_metadata_fetch_rate_limit!) { |extid| order << [:charge, extid] }

      logic.raise_concerns

      expect(order).to eq([:authorize, :saml_enabled, [:charge, 'ext-owner123']])
      expect(fetcher).not_to have_received(:fetch)
    end

    it 'raises LimitExceeded out of raise_concerns and fetches nothing when the customer is locked' do
      allow(logic).to receive(:enforce_sso_metadata_fetch_rate_limit!).and_raise(
        Onetime::LimitExceeded.new('Too many metadata fetches. Please try again later.',
                                   retry_after: 1234, max_attempts: 30),
      )

      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded) do |error|
        expect(error.retry_after).to eq(1234)
      end
      expect(fetcher).not_to have_received(:fetch)
    end
  end

  describe 'per-customer rate limit (SsoMetadataFetchRateLimiter)' do
    it 'declares the policy: kind sso_metadata_fetch, 30 per hour, one-hour lockout' do
      policy = Onetime::Security::SsoMetadataFetchRateLimiter::POLICY

      expect(policy.to_h).to include(
        kind: 'sso_metadata_fetch', config_key: 'sso_metadata_fetch_rate_limit',
        default_max_per_customer: 30, default_window: 3600, default_lockout: 3600,
        audit_verb: 'sso.metadata_fetch_throttled'
      )
      expect(Onetime::Operations::RateLimit::Registry.keys_for('sso_metadata_fetch', 'ext-owner123'))
        .to eq(['sso_metadata_fetch:attempts:ext-owner123', 'sso_metadata_fetch:locked:ext-owner123'])
    end

    # The real limiter, against the lane's Valkey: the test config ships it
    # disabled, so it is enabled here in-process with a cap of one, which
    # makes the second request the locked one.
    it 'enforces through the real module when enabled: the request over the cap is refused' do
      saved_conf = YAML.load(YAML.dump(OT.conf))
      new_conf   = YAML.load(YAML.dump(OT.conf))
      ((new_conf['features'] ||= {})['organizations'] ||= {})['sso_metadata_fetch_rate_limit'] =
        { 'enabled' => true, 'max_per_customer' => 1, 'window' => 60, 'lockout' => 60 }
      OT.send(:conf=, new_conf)
      allow(Onetime::ColonelAuditEvent).to receive(:record_security)
      redis = Onetime::Customer.dbclient
      keys  = ['sso_metadata_fetch:attempts:ext-owner123', 'sso_metadata_fetch:locked:ext-owner123']
      redis.del(*keys)

      begin
        expect(run[:success]).to be(true)

        second = build_logic(params)
        expect { second.raise_concerns }.to raise_error(Onetime::LimitExceeded)
        expect(fetcher).to have_received(:fetch).once
      ensure
        redis.del(*keys)
        OT.send(:conf=, saved_conf)
      end
    end
  end

  describe '#process' do
    before { allow(logic).to receive(:enforce_sso_metadata_fetch_rate_limit!) }

    describe 'a fetched and parsed document' do
      it 'returns the preview with the submitted URL, stripped, and never touches the record' do
        result = run

        expect(result).to include(
          user_id: 'ext-owner123',
          success: true,
          metadata_url: metadata_url,
          idp_entity_id: 'https://idp.example.com/saml/metadata',
          idp_sso_service_url: 'https://idp.example.com/saml/sso',
          name_id_formats: ['urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'],
          problems: [],
        )
        expect(result[:signing_certificates].size).to eq(1)
        expect(result[:signing_certificates].first.keys).to eq(
          %i[pem subject not_before not_after fingerprint_sha256 thumbprint_sha1 problem],
        )
        expect(fetcher).to have_received(:fetch).with(metadata_url).once
        expect_no_record_access
      end

      it 'does not gate on the response Content-Type' do
        allow(fetcher).to receive(:fetch)
          .and_return(fetched(:ok, body: metadata_document, content_type: 'application/octet-stream'))

        expect(run[:success]).to be(true)
      end

      it 'reports blocking problems inside a successful fetch' do
        allow(fetcher).to receive(:fetch).and_return(fetched(:ok, body: metadata_document(entity_id: '')))

        result = run

        expect(result[:success]).to be(true)
        expect(result[:problems]).to eq(
          [{ code: 'invalid_entity_id', severity: 'blocking', message: 'IdP EntityID is blank' }],
        )
      end

      it 'logs scalars only: never the URL or a certificate' do
        result = run

        expect(logged.join("\n")).not_to include('idp.example.com/saml/metadata')
        expect(logged.join("\n")).not_to include(result[:signing_certificates].first[:pem][30, 40])
        expect(logged.grep(/IdP metadata fetch completed/).size).to eq(1)
      end

      # Keywords, not a trailing positional Hash: OT.info(*msgs, **payload)
      # would join a positional Hash into the message string.
      it 'logs the outcome as a structured payload' do
        payloads = []
        allow(OT).to receive(:info) { |*_msgs, **payload| payloads << payload }

        run

        expect(payloads).to include(hash_including(success: true, certificate_count: 1))
      end
    end

    describe 'the metadata URL check, before any fetch' do
      {
        'an http URL' => 'http://idp.example.com/metadata',
        'a URL with credentials' => 'https://user:secret@idp.example.com/metadata',
        'a URL with a fragment' => 'https://idp.example.com/metadata#frag',
        'a host with a trailing dot' => 'https://idp.example.com./metadata',
        'not a URL' => 'idp.example.com/metadata',
      }.each do |label, url|
        context "with #{label}" do
          let(:params) { { 'extid' => 'ext-domain123', 'metadata_url' => url } }

          it 'answers invalid_metadata_url in metadata-URL words, without fetching' do
            result = run

            expect(result).to include(success: false, metadata_url: url, message: 'Invalid metadata URL')
            expect(result[:details][:error_code]).to eq('invalid_metadata_url')
            expect(result[:details][:description]).to include('metadata URL')
            expect(result.inspect).not_to include('IdP SSO service URL')
            expect(fetcher).not_to have_received(:fetch)
          end
        end
      end

      it 'refuses a host that resolves to a private address (SsrfProtection) without fetching' do
        allow(Resolv).to receive(:getaddresses).with('idp.example.com').and_return(['10.0.0.5'])

        result = run

        expect(result[:details][:error_code]).to eq('invalid_metadata_url')
        expect(result.inspect).not_to include('10.0.0.5')
        expect(fetcher).not_to have_received(:fetch)
      end

      # The host check resolves the caller-chosen name, so the budget covers
      # it (SsoMetadataFetchRateLimiter): a refused URL is charged.
      it 'charges a URL the host check refuses' do
        allow(Resolv).to receive(:getaddresses).with('idp.example.com').and_return(['10.0.0.5'])
        allow(logic).to receive(:enforce_sso_metadata_fetch_rate_limit!)

        expect(run[:details][:error_code]).to eq('invalid_metadata_url')
        expect(logic).to have_received(:enforce_sso_metadata_fetch_rate_limit!).with('ext-owner123')
      end

      it 'builds the SSRF-guarded fetcher with the discovery timeouts and the SAML metadata Accept header' do
        allow(logic).to receive(:metadata_fetcher).and_call_original
        allow(Onetime::SsoProvider::DiscoveryFetcher).to receive(:new).and_return(fetcher)

        run

        expect(Onetime::SsoProvider::DiscoveryFetcher).to have_received(:new).with(
          open_timeout: 10,
          read_timeout: 10,
          user_agent: 'OneTimeSecret-SSO-Metadata/1.0',
          accept: 'application/samlmetadata+xml, application/xml, text/xml',
        )
      end
    end

    describe 'fetch outcome to error_code mapping' do
      def failure_for(result)
        allow(fetcher).to receive(:fetch).and_return(result)
        outcome = run
        expect(outcome).to include(success: false, metadata_url: metadata_url)
        expect(outcome[:details][:description]).to be_a(String).and(satisfy { !it.empty? })
        outcome
      end

      it 'maps :not_found to metadata_not_found' do
        outcome = failure_for(fetched(:not_found, http_status: 404))

        expect(outcome[:details]).to include(error_code: 'metadata_not_found', http_status: 404)
      end

      it 'maps :http_error, including an unfollowed redirect, to http_error without the reason phrase' do
        outcome = failure_for(fetched(:http_error, http_status: 302, http_message: 'Found <script>'))

        expect(outcome[:details]).to include(error_code: 'http_error', http_status: 302)
        expect(outcome.inspect).not_to include('<script>')
      end

      it 'maps :too_large to metadata_too_large with the cap' do
        outcome = failure_for(fetched(:too_large, http_status: 200))

        expect(outcome[:details]).to include(error_code: 'metadata_too_large', max_bytes: 262_144)
      end

      it 'maps :timeout to timeout' do
        outcome = failure_for(fetched(:timeout, error: Net::ReadTimeout.new))

        expect(outcome[:details]).to include(error_code: 'timeout', timeout_seconds: 10)
      end

      it 'maps :ssl_error to ssl_error with the error text sanitized' do
        error   = OpenSSL::SSL::SSLError.new('certificate verify failed for 198.51.100.7:443')
        outcome = failure_for(fetched(:ssl_error, error: error))

        expect(outcome[:details][:error_code]).to eq('ssl_error')
        expect(outcome[:details][:description]).to include('certificate verify failed', '[IP]', ':[PORT]')
        expect(outcome.inspect).not_to include('198.51.100.7')
      end

      it 'maps :connection_failed to connection_failed with the error text sanitized' do
        error   = Errno::ECONNREFUSED.new('connect(2) for 198.51.100.7:443')
        outcome = failure_for(fetched(:connection_failed, error: error))

        expect(outcome[:details][:error_code]).to eq('connection_failed')
        expect(outcome.inspect).not_to include('198.51.100.7')
      end

      it 'maps :blocked to blocked_target, never echoing the resolved address' do
        error   = Onetime::Http::Guard::Blocked.new('idp.example.com resolves to blocked address 10.1.2.3')
        outcome = failure_for(fetched(:blocked, error: error))

        expect(outcome[:details]).to include(error_code: 'blocked_target')
        expect(outcome.inspect).not_to include('10.1.2.3')
      end

      it 'maps :invalid_url to invalid_metadata_url' do
        outcome = failure_for(fetched(:invalid_url))

        expect(outcome[:details]).to include(error_code: 'invalid_metadata_url')
      end

      it 'maps :error to unexpected_error without the exception text' do
        outcome = failure_for(fetched(:error, error: StandardError.new('internal detail xyz')))

        expect(outcome[:details]).to include(error_code: 'unexpected_error')
        expect([outcome.inspect, *logged].join).not_to include('internal detail xyz')
      end

      it 'maps a raising fetcher to unexpected_error' do
        allow(fetcher).to receive(:fetch).and_raise(NoMethodError, 'undefined method for document body')

        outcome = run

        expect(outcome[:details]).to include(error_code: 'unexpected_error')
        expect([outcome.inspect, *logged].join).not_to include('document body')
      end
    end

    describe 'documents the parser refuses' do
      it 'maps a non-metadata body to invalid_metadata without echoing it' do
        allow(fetcher).to receive(:fetch).and_return(fetched(:ok, body: '{"issuer":"https://leak.example.com"}'))

        outcome = run

        expect(outcome).to include(success: false, message: 'The document is not usable SAML 2.0 IdP metadata')
        expect(outcome[:details][:error_code]).to eq('invalid_metadata')
        expect([outcome.inspect, *logged].join).not_to include('leak.example.com')
      end

      it 'maps a federation aggregate to aggregate_metadata' do
        entity = ->(id) { metadata_document(entity_id: id).sub(/\A<md:EntityDescriptor [^>]*>/, %(<md:EntityDescriptor entityID="#{id}">)) }
        body   = '<md:EntitiesDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" ' \
                 "xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">#{entity.call('https://a.example.com')}" \
                 "#{entity.call('https://b.example.com')}</md:EntitiesDescriptor>"
        allow(fetcher).to receive(:fetch).and_return(fetched(:ok, body: body))

        outcome = run

        expect(outcome[:details][:error_code]).to eq('aggregate_metadata')
      end

      it 'reports an unrelated parser RuntimeError as unexpected_error, without its text' do
        allow(Onetime::SsoProvider::IdpMetadata).to receive(:parse).and_raise(RuntimeError, 'boom with detail')

        outcome = run

        expect(outcome[:details]).to include(error_code: 'unexpected_error')
        expect([outcome.inspect, *logged].join).not_to include('boom with detail')
      end
    end

    # The advisory names Entra's TENANT-level metadata: one tenant segment
    # (GUID, tenant domain or `common`) and no nonempty appid, parsed as a
    # query parameter.
    describe 'tenant_level_entra_metadata advisory' do
      def result_for(url)
        instance = build_logic('extid' => 'ext-domain123', 'metadata_url' => url)
        allow(instance).to receive(:enforce_sso_metadata_fetch_rate_limit!)
        instance.raise_concerns
        instance.process
      end

      def problems_for(url)
        result_for(url)[:problems]
      end

      tenants = {
        'a GUID tenant' => '72f988bf-86f1-41af-91ab-2d7cd011db47',
        'a domain tenant' => 'contoso.onmicrosoft.com',
        'the common tenant' => 'common',
      }
      queries = { 'missing appid' => '', 'a bare appid' => '?appid', 'an empty appid' => '?appid=' }

      tenants.each do |tenant_label, tenant|
        queries.each do |query_label, query|
          it "warns for #{tenant_label} with #{query_label}" do
            url = "https://login.microsoftonline.com/#{tenant}/federationmetadata/2007-06/federationmetadata.xml#{query}"

            expect(problems_for(url)).to contain_exactly(
              hash_including(code: 'tenant_level_entra_metadata', severity: 'advisory'),
            )
          end
        end

        it "does not warn for #{tenant_label} with a nonempty appid" do
          url = "https://login.microsoftonline.com/#{tenant}/federationmetadata/2007-06/federationmetadata.xml" \
                '?appid=00000000-1111-2222-3333-444444444444'

          expect(problems_for(url)).to eq([])
        end
      end

      it 'does not warn for an unrelated host on the same path' do
        expect(problems_for('https://idp.example.com/common/federationmetadata/2007-06/federationmetadata.xml'))
          .to eq([])
      end

      it 'does not warn for an unrelated path on an Entra host' do
        expect(problems_for('https://login.microsoftonline.com/common/saml2/metadata')).to eq([])
      end

      it 'does not block an otherwise eligible import' do
        result = result_for('https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml')

        expect(result).to include(success: true, idp_sso_service_url: 'https://idp.example.com/saml/sso')
        expect(result[:problems].map { it[:severity] }).to eq(['advisory'])
      end
    end
  end
end
