# frozen_string_literal: true

# Run only through tests/lanes/run unit --only tests/browser/saml_callback_spec.rb.
# This owns one ephemeral loopback TLS listener, exposed as two genuinely
# cross-site origins (localhost and 127.0.0.1), and a bounded Playwright child.
require 'spec_helper'
require 'puma'
require 'puma/minissl'
require 'rack/session/cookie'
require 'rack/protection'
require 'open3'
require 'timeout'
require 'tmpdir'
require 'cgi'
require 'zlib'
require 'onetime/middleware/saml_callback_transport'
require 'onetime/sso_provider/request_bound_saml'
require 'onetime/sso_provider/saml'
require_relative '../../spec/support/saml/test_idp'

RSpec.describe 'Real-browser staged SAML callback' do
  it 'recovers the original Lax cookie across cross-site POST → 303 → GET, with None and Strict controls' do
    config = OmniAuth.config
    saved = %i[on_failure request_validation_phase logger test_mode full_host].to_h { |key| [key, config.public_send(key)] }
    config.test_mode = false
    config.full_host = nil
    config.request_validation_phase = nil # Harness initiation only, not production configuration.
    config.logger = Logger.new(File::NULL)
    stub_const('Onetime::Security::SamlCallbackStore::PREFIX', "spec:browser:saml:#{SecureRandom.hex(8)}")
    idp = SamlSpec::TestIdp.new
    observations = {}
    evidence = lambda do |env|
      {
        postCookie: observations[:post_cookie] == true,
        postAuthenticated: observations[:post_authenticated] == true,
        getMethod: env['REQUEST_METHOD'],
        getCookie: env['HTTP_COOKIE'].to_s.include?('saml.browser.session='),
        originalSession: env['rack.session']['browser_original'] == 'original',
      }
    end
    html = lambda do |title, env|
      "<h1>#{title}</h1><pre data-testid=\"evidence\">#{CGI.escapeHTML(JSON.generate(evidence.call(env)))}</pre><a href=\"/probe\">Leave callback</a>"
    end
    config.on_failure = ->(env) { [401, { 'content-type' => 'text/html' }, [html.call('Refused', env)]] }

    Dir.mktmpdir('saml-browser') do |directory|
      key_path = File.join(directory, 'key.pem')
      cert_path = File.join(directory, 'cert.pem')
      File.write(key_path, idp.key.to_pem, perm: 0o600)
      File.write(cert_path, idp.cert_pem)
      tls = Puma::MiniSSL::Context.new
      tls.key = key_path
      tls.cert = cert_path
      rack_app = nil
      server = Puma::Server.new(->(env) { rack_app.call(env) }, nil, log_writer: Puma::LogWriter.strings)
      server.add_ssl_listener('127.0.0.1', 0, tls)
      port = server.connected_ports.first
      sp_origin = "https://localhost:#{port}"
      idp_origin = "https://127.0.0.1:#{port}"
      acs = "#{sp_origin}/auth/sso/saml/callback"
      audience = "#{sp_origin}/metadata"
      options = Onetime::SsoProvider::Saml.strategy_options_for(
        idp_sso_service_url: "#{idp_origin}/idp", idp_entity_id: idp.entity_id, idp_cert: idp.cert_pem,
      ).merge(path_prefix: '/auth/sso', sp_entity_id: audience, assertion_consumer_service_url: acs)

      sp = Rack::Builder.new do
        use Onetime::Middleware::SamlCallbackTransport::Boundary
        use Rack::Session::Cookie, key: 'saml.browser.session', secret: 'x' * 64, same_site: :lax, secure: true
        use Rack::Protection::HttpOrigin, allow_if: ->(env) { env['HTTP_ORIGIN'] == idp_origin && env['PATH_INFO'] == '/auth/sso/saml/callback' }
        use Onetime::Middleware::SamlCallbackTransport::Stage
        use OmniAuth::Strategies::RequestBoundSAML, **options
        run lambda { |env|
          if env['PATH_INFO'] == '/start'
            env['rack.session']['browser_original'] = 'original'
            [200, { 'content-type' => 'text/html' }, ['<form method="post" action="/auth/sso/saml"><button>Start SAML sign-in</button></form>']]
          elsif env['PATH_INFO'] == '/probe'
            [200, { 'content-type' => 'text/html' }, ["<h1>Referrer probe</h1><p data-testid=\"referrer\">#{env['HTTP_REFERER'].to_s.empty? ? 'absent' : 'present'}</p>"]]
          elsif env['omniauth.auth']
            [200, { 'content-type' => 'text/html' }, [html.call('Authenticated', env)]]
          else
            [404, { 'content-type' => 'text/plain' }, ['Not found']]
          end
        }
      end.to_app
      rack_app = lambda do |env|
        req = Rack::Request.new(env)
        if req.host == '127.0.0.1' && req.path == '/idp'
          xml = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(Base64.decode64(req.params.fetch('SAMLRequest')))
          request_id = xml[/\sID=['"]([^'"]+)['"]/, 1]
          assertion = idp.response(in_response_to: request_id, acs_url: acs, audience: audience, conditions_expiry: nil)
          form = %(<form method="post" action="#{acs}"><input type="hidden" name="SAMLResponse" value="#{CGI.escapeHTML(assertion)}"><button>Return signed assertion</button></form>)
          [200, { 'content-type' => 'text/html', 'cache-control' => 'no-store' }, [form]]
        else
          if req.post? && req.path == '/auth/sso/saml/callback'
            observations[:post_cookie] = env['HTTP_COOKIE'].to_s.include?('saml.browser.session=')
            response = sp.call(env)
            observations[:post_authenticated] = !env['omniauth.auth'].nil?
            response
          else
            sp.call(env)
          end
        end
      end
      server.run
      begin
        Open3.popen3('node', File.join(__dir__, 'saml_callback.mjs'), sp_origin, idp_origin, pgroup: true) do |stdin, stdout, stderr, child|
          stdin.close
          out = Thread.new { stdout.read }
          err = Thread.new { stderr.read }
          begin
            status = Timeout.timeout(105) { child.value }
            expect(status.success?).to be(true), "Browser harness failed:\n#{err.value}\n#{out.value}"
            results = JSON.parse(out.value)
            puts "Browser evidence: #{JSON.generate(results)}"
            expected_results = %w[chromium firefox webkit].product(%w[Lax None Strict])
            actual_results = results.map do |result|
              [result['browser'], result['sameSite']]
            end
            expect(actual_results).to eq(expected_results)
            expect(results.map { |result| result['status'] }).to all(eq('passed'))
          ensure
            if child.alive?
              Process.kill('KILL', -child.pid)
              child.join
            end
            out.join
            err.join
          end
        end
      ensure
        server.stop(true)
      end
    end
  ensure
    saved&.each { |key, value| config.public_send(:"#{key}=", value) }
  end
end
