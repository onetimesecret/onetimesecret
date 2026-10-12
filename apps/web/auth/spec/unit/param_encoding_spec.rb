# apps/web/auth/spec/unit/param_encoding_spec.rb
#
# frozen_string_literal: true

# Auth::ParamEncoding (SEC-B01, SEC-B08, SEC-B11): a Rodauth request whose
# params hold a String with invalid encoding gets one 400 from the last step of
# before_rodauth, after the host gates and before any route hook, so before any
# account lookup. Exercised through the production before_rodauth owner
# (config/hooks/restrict_to.rb) on a Rodauth app with an email-sending route,
# where the invalid param used to be touched only for an existing account. The
# gates are stubbed; their policy has its own specs (restrict_to_gate_spec.rb,
# signin_gate_spec.rb).
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/unit/param_encoding_spec.rb

require_relative '../spec_helper'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../lib/logging'
require_relative '../../param_encoding'
require_relative '../../config/hooks/restrict_to'

# rubocop:disable-next RSpec/SpecFilePathFormat -- unit specs for apps/web/auth/*.rb live in spec/unit
RSpec.describe Auth::ParamEncoding, :aggregate_failures do
  include Rack::Test::Methods

  let(:invalid) { (+"\xFF").force_encoding(Encoding::UTF_8) }

  describe '.invalid?' do
    it 'flags a String that is not valid in its encoding, at any depth' do
      expect(described_class.invalid?(invalid)).to be(true)
      expect(described_class.invalid?({ 'locale' => invalid })).to be(true)
      expect(described_class.invalid?({ invalid => 'value' })).to be(true)
      expect(described_class.invalid?({ 'a' => [{ 'b' => invalid }] })).to be(true)
      expect(described_class.invalid?([1, invalid])).to be(true)
    end

    it 'passes valid Strings, binary Strings and non-Strings' do
      expect(described_class.invalid?({ 'locale' => 'fr_FR', 'name' => 'Zoë' })).to be(false)
      expect(described_class.invalid?((+"\xFF").force_encoding(Encoding::ASCII_8BIT))).to be(false)
      expect(described_class.invalid?({ key: :symbol, 'n' => 1, 'b' => true, 'x' => nil })).to be(false)
      expect(described_class.invalid?({})).to be(false)
    end
  end

  describe 'wired into before_rodauth, after the host gates' do
    let(:db) { create_test_database }
    let(:sent) { [] }
    # Routes the stubbed RestrictTo gate 404s, as on a host that restricts
    # their sign-in method away.
    let(:gated_routes) { [] }

    # Shaped like Auth::Router where the answer's bytes depend on it: its
    # default cache-control header, its 404 catch-all body, and
    # Rack::ContentLength outside the app (lib/onetime/application/
    # middleware_stack.rb). json: true loads Roda's json_parser, which parses
    # any JSON media type and so reads the non-UTF-8 charset bodies. The email
    # builder reads a request param with String#strip AFTER the account
    # lookup, as the production builders do (the email locale, the invite
    # token), so without the guard only an existing account raises.
    let(:app) do
      deliveries = sent
      app_db     = db
      roda       = Class.new(Roda) do
        plugin :json
        plugin :halt
        plugin :default_headers, 'cache-control' => 'private, no-store'
        plugin :rodauth, json: true do
          db app_db
          enable :json, :login, :reset_password
          login_column :email
          only_json? true
          require_mail? false
          set_deadline_values? true
          send_reset_password_email { deliveries << param_or_nil('locale').to_s.strip }
          Auth::Config::Hooks::RestrictTo.configure(self)
        end
        route do |r|
          r.rodauth
          response.status = 404
          Auth::ErrorTranslator::NOT_FOUND_BODY
        end
      end
      Rack::ContentLength.new(roda.app)
    end

    before do
      allow(Auth::Config::Hooks::RestrictTo).to receive(:refuse_unavailable_domain!)
      allow(Auth::SigninEnabled).to receive(:enforce_route!)
      allow(Auth::SignupEnabled).to receive(:enforce_route!)
      allow(Auth::SigninGate).to receive(:enforce_route!)
      allow(Auth::RestrictTo).to receive(:enforce_route!) do |rodauth|
        rodauth.request.halt(Auth::RestrictTo.not_found_response) if gated_routes.include?(rodauth.current_route)
      end
      env 'rack.session', {}
      db[:accounts].insert(email: 'user@example.com', status_id: AuthTestConstants::STATUS_VERIFIED)
    end

    def post_raw(path, body, content_type: 'application/json; charset=iso-8859-1')
      header 'Content-Type', content_type
      header 'Accept', 'application/json'
      post path, body.b
      [last_response.status, last_response.headers.to_h, last_response.body]
    end

    def reset_body(login, locale)
      %({"login":"#{login}","locale":"#{locale}"})
    end

    it 'answers an existing and a missing login with the same 400 when a param is invalid' do
      existing = post_raw('/reset-password-request', reset_body('user@example.com', "\xFF"))
      missing  = post_raw('/reset-password-request', reset_body('nobody@example.com', "\xFF"))

      expect(existing.first).to eq(400)
      expect(JSON.parse(existing.last)).to eq('error' => 'Bad Request', 'error_type' => 'BadRequest')
      expect(existing[1]).to include('content-type' => 'application/json', 'cache-control' => 'private, no-store')
      expect(existing).to eq(missing)
      expect(sent).to be_empty
    end

    it 'refuses only after every host gate has run' do
      post_raw('/reset-password-request', reset_body('user@example.com', "\xFF"))

      expect(last_response.status).to eq(400)
      expect(Auth::Config::Hooks::RestrictTo).to have_received(:refuse_unavailable_domain!)
      expect(Auth::SigninEnabled).to have_received(:enforce_route!)
      expect(Auth::SignupEnabled).to have_received(:enforce_route!)
      expect(Auth::RestrictTo).to have_received(:enforce_route!)
      expect(Auth::SigninGate).to have_received(:enforce_route!)
    end

    it 'refuses an invalid query param the same way' do
      header 'Accept', 'application/json'
      header 'Content-Type', 'application/json'
      post '/reset-password-request?locale=%FF', %({"login":"user@example.com"})

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)).to include('error_type' => 'BadRequest')
    end

    it 'leaves a valid request untouched' do
      status, = post_raw(
        '/reset-password-request',
        reset_body('user@example.com', 'fr_FR'),
        content_type: 'application/json',
      )

      expect(status).to eq(200)
      expect(sent).to eq(['fr_FR'])
    end

    # ADR-034#reject-as-not-found-not-forbidden: "A restricted-away method
    # rejects as 404, matching Rodauth's behavior for a feature that was never
    # loaded". The guard ran first in around_rodauth, so a bad param answered
    # 400 here while an undefined path answers 404 (SEC-B11).
    context 'when the host gates the route away' do
      let(:gated_routes) { [:reset_password_request] }

      it 'answers an invalid param exactly as an undefined path does' do
        gated     = post_raw('/reset-password-request', reset_body('user@example.com', "\xFF"))
        undefined = post_raw('/no-such-route', reset_body('user@example.com', "\xFF"))

        expect(gated.first).to eq(404)
        expect(gated).to eq(undefined)
        expect(sent).to be_empty
      end

      it 'answers a malformed JSON body exactly as an undefined path does' do
        gated     = post_raw('/reset-password-request', '{"login":', content_type: 'application/vnd.api+json')
        undefined = post_raw('/no-such-route', '{"login":', content_type: 'application/vnd.api+json')

        expect(gated.first).to eq(404)
        expect(gated).to eq(undefined)
      end
    end
  end

  describe '.refuse_invalid!' do
    it 'skips internal requests, whose params are the app own' do
      request = instance_double(Rack::Request)
      rodauth = double('Rodauth::Auth', request: request) # rubocop:disable RSpec/VerifiedDoubles -- internal_request? is private
      allow(rodauth).to receive(:internal_request?).and_return(true)

      described_class.refuse_invalid!(rodauth)

      expect(rodauth).not_to have_received(:request)
    end
  end
end
