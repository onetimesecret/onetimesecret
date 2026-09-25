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
require 'onetime/sso_provider/saml'
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

  # The SHIPPED hardened option set, from the one builder both surfaces use
  # (Onetime::SsoProvider::Saml.strategy_options_for) — not a copy of it. So
  # every gate below is proven against the options the platform definition and
  # the tenant arm actually register, including the full `security` hash
  # (ruby-saml's Settings.new REPLACES the security defaults wholesale, so it
  # must be complete; registry_spec pins it key by key).
  let(:hardened_options) do
    Onetime::SsoProvider::Saml.strategy_options_for(
      idp_sso_service_url: 'https://idp.example.com/saml/sso',
      idp_entity_id: idp.entity_id,
      idp_cert: idp.cert_pem,
    ).merge(sp_entity_id: sp_entity_id)
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

    # The shared builder carries no idp_sso_service_url_runtime_params key:
    # OmniAuth deep-merges instance options over class defaults, so a `{}`
    # passed at registration could not clear omniauth-saml's RelayState
    # forwarding default — the subclass's class-level default is what does.
    it "does not forward the user's RelayState to the IdP" do
      _, query = decode_authn_request(start_login('/auth/saml?RelayState=/evil')['location'])

      expect(described_class.default_options[:idp_sso_service_url_runtime_params].to_hash).to eq({})
      expect(query.keys).to contain_exactly('SAMLRequest')
    end

    context 'when a registration passes an empty idp_sso_service_url_runtime_params' do
      let(:strategy_options) { hardened_options.merge(idp_sso_service_url_runtime_params: {}) }

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

  # The pending AuthnRequest id lives in the session cookie of the host the
  # visitor started on, and the IdP posts the response to the ACS URL. The
  # platform surface pins its ACS to site.host (Saml.platform_options), so a
  # platform sign-in started anywhere else — a custom domain under platform
  # fallback, a secondary canonical host — could only end as
  # :saml_no_pending_request. Refused up front, at both phases.
  describe 'ACS host gate (assertion_consumer_service_url pinned to another host)' do
    let(:pinned_acs) { 'https://canonical.example.com/auth/saml/callback' }
    let(:strategy_options) { hardened_options.merge(assertion_consumer_service_url: pinned_acs) }

    it 'refuses the request phase before contacting the IdP and leaves nothing pending' do
      response = start_login

      expect(response.status).to eq(401)
      expect(failure_types).to eq([:saml_acs_host_mismatch])
      expect(session).not_to have_key(request_id_key)
      expect(auth_logger).to have_received(:warn).with(
        '[saml_response_refused]',
        hash_including(reason: 'saml_acs_host_mismatch', phase: 'request',
                       acs_host: 'canonical.example.com', request_host: 'ots.example.com'),
      )
    end

    it 'refuses the callback phase and burns the pending id' do
      session[request_id_key] = '_pending'
      response = post_callback(response_for('_pending'))

      expect(response.status).to eq(401)
      expect(failure_types).to eq([:saml_acs_host_mismatch])
      expect(session).not_to have_key(request_id_key)
      expect(reached_app).to be_empty
    end

    context 'when the pinned ACS names this host on another scheme or port' do
      let(:pinned_acs) { 'http://OTS.example.com:8080/auth/saml/callback' }

      it 'is not a mismatch (the cookie is host-scoped)' do
        response = start_login

        expect(response.status).to eq(302)
        expect(failure_types).to be_empty
        expect(session[request_id_key]).not_to be_nil
      end
    end

    context 'when the pinned ACS does not parse' do
      let(:pinned_acs) { 'https://canonical.example.com:notaport/auth/saml/callback' }

      it 'fails closed' do
        expect(start_login.status).to eq(401)
        expect(failure_types).to eq([:saml_acs_host_mismatch])
      end
    end

    context 'when no ACS is pinned (the tenant hook or the gem derives it from this request)' do
      let(:strategy_options) { hardened_options }

      it 'is not a mismatch' do
        expect(start_login.status).to eq(302)
        expect(failure_types).to be_empty
      end
    end
  end

  # saml.rb:88-109: other_phase runs setup_phase and serves SP metadata from
  # whatever options the strategy holds.
  describe 'SP metadata sub-path' do
    def get_metadata
      Rack::MockRequest.new(app).get("#{host}/auth/saml/metadata")
    end

    it 'serves metadata naming the configured SP EntityID and the constant ACS URL' do
      response = get_metadata

      expect(response.status).to eq(200)
      expect(response['content-type']).to include('application/xml')
      expect(response.body).to include(%(entityID='#{sp_entity_id}')).or include(%(entityID="#{sp_entity_id}"))
      expect(response.body).to include(acs_url)
    end

    it 'does not start a login (no pending AuthnRequest id is stored)' do
      get_metadata

      expect(session).not_to have_key(request_id_key)
    end

    # The placeholder registration (org-level SSO on, no platform SAML_* vars)
    # carries blank trust anchors. With no tenant resolved, the gem would
    # serve a document with a blank entityID for an IdP admin to import.
    context 'with the placeholder (blank trust anchor) options' do
      let(:strategy_options) { Onetime::SsoProvider::Saml::DEFINITION[:placeholder_options].dup }

      it 'answers 404 instead of half-configured metadata' do
        response = get_metadata

        expect(response.status).to eq(404)
        expect(response.body).not_to include('EntityDescriptor')
      end
    end

    context 'with a blank sp_entity_id only' do
      let(:strategy_options) { hardened_options.merge(sp_entity_id: ' ') }

      it 'answers 404' do
        expect(get_metadata.status).to eq(404)
      end
    end

    it 'keeps /slo and /spslo disabled (slo_enabled: false)' do
      %w[slo spslo].each do |subpath|
        expect(Rack::MockRequest.new(app).get("#{host}/auth/saml/#{subpath}").status).to eq(501), subpath
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
        # The gem's message names the check; it reaches the log as the
        # bounded `detail` of the scalar event, never as the exception.
        expect(failures.first[:error].message).to eq('SAML response failed validation')
        expect(auth_logger).to have_received(:warn)
          .with('[saml_response_refused]', hash_including(reason: 'invalid_ticket', detail: /InResponseTo/))
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

      it 'refuses a request with no SAMLResponse parameter before the gem sees it' do
        Rack::MockRequest.new(app).post(acs_url)

        expect(failure_types).to eq([:saml_response_missing])
      end
    end

    # omniauth's callback_call runs callback_phase for ANY method, and the
    # POST binding needs a SameSite=None cookie — so a cross-site <img> GET
    # to the callback path arrives with the victim's session. Consuming the
    # pending id there would let any page cancel an in-flight sign-in.
    describe 'callback method gate' do
      before { start_login }

      it 'refuses a GET and leaves the pending id in place' do
        pending_id = session[request_id_key]
        response   = Rack::MockRequest.new(app).get("#{acs_url}?SAMLResponse=#{response_for(pending_id)}")

        expect(response.status).to eq(401)
        expect(failure_types).to eq([:saml_response_missing])
        expect(session[request_id_key]).to eq(pending_id)
        expect(reached_app).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_response_missing', method: 'GET', has_saml_response: true, phase: 'callback'),
        )
      end

      it 'refuses a HEAD and leaves the pending id in place' do
        pending_id = session[request_id_key]
        Rack::MockRequest.new(app).head(acs_url)

        expect(failure_types).to eq([:saml_response_missing])
        expect(session[request_id_key]).to eq(pending_id)
      end

      it 'refuses a POST without a SAMLResponse and leaves the pending id in place' do
        pending_id = session[request_id_key]
        Rack::MockRequest.new(app).post(acs_url, params: { 'RelayState' => 'x' })

        expect(failure_types).to eq([:saml_response_missing])
        expect(session[request_id_key]).to eq(pending_id)
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_response_missing', method: 'POST', has_saml_response: false),
        )
      end

      it 'refuses a POST whose SAMLResponse is blank or not a string, leaving the pending id' do
        pending_id = session[request_id_key]
        Rack::MockRequest.new(app).post(acs_url, params: { 'SAMLResponse' => '' })
        Rack::MockRequest.new(app).post(acs_url, params: { 'SAMLResponse' => %w[a b] })

        expect(failure_types).to eq([:saml_response_missing, :saml_response_missing])
        expect(session[request_id_key]).to eq(pending_id)
      end

      it 'still completes the real IdP POST after a cross-site GET tried to burn the id' do
        pending_id = session[request_id_key]
        Rack::MockRequest.new(app).get(acs_url)
        post_callback(response_for(pending_id))

        expect(failure_types).to eq([:saml_response_missing])
        expect(reached_app.size).to eq(1)
        expect(session).not_to have_key(request_id_key)
      end
    end

    # The gem matches only the UNSIGNED Response/@InResponseTo against the
    # pending id; the signed assertion's SubjectConfirmationData/@InResponseTo
    # is compared only when present. So a valid signed assertion whose
    # confirmation data carries no InResponseTo — an IdP-initiated one, or
    # one an attacker obtained by starting their own login — passes the gem
    # once rewrapped in a Response naming the victim's pending id. The
    # subclass requires the binding IN THE SIGNED ASSERTION.
    describe 'request binding gate (signed SubjectConfirmationData/@InResponseTo)' do
      before { start_login }

      it 'refuses an unclaimed signed assertion rewrapped in a Response naming the pending id' do
        post_callback(response_for(session[request_id_key], subject_confirmations: [nil]))

        expect(failure_types).to eq([:saml_in_response_to_unbound])
        expect(reached_app).to be_empty
        expect(fake_dbclient.writes).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_in_response_to_unbound', bound_confirmations: 0, unbound_confirmations: 1),
        )
      end

      # Pinned against the gem so the gate's reason for existing is visible:
      # if a ruby-saml bump starts refusing this, the gate is redundant but
      # stays (it is what makes the binding signed).
      it 'documents that ruby-saml alone accepts the rewrapped assertion' do
        settings = OneLogin::RubySaml::Settings.new(
          hardened_options.merge(assertion_consumer_service_url: acs_url),
        )
        response = OneLogin::RubySaml::Response.new(
          response_for(session[request_id_key], subject_confirmations: [nil]),
          settings: settings,
          matches_request_id: session[request_id_key],
          allowed_clock_drift: 60,
          check_duplicated_attributes: true,
        )

        expect(response.is_valid?).to be(true), response.errors.inspect
      end

      # The gem's validate_subject_confirmation catches a single mismatching
      # confirmation itself (:invalid_ticket); still closed.
      it 'refuses a signed InResponseTo that names another request (gem refusal)' do
        post_callback(response_for(session[request_id_key], subject_confirmations: ['_another-request']))

        expect(failure_types).to eq([:invalid_ticket])
        expect(auth_logger).to have_received(:warn)
          .with('[saml_response_refused]', hash_including(reason: 'invalid_ticket', detail: /SubjectConfirmation/))
        expect(reached_app).to be_empty
      end

      # The gem accepts the FIRST bearer confirmation that passes, and an
      # absent InResponseTo passes — so bound + unbound passes the gem. Every
      # bearer confirmation must be bound.
      it 'refuses when one bearer confirmation is bound and another is not' do
        pending_id = session[request_id_key]
        post_callback(response_for(pending_id, subject_confirmations: [pending_id, nil]))

        expect(failure_types).to eq([:saml_in_response_to_unbound])
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_in_response_to_unbound', bound_confirmations: 1, unbound_confirmations: 1),
        )
        expect(reached_app).to be_empty
      end

      it 'passes a bound assertion on to the later gates' do
        pending_id = session[request_id_key]
        post_callback(response_for(pending_id, subject_confirmations: [pending_id], name_id_format: SamlSpec::TestIdp::TRANSIENT))

        expect(failure_types).to eq([:saml_transient_name_id])
      end

      it 'accepts a bound assertion with two bound bearer confirmations' do
        pending_id = session[request_id_key]
        post_callback(response_for(pending_id, subject_confirmations: [pending_id, pending_id]))

        expect(failures).to be_empty
        expect(reached_app.size).to eq(1)
      end

      # The gem calls the same helper inside validate_subject_confirmation,
      # so an unconditional stub would be refused by the gem first; it is
      # armed only once validation has returned.
      it 'refuses under its own symbol when the signed assertion reads empty after validation' do
        validated = false
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:is_valid?).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          original.call(*args).tap { validated = true }
        end
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:xpath_from_signed_assertion).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          validated && args.first == '/a:Subject/a:SubjectConfirmation' ? [] : original.call(*args)
        end
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_in_response_to_unbound])
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_in_response_to_unbound', bound_confirmations: 0, unbound_confirmations: 0),
        )
        expect(reached_app).to be_empty
        expect(fake_dbclient.writes).to be_empty
      end

      it 'runs before the issuer gate' do
        folded = 'https://IDP.example.com/saml/metadata'
        post_callback(response_for(session[request_id_key], subject_confirmations: [nil], response_issuer: folded, assertion_issuer: folded))

        expect(failure_types).to eq([:saml_in_response_to_unbound])
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

    describe 'signature algorithm gate' do
      let(:sha1)     { XMLSecurity::Document::SHA1 }
      let(:rsa_sha1) { XMLSecurity::Document::RSA_SHA1 }

      before { start_login }

      # WHY THE GATE EXISTS, pinned against the gem: under the shipped
      # hardened settings ruby-saml 1.18.1 verifies a SHA-1 signed response
      # exactly like a SHA-256 one (xml_security.rb `algorithm` reads the URI
      # the response declares). If a bump makes this example fail, the gate
      # has become redundant — keep it anyway; it is the allowlist.
      it 'documents that ruby-saml alone accepts an RSA-SHA1 / SHA1 signed response' do
        settings = OneLogin::RubySaml::Settings.new(
          hardened_options.merge(assertion_consumer_service_url: acs_url),
        )
        response = OneLogin::RubySaml::Response.new(
          response_for(session[request_id_key], signature_method: rsa_sha1, digest_method: sha1),
          settings: settings, matches_request_id: session[request_id_key],
          allowed_clock_drift: 60, check_duplicated_attributes: true,
        )

        expect(response.is_valid?).to be(true), response.errors.inspect
      end

      it 'refuses an RSA-SHA1 signature' do
        post_callback(response_for(session[request_id_key], signature_method: rsa_sha1))

        expect(failure_types).to eq([:saml_weak_signature_algorithm])
        expect(reached_app).to be_empty
        expect(fake_dbclient.writes).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_weak_signature_algorithm', kind: 'signature_method', algorithm: rsa_sha1),
        )
      end

      it 'refuses a SHA1 digest even under an RSA-SHA256 signature' do
        post_callback(response_for(session[request_id_key], digest_method: sha1))

        expect(failure_types).to eq([:saml_weak_signature_algorithm])
        expect(reached_app).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_weak_signature_algorithm', kind: 'digest_method', algorithm: sha1),
        )
      end

      # Allowlist, not denylist: the gem maps an unknown URI to SHA1 and would
      # verify it; the gate must refuse it on the string alone.
      it 'refuses an algorithm URI it does not know, even one the gem would resolve' do
        post_callback(response_for(session[request_id_key], signature_method: 'http://www.w3.org/2000/09/xmldsig#dsa-sha1'))

        expect(failure_types).to eq([:saml_weak_signature_algorithm])
        expect(reached_app).to be_empty
      end

      {
        'RSA-SHA384 / SHA384' => [XMLSecurity::Document::RSA_SHA384, XMLSecurity::Document::SHA384],
        'RSA-SHA512 / SHA512' => [XMLSecurity::Document::RSA_SHA512, XMLSecurity::Document::SHA512],
      }.each do |label, (signature_method, digest_method)|
        it "accepts #{label}" do
          post_callback(response_for(session[request_id_key], signature_method: signature_method, digest_method: digest_method))

          expect(failure_types).to be_empty
          expect(reached_app.size).to eq(1)
        end
      end

      it 'runs before the issuer gate, so a weak signature never spends a datastore write' do
        post_callback(response_for(
          session[request_id_key], signature_method: rsa_sha1,
          response_issuer: 'https://IDP.example.com/saml/metadata', assertion_issuer: 'https://IDP.example.com/saml/metadata'
        ))

        expect(failure_types).to eq([:saml_weak_signature_algorithm])
        expect(fake_dbclient.writes).to be_empty
      end

      it 'keeps the allowlists to SHA-2 RSA methods and SHA-2 digests' do
        expect(described_class::ALLOWED_SIGNATURE_METHODS).to all(match(%r{#rsa-sha(256|384|512)\z}))
        expect(described_class::ALLOWED_DIGEST_METHODS).to all(match(/#sha(256|384|512)\z/))
        expect(described_class::ALLOWED_SIGNATURE_METHODS).not_to include(rsa_sha1)
        expect(described_class::ALLOWED_DIGEST_METHODS).not_to include(sha1)
      end
    end

    describe 'issuer gate' do
      before { start_login }

      # The GEM refuses this first (validate_issuer runs on the missing
      # Response Issuer before the block runs), so the subclass's own
      # :saml_issuer_unreadable is legitimately not the type here.
      it 'refuses a response with no Response Issuer' do
        post_callback(response_for(session[request_id_key], response_issuer: nil))

        expect(failure_types).to eq([:invalid_ticket])
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

      # The subclass's own rescue: without it the ValidationError would
      # propagate into omniauth-saml's callback_phase rescue and become a
      # generic :invalid_ticket — still closed, but the distinct symbol and
      # the [saml_response_refused] event the ops docs name would be gone.
      #
      # `issuers` is ALSO what the gem's validate_issuer calls during
      # is_valid?, so a stub that raised unconditionally would be refused by
      # the gem first (:invalid_ticket) and never reach the subclass. The
      # raise is armed only once validation has returned — the point at
      # which the subclass reads the issuers itself.
      it 'refuses when reading the issuers raises after validation, under its own symbol' do
        validated = false
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:is_valid?).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          original.call(*args).tap { validated = true }
        end
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:issuers).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          raise OneLogin::RubySaml::ValidationError, 'Issuer of the Assertion not found or multiple.' if validated

          original.call(*args)
        end
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_issuer_unreadable])
        expect(auth_logger).to have_received(:warn)
          .with('[saml_response_refused]', hash_including(reason: 'saml_issuer_unreadable', phase: 'callback'))
        expect(reached_app).to be_empty
        expect(fake_dbclient.writes).to be_empty
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

      # ruby-saml imposes no maximum NotOnOrAfter. An assertion valid for
      # longer than the guard will remember it would become replayable once
      # the marker expired; it is refused instead of silently clamped.
      it 'refuses an assertion whose NotOnOrAfter is beyond MAX_LIFETIME + clock drift, without claiming' do
        start_login
        now = Time.now.utc
        post_callback(response_for(session[request_id_key], now: now, not_on_or_after: now + 3600 + 60 + 30))

        expect(failure_types).to eq([:saml_assertion_lifetime_exceeded])
        expect(fake_dbclient.writes).to be_empty
        expect(reached_app).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_assertion_lifetime_exceeded', max_lifetime_seconds: 3600, lifetime_seconds: be_between(3685, 3690)),
        )
      end

      it 'accepts a one-hour assertion (AD FS / Entra ID default) with the IdP clock ahead by the tolerated drift' do
        start_login
        now = Time.now.utc
        post_callback(response_for(session[request_id_key], now: now, not_on_or_after: now + 3600 + 30))

        expect(failures).to be_empty
        expect(reached_app.size).to eq(1)
        # The marker outlives the gem's acceptance window (NotOnOrAfter + 60s)
        # instead of being clamped short of it.
        expect(fake_dbclient.writes.first[:ex]).to be_between(3685, 3691)
      end

      it 'refuses an assertion with no readable id or expiry, without claiming' do
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:assertion_id).and_return(nil) # rubocop:disable RSpec/AnyInstance
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_assertion_unbounded])
        expect(fake_dbclient.writes).to be_empty
        expect(reached_app).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_assertion_unbounded', has_assertion_id: false, has_not_on_or_after: true),
        )
      end

      # The other operand of the same gate. Without it a nil NotOnOrAfter
      # would reach the guard's ArgumentError and be refused under the
      # OUTAGE symbol, which an operator reads as a datastore incident.
      it 'refuses an assertion with no NotOnOrAfter under the unbounded symbol, not the outage one' do
        allow_any_instance_of(OneLogin::RubySaml::Response).to receive(:not_on_or_after).and_return(nil) # rubocop:disable RSpec/AnyInstance
        start_login
        post_callback(response_for(session[request_id_key]))

        expect(failure_types).to eq([:saml_assertion_unbounded])
        expect(fake_dbclient.writes).to be_empty
        expect(reached_app).to be_empty
        expect(auth_logger).to have_received(:warn).with(
          '[saml_response_refused]',
          hash_including(reason: 'saml_assertion_unbounded', has_assertion_id: true, has_not_on_or_after: false),
        )
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

      # Refusals the GEM makes carry response-derived text in their message
      # (Issuer, Audience values, the unsigned StatusMessage). The failure
      # exception that reaches omniauth's logger and the app's failure hook
      # must be a Refusal with a fixed message; the gem's text reaches the
      # log only as the bounded, single-line `detail` of the scalar event.
      describe 'gem-made refusals' do
        it 'replaces the gem exception with a fixed-message Refusal and one bounded scalar event' do
          start_login
          post_callback(response_for(session[request_id_key], audience: 'https://other-sp.example.com/metadata'))

          expect(failure_types).to eq([:invalid_ticket])
          error = failures.first[:error]
          expect(error).to be_a(described_class::Refusal)
          expect(error.message).to eq('SAML response failed validation')
          expect(error.message).not_to include('other-sp')
          expect(auth_logger).to have_received(:warn).once.with(
            '[saml_response_refused]',
            hash_including(reason: 'invalid_ticket', provider: 'saml', phase: 'callback',
              error_class: 'OneLogin::RubySaml::ValidationError'),
          )
          expect(auth_logger).to have_received(:warn) do |_message, payload|
            expect(payload[:detail]).to include('Invalid Audience')
            expect(payload[:detail].length).to be <= described_class::LOG_VALUE_MAX
            expect(payload.values).to all(be_a(String))
          end
        end

        it 'bounds and flattens an unsigned StatusMessage flood' do
          flood = "x\n[login_success] forged=true\r\n" + ('A' * 100_000)
          start_login
          post_callback(idp.failure_response(in_response_to: session[request_id_key], acs_url: acs_url, status_message: flood))

          expect(failure_types).to eq([:invalid_ticket])
          expect(failures.first[:error].message).to eq('SAML response failed validation')
          expect(auth_logger).to have_received(:warn).once do |_message, payload|
            expect(payload[:detail].length).to be <= described_class::LOG_VALUE_MAX
            expect(payload[:detail]).not_to match(/[\r\n]/)
            expect(payload[:detail]).not_to include("\n[login_success]")
          end
          expect(reached_app).to be_empty
        end

        # omniauth-saml's other ValidationError class. Its "SAML response
        # missing" raise is unreachable now (the subclass refuses a bare
        # callback first, without consuming the pending id), so the missing
        # uid attribute raise (saml.rb:115) is the path that exercises it.
        context "with the gem's own ValidationError class" do
          let(:strategy_options) { hardened_options.merge(uid_attribute: 'employee_id') }

          it 'is replaced the same way' do
            start_login
            post_callback(response_for(session[request_id_key], attributes: { 'email' => ['e@example.com'] }))

            expect(failure_types).to eq([:invalid_ticket])
            expect(failures.first[:error]).to be_a(described_class::Refusal)
            expect(failures.first[:error].message).not_to include('employee_id')
            expect(auth_logger).to have_received(:warn).with(
              '[saml_response_refused]',
              hash_including(reason: 'invalid_ticket', error_class: 'OmniAuth::Strategies::SAML::ValidationError'),
            )
          end
        end

        it 'leaves refusals made by the subclass untouched (one event, the original message)' do
          start_login
          post_callback(response_for(session[request_id_key], name_id_format: SamlSpec::TestIdp::TRANSIENT))

          expect(failures.first[:error].message).to eq('SAML NameID is transient and no uid_attribute is configured')
          expect(auth_logger).to have_received(:warn).once
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

      # Every IdP-supplied string reaching a log event goes through
      # `loggable`; a newline in one would forge a log line.
      it 'flattens control characters in IdP-supplied strings copied into the log event' do
        strategy = described_class.new(->(_env) { [404, {}, []] }, **strategy_options)

        expect(strategy.send(:loggable, "a\nb\r\nc\tforged\x00")).to eq('a b c forged ')
        expect(strategy.send(:loggable, "\xff".dup.force_encoding('UTF-8'))).to eq('?')
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
