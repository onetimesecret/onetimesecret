# spec/unit/onetime/sso_provider/request_bound_saml_spec.rb
#
# frozen_string_literal: true

# Unit coverage for OmniAuth::Strategies::RequestBoundSAML (#4450) — the
# strategy subclass that owns every SAML-specific gate.
#
# The strategy is mounted in a bare Rack stack (no Rodauth, no app boot) and
# driven with REAL signed SAML Responses minted by SamlSpec::TestIdp, so
# ruby-saml's validate path (XSD, signature, audience, destination,
# conditions, InResponseTo, issuer) runs for real. Only three seams are
# replaced:
#   - env['rack.session'] is a plain Hash the example can read and seed
#   - Familia.dbclient is an in-memory SET NX fake, so the REAL replay guard
#     runs without a datastore (the datastore behaviour itself is pinned in
#     try/unit/security/saml_assertion_replay_guard_try.rb)
#   - the Auth logger is a spy
#
# OmniAuth.config is process-global; every example snapshots and restores the
# fields it touches.

require 'spec_helper'
require 'rack/mock'
require 'zlib'
require 'onetime/sso_provider/request_bound_saml'
require_relative '../../../support/saml/test_idp'

RSpec.describe OmniAuth::Strategies::RequestBoundSAML do
  # SET NX EX only — the single datastore call the replay guard makes.
  let(:fake_dbclient) do
    Class.new do
      attr_reader :writes

      def initialize
        @store  = {}
        @writes = []
      end

      def set(key, value, nx: false, ex: nil)
        @writes << { key: key, ex: ex }
        return false if nx && @store.key?(key)

        @store[key] = value
        true
      end
    end.new
  end

  let(:idp) { SamlSpec::TestIdp.new }
  let(:host) { 'https://ots.example.com' }
  let(:acs_url) { "#{host}/auth/saml/callback" }
  let(:sp_entity_id) { "#{host}/auth/saml/metadata" }
  let(:request_id_key) { described_class::REQUEST_ID_KEY }

  # The full hardened option set from the #4450 design (D3). ruby-saml's
  # Settings.new REPLACES the security defaults wholesale, so the hash is
  # always complete.
  let(:hardened_options) do
    {
      idp_sso_service_url: 'https://idp.example.com/saml/sso',
      idp_entity_id: idp.entity_id,
      idp_cert: idp.cert_pem,
      sp_entity_id: sp_entity_id,
      name_identifier_format: SamlSpec::TestIdp::PERSISTENT,
      allowed_clock_drift: 60,
      check_duplicated_attributes: true,
      slo_enabled: false,
      idp_sso_service_url_runtime_params: {},
      security: {
        authn_requests_signed: false,
        logout_requests_signed: false,
        logout_responses_signed: false,
        want_assertions_signed: true,
        want_assertions_encrypted: false,
        want_name_id: true,
        metadata_signed: false,
        embed_sign: false,
        digest_method: XMLSecurity::Document::SHA256,
        signature_method: XMLSecurity::Document::RSA_SHA256,
        check_idp_cert_expiration: true,
        check_sp_cert_expiration: false,
        strict_audience_validation: true,
        lowercase_url_encoding: false,
      },
    }
  end
  let(:strategy_options) { hardened_options }

  let(:session) { {} }
  let(:reached_app) { [] }
  let(:failures) { [] }
  let(:auth_logger) { instance_double(SemanticLogger::Logger, warn: nil, debug: nil, info: nil, error: nil) }

  let(:app) do
    shared_session = session
    reached        = reached_app
    options        = strategy_options
    strategy       = described_class

    Rack::Builder.new do
      use(Class.new do
        define_method(:initialize) { |inner| @inner = inner }
        define_method(:call) do |env|
          env['rack.session'] = shared_session
          @inner.call(env)
        end
      end)
      use strategy, **options
      run lambda { |env|
        reached << env['omniauth.auth']
        [200, { 'content-type' => 'text/plain' }, ['app']]
      }
    end.to_app
  end

  around do |example|
    config = OmniAuth.config
    saved  = {
      on_failure: config.on_failure,
      request_validation_phase: config.request_validation_phase,
      logger: config.logger,
      test_mode: config.test_mode,
      full_host: config.full_host,
    }
    recorded                        = failures
    config.test_mode                = false
    config.full_host                = nil
    config.request_validation_phase = nil
    config.logger                   = Logger.new(File::NULL)
    config.on_failure               = lambda { |env|
      recorded << {
        type: env['omniauth.error.type'],
        error: env['omniauth.error'],
      }
      [401, { 'content-type' => 'text/plain' }, ['refused']]
    }
    example.run
  ensure
    saved.each { |key, value| config.public_send(:"#{key}=", value) }
  end

  before do
    allow(Familia).to receive(:dbclient).and_return(fake_dbclient)
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('Auth').and_return(auth_logger)
  end

  def start_login(path = '/auth/saml')
    Rack::MockRequest.new(app).post("#{host}#{path}")
  end

  def post_callback(saml_response)
    Rack::MockRequest.new(app).post(acs_url, params: { 'SAMLResponse' => saml_response })
  end

  # A response the IdP would send for the currently pending request.
  def response_for(request_id, **overrides)
    idp.response(in_response_to: request_id, acs_url: acs_url, audience: sp_entity_id, **overrides)
  end

  def decode_authn_request(location)
    query   = Rack::Utils.parse_query(URI.parse(location).query)
    deflate = Base64.decode64(query.fetch('SAMLRequest'))
    [Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(deflate), query]
  end

  def failure_types
    failures.map { |failure| failure[:type] }
  end

  describe 'class wiring' do
    it 'is an omniauth-saml strategy named saml by default' do
      expect(described_class.superclass).to eq(OmniAuth::Strategies::SAML)
      expect(described_class.default_options[:name]).to eq('saml')
    end

    it 'resolves from the :request_bound_saml symbol the way registry definitions name strategies' do
      expect(OmniAuth::Strategies.const_get(OmniAuth::Utils.camelize('request_bound_saml'))).to eq(described_class)
    end

    it 'points ruby-saml at the application logger instead of STDOUT' do
      expect(OneLogin::RubySaml::Logging.logger).to eq(Onetime::SsoProvider::RubySamlLogBridge)

      OneLogin::RubySaml::Logging.logger.debug('Created AuthnRequest: <xml/>')
      expect(auth_logger).to have_received(:debug).with('[ruby-saml] Created AuthnRequest: <xml/>')
    end
  end

  describe 'request phase' do
    it 'stores the AuthnRequest id it actually sent, in the session' do
      response = start_login

      expect(response.status).to eq(302)
      expect(response['location']).to start_with('https://idp.example.com/saml/sso?')

      xml, = decode_authn_request(response['location'])
      sent_id = xml[/<samlp:AuthnRequest[^>]*\sID=['"]([^'"]+)['"]/, 1]
      expect(sent_id).not_to be_nil
      expect(session[request_id_key]).to eq(sent_id)
    end

    it 'replaces an earlier pending id (one login attempt per session)' do
      start_login
      first = session[request_id_key]
      start_login

      expect(session[request_id_key]).not_to eq(first)
    end

    it 'sends a constant ACS URL: the login link query string is not appended' do
      response = start_login('/auth/saml?domain=tenant.example.com&RelayState=/evil')
      xml, = decode_authn_request(response['location'])

      expect(xml).to include(%(AssertionConsumerServiceURL='#{acs_url}')).or include(%(AssertionConsumerServiceURL="#{acs_url}"))
      expect(xml).not_to include('tenant.example.com')
    end

    # OmniAuth deep-merges instance options over class defaults, so the `{}`
    # in hardened_options cannot clear omniauth-saml's RelayState forwarding
    # default on its own — the subclass's class-level default is what does.
    it "does not forward the user's RelayState to the IdP" do
      _, query = decode_authn_request(start_login('/auth/saml?RelayState=/evil')['location'])

      expect(described_class.default_options[:idp_sso_service_url_runtime_params].to_hash).to eq({})
      expect(query.keys).to contain_exactly('SAMLRequest')
    end

    context 'when registered without any idp_sso_service_url_runtime_params option' do
      let(:strategy_options) { hardened_options.except(:idp_sso_service_url_runtime_params) }

      it "still does not forward the user's RelayState" do
        _, query = decode_authn_request(start_login('/auth/saml?RelayState=/evil')['location'])

        expect(query.keys).to contain_exactly('SAMLRequest')
      end
    end

    it 'sends our SP EntityID as the AuthnRequest Issuer' do
      xml, = decode_authn_request(start_login['location'])

      expect(xml).to include(">#{sp_entity_id}</saml:Issuer>")
    end

    %i[idp_entity_id sp_entity_id].each do |option|
      [nil, '', '   '].each do |blank|
        context "when #{option} is #{blank.inspect}" do
          let(:strategy_options) { hardened_options.merge(option => blank) }

          it 'refuses before contacting the IdP and leaves nothing pending' do
            response = start_login

            expect(response.status).to eq(401)
            expect(failure_types).to eq([:saml_misconfigured])
            expect(session).not_to have_key(request_id_key)
          end
        end
      end
    end
  end

  describe 'callback phase' do
    context 'with a valid response to the pending request' do
      it 'reaches the app with the NameID as uid and consumes the pending id' do
        start_login
        response = post_callback(response_for(session[request_id_key], name_id: 'persistent-abc'))

        expect(response.status).to eq(200)
        expect(failures).to be_empty
        expect(reached_app.size).to eq(1)
        expect(reached_app.first.uid).to eq('persistent-abc')
        expect(reached_app.first.provider).to eq('saml')
        expect(session).not_to have_key(request_id_key)
      end

      it 'maps the email attribute into info' do
        start_login
        post_callback(response_for(session[request_id_key], attributes: { 'email' => ['alice@example.com'] }))

        expect(reached_app.first.info.email).to eq('alice@example.com')
      end

      it "deletes the gem's SLO session keys" do
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(reached_app.size).to eq(1)
        expect(session.keys).not_to include('saml_uid', 'saml_session_index')
        expect(session).to be_empty
      end

      it 'claims the assertion with a TTL of validity + clock drift' do
        start_login
        now = Time.now.utc
        post_callback(response_for(session[request_id_key], now: now, not_on_or_after: now + 300))

        expect(fake_dbclient.writes.size).to eq(1)
        expect(fake_dbclient.writes.first[:key]).to match(/\Asaml:assertion:[0-9a-f]{64}\z/)
        expect(fake_dbclient.writes.first[:ex]).to be_between(355, 361)
      end
    end

    context 'with no pending AuthnRequest (unsolicited / IdP-initiated)' do
      it 'refuses a validly signed response that carries no InResponseTo' do
        response = post_callback(response_for(nil))

        expect(response.status).to eq(401)
        expect(failure_types).to eq([:saml_no_pending_request])
        expect(reached_app).to be_empty
      end

      it 'refuses a validly signed response that names some request id' do
        post_callback(response_for('_attacker-chosen'))

        expect(failure_types).to eq([:saml_no_pending_request])
        expect(reached_app).to be_empty
      end

      it 'refuses when the pending id is present but blank' do
        ['', '   '].each do |blank|
          session[request_id_key] = blank
          post_callback(response_for(nil))
        end

        expect(failure_types).to eq(%i[saml_no_pending_request saml_no_pending_request])
        expect(reached_app).to be_empty
      end

      it 'does not spend a replay-cache write on it' do
        post_callback(response_for(nil))

        expect(fake_dbclient.writes).to be_empty
      end
    end

    context 'when InResponseTo does not match the pending id' do
      it "refuses through the gem's own validation and burns the pending id" do
        start_login
        post_callback(response_for('_some-other-request'))

        expect(failure_types).to eq([:invalid_ticket])
        expect(failures.first[:error].message).to include('InResponseTo')
        expect(reached_app).to be_empty
        expect(session).not_to have_key(request_id_key)
      end

      it 'refuses a response with no InResponseTo at all while a request is pending' do
        start_login
        post_callback(response_for(nil))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end
    end

    context 'when the pending id has already been used' do
      it 'refuses a second, fresh, validly signed response to the same request' do
        start_login
        request_id = session[request_id_key]

        post_callback(response_for(request_id))
        post_callback(response_for(request_id))

        expect(reached_app.size).to eq(1)
        expect(failure_types).to eq([:saml_no_pending_request])
      end

      it 'burns the pending id even when the first response is refused' do
        start_login
        request_id = session[request_id_key]

        post_callback(response_for(request_id, sign: false))
        post_callback(response_for(request_id))

        expect(reached_app).to be_empty
        expect(failure_types).to eq(%i[invalid_ticket saml_no_pending_request])
      end
    end

    context 'when the document itself is not acceptable (hardened settings reach the gem)' do
      before { start_login }

      it 'refuses an unsigned assertion' do
        post_callback(response_for(session[request_id_key], sign: false))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'refuses an assertion signed by a different key' do
        impostor = SamlSpec::TestIdp.new(entity_id: idp.entity_id, key: OpenSSL::PKey::RSA.new(2048))
        post_callback(impostor.response(in_response_to: session[request_id_key], acs_url: acs_url, audience: sp_entity_id))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'refuses an assertion for a different audience' do
        post_callback(response_for(session[request_id_key], audience: 'https://other-sp.example.com/metadata'))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'refuses an expired assertion' do
        past = Time.now.utc - 3600
        post_callback(response_for(session[request_id_key], now: past, not_on_or_after: past + 300))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'refuses a request with no SAMLResponse parameter' do
        Rack::MockRequest.new(app).post(acs_url)

        expect(failure_types).to eq([:invalid_ticket])
      end
    end

    context 'when a skip_* validation escape hatch is configured' do
      let(:strategy_options) do
        hardened_options.merge(
          skip_audience: true, skip_conditions: true, skip_destination: true,
          skip_recipient_check: true, skip_subject_confirmation: true, skip_authnstatement: true
        )
      end

      it 'is ignored: the audience is still enforced' do
        start_login
        post_callback(response_for(session[request_id_key], audience: 'https://other-sp.example.com/metadata'))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end
    end

    describe 'issuer gate' do
      before { start_login }

      it 'refuses a response with no Response Issuer' do
        post_callback(response_for(session[request_id_key], response_issuer: nil))

        expect(failures.size).to eq(1)
        expect(reached_app).to be_empty
      end

      it 'refuses an issuer that is a different IdP entirely' do
        other = 'https://evil.example.net/metadata'
        post_callback(response_for(session[request_id_key], response_issuer: other, assertion_issuer: other))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      # ruby-saml compares issuers with Utils.uri_match?, which folds
      # scheme/host case and ignores the port entirely. These pass the gem and
      # are refused by the subclass's byte-equality requirement.
      {
        'host case' => 'https://IDP.example.com/saml/metadata',
        'scheme case' => 'HTTPS://idp.example.com/saml/metadata',
        'port' => 'https://idp.example.com:8443/saml/metadata',
      }.each do |label, variant|
        it "refuses an issuer that differs from the configured EntityID only by #{label}" do
          post_callback(response_for(session[request_id_key], response_issuer: variant, assertion_issuer: variant))

          expect(failure_types).to eq([:saml_issuer_mismatch])
          expect(reached_app).to be_empty
          expect(fake_dbclient.writes).to be_empty
        end
      end

      it 'refuses two distinct issuer values even when each would pass the gem' do
        post_callback(response_for(
          session[request_id_key],
          response_issuer: 'https://IDP.example.com/saml/metadata',
          assertion_issuer: idp.entity_id,
        ))

        expect(failure_types).to eq([:saml_issuer_mismatch])
        expect(auth_logger).to have_received(:warn)
          .with('[saml_response_refused]', hash_including(reason: 'saml_issuer_mismatch', issuer_count: 2))
        expect(reached_app).to be_empty
      end

      it 'refuses when the Response issuer is right but the Assertion issuer is another IdP' do
        post_callback(response_for(session[request_id_key], assertion_issuer: 'https://evil.example.net/metadata'))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'refuses when reading the issuers raises after validation' do
        allow_any_instance_of(OneLogin::RubySaml::Response) # rubocop:disable RSpec/AnyInstance
          .to receive(:issuers).and_raise(OneLogin::RubySaml::ValidationError, 'Issuer of the Assertion not found or multiple.')
        post_callback(response_for(session[request_id_key]))

        expect(failures.size).to eq(1)
        expect(reached_app).to be_empty
      end
    end

    %i[idp_entity_id sp_entity_id].each do |option|
      [nil, '', '   '].each do |blank|
        context "when #{option} is #{blank.inspect} at callback time" do
          let(:strategy_options) { hardened_options.merge(option => blank) }

          it 'refuses a validly signed response and still burns the pending id' do
            session[request_id_key] = '_pending'
            post_callback(response_for('_pending'))

            expect(failure_types).to eq([:saml_misconfigured])
            expect(reached_app).to be_empty
            expect(session).not_to have_key(request_id_key)
            expect(fake_dbclient.writes).to be_empty
          end
        end
      end
    end

    describe 'NameID gate' do
      before { start_login }

      it 'refuses a transient NameID when no uid_attribute is configured' do
        post_callback(response_for(session[request_id_key], name_id_format: SamlSpec::TestIdp::TRANSIENT))

        expect(failure_types).to eq([:saml_transient_name_id])
        expect(reached_app).to be_empty
        expect(fake_dbclient.writes).to be_empty
      end

      it 'accepts an emailAddress NameID' do
        post_callback(response_for(session[request_id_key], name_id: 'a@example.com', name_id_format: SamlSpec::TestIdp::EMAIL))

        expect(reached_app.first.uid).to eq('a@example.com')
      end

      context 'with uid_attribute configured' do
        let(:strategy_options) { hardened_options.merge(uid_attribute: 'employee_id') }

        it 'accepts a transient NameID and takes the uid from the attribute' do
          post_callback(response_for(
            session[request_id_key],
            name_id: '_random-per-login', name_id_format: SamlSpec::TestIdp::TRANSIENT,
            attributes: { 'employee_id' => ['E-1001'], 'email' => ['e@example.com'] }
          ))

          expect(failures).to be_empty
          expect(reached_app.first.uid).to eq('E-1001')
        end

        it 'refuses when the attribute is missing' do
          post_callback(response_for(session[request_id_key], attributes: { 'email' => ['e@example.com'] }))

          expect(failure_types).to eq([:invalid_ticket])
          expect(reached_app).to be_empty
        end

        it 'refuses when the attribute is present but blank' do
          post_callback(response_for(session[request_id_key], attributes: { 'employee_id' => ['  '] }))

          expect(failure_types).to eq([:saml_missing_uid])
          expect(reached_app).to be_empty
        end
      end
    end

    describe 'replay gate' do
      it 'refuses the same assertion presented twice, even with a matching pending id' do
        start_login
        request_id    = session[request_id_key]
        saml_response = response_for(request_id)

        post_callback(saml_response)
        # Re-seed the pending id so ONLY the replay cache stands between the
        # replayed document and a login.
        session[request_id_key] = request_id
        post_callback(saml_response)

        expect(reached_app.size).to eq(1)
        expect(failure_types).to eq([:saml_assertion_replayed])
      end

      it 'fails closed when the datastore raises' do
        allow(fake_dbclient).to receive(:set).and_raise(Redis::CannotConnectError, 'redis://:hunter2@10.0.0.5:6379')
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_replay_guard_unavailable])
        expect(reached_app).to be_empty
        # The Redis error message (which can carry a URL with credentials)
        # reaches neither the failure exception nor the log event.
        expect(failures.first[:error].message).not_to include('hunter2')
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_replay_guard_unavailable', error_class: 'Redis::CannotConnectError'),
        )
      end

      it 'fails closed when the guard returns anything but true' do
        allow(Onetime::Security::SamlAssertionReplayGuard).to receive(:claim).and_return(nil)
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_assertion_replayed])
        expect(reached_app).to be_empty
      end

      it 'refuses an assertion with no readable id or expiry, without claiming' do
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:assertion_id).and_return(nil) # rubocop:disable RSpec/AnyInstance
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_assertion_unbounded])
        expect(fake_dbclient.writes).to be_empty
        expect(reached_app).to be_empty
      end
    end

    describe 'refusal hygiene' do
      it "deletes the gem's SLO session keys when a post-validation gate refuses" do
        start_login
        post_callback(response_for(session[request_id_key], name_id_format: SamlSpec::TestIdp::TRANSIENT))

        expect(failure_types).to eq([:saml_transient_name_id])
        expect(session).to be_empty
      end

      it 'refuses when the gem reports errors without raising (soft-mode regression guard)' do
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:is_valid?) do |response| # rubocop:disable RSpec/AnyInstance
          response.errors << 'Invalid Signature on SAML Response'
          false
        end
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:invalid_ticket])
        expect(reached_app).to be_empty
      end

      it 'logs one scalar-only event per refusal' do
        start_login
        post_callback(response_for(session[request_id_key], response_issuer: 'https://IDP.example.com/saml/metadata',
          assertion_issuer: 'https://IDP.example.com/saml/metadata'))

        expect(auth_logger).to have_received(:warn).once do |message, payload|
          expect(message).to eq('[saml_response_refused]')
          expect(payload).to include(
            reason: 'saml_issuer_mismatch', provider: 'saml', phase: 'callback',
            observed_issuer: 'https://IDP.example.com/saml/metadata', expected_issuer: idp.entity_id
          )
          expect(payload.values).to all(be_a(String).or(be_a(Integer)).or(be(true)).or(be(false)))
        end
      end

      it 'truncates IdP-supplied strings copied into the log event' do
        # uri_match? ignores the fragment, so this passes the gem.
        long = "#{idp.entity_id}##{'a' * 1000}"
        start_login
        post_callback(response_for(session[request_id_key], response_issuer: long, assertion_issuer: long))

        expect(auth_logger).to have_received(:warn) do |_message, payload|
          expect(payload[:observed_issuer].length).to be <= described_class::LOG_VALUE_MAX
        end
      end
    end
  end

  describe 'auth hash hygiene' do
    # An SP keypair makes the leak test meaningful: with it configured, the
    # gem's Response object holds a private key via its settings.
    let(:sp_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:strategy_options) do
      hardened_options.merge(private_key: sp_key.to_pem, certificate: SamlSpec::TestIdp.new(key: sp_key).cert_pem)
    end
    let(:saml_response) do
      response_for(
        session[request_id_key],
        attributes: { 'email' => ['alice@example.com'], 'groups' => %w[eng ops], 'marker' => ['ATTRIBUTE-CANARY'] },
      )
    end
    let(:auth) { reached_app.first }

    before do
      start_login
      post_callback(saml_response)
    end

    it 'succeeds with the SP keypair configured' do
      expect(failures).to be_empty
      expect(auth).not_to be_nil
    end

    it 'exposes exactly the scalar extra keys and raw_info — never response_object' do
      expect(auth.extra.keys).to contain_exactly('idp_entity_id', 'name_id_format', 'session_index', 'raw_info')
      expect(auth.extra).not_to have_key('response_object')
      expect(auth.extra['idp_entity_id']).to eq(idp.entity_id)
      expect(auth.extra['name_id_format']).to eq(SamlSpec::TestIdp::PERSISTENT)
      expect(auth.extra['session_index']).to be_a(String)
    end

    it 'hands raw_info over as a Hash of name => Array<String> without the injected fingerprint' do
      raw_info = auth.extra['raw_info']

      expect(raw_info).to be_a(Hash)
      expect(raw_info).not_to be_a(OneLogin::RubySaml::Attributes)
      expect(raw_info.to_hash).to eq(
        'email' => ['alice@example.com'], 'groups' => %w[eng ops], 'marker' => ['ATTRIBUTE-CANARY'],
      )
      expect(raw_info).not_to have_key('fingerprint')
    end

    it 'answers the claim reads the omniauth hooks make without raising' do
      # hooks/omniauth.rb email_verification_hold and features/omniauth.rb
      # omniauth_token_issuer index raw_info by string and by symbol.
      raw_info = auth.extra['raw_info']

      expect(raw_info['email_verified']).to be_nil
      expect(raw_info[:email_verified]).to be_nil
      expect(raw_info['iss']).to be_nil
    end

    it 'contains no ruby-saml object anywhere in the tree' do
      walk = lambda do |node|
        case node
        when Hash then node.values.flat_map { |value| walk.call(value) }
        when Array then node.flat_map { |value| walk.call(value) }
        else [node]
        end
      end
      leaves = walk.call(auth.to_hash)

      expect(leaves.map(&:class).uniq - [String, NilClass, TrueClass, FalseClass, Integer]).to be_empty
    end

    it 'leaks neither the response XML nor a private key through inspect, to_json or Marshal' do
      decoded = Base64.decode64(saml_response)
      dumps   = {
        inspect: auth.inspect,
        json: JSON.generate(auth.to_hash),
        marshal: Marshal.dump(auth.to_hash).force_encoding(Encoding::BINARY),
      }

      dumps.each_value do |dump|
        expect(dump).not_to include('PRIVATE KEY')
        expect(dump).not_to include(sp_key.to_pem.lines[1].strip)
        expect(dump).not_to include('saml:Assertion')
        expect(dump).not_to include('SignatureValue')
        expect(dump).not_to include(saml_response[0, 64])
        expect(dump).not_to include(decoded[/<ds:SignatureValue>([^<]{32})/, 1])
        expect(dump).not_to include(idp.cert_pem.lines[1].strip)
      end
    end

    it 'is small: the serialized auth hash is attributes and scalars, not a document' do
      expect(Marshal.dump(auth.to_hash).bytesize).to be < 2048
    end
  end
end
