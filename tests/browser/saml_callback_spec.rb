# frozen_string_literal: true

# rubocop:disable ThreadSafety/NewThread -- Bounded fixture server and pipe readers are joined during teardown.

# Browser lane only: tests/lanes/run browser [--only tests/browser/saml_callback_spec.rb].
# This is a production middleware/strategy stack, NOT Auth::Application: the
# lane is simple-mode and has no auth SQL service, Rodauth hooks or account rows.
require 'spec_helper'
require 'puma'
require 'puma/minissl'
require 'rack/protection'
require 'open3'
require 'timeout'
require 'tmpdir'
require 'cgi'
require 'zlib'
require 'socket'
require 'climate_control'
require 'middleware/detect_host'
require 'onetime/session'
require 'onetime/middleware/domain_strategy'
require 'onetime/middleware/public_host_rewrite'
require 'onetime/middleware/saml_callback_transport'
require 'onetime/sso_provider/request_bound_saml'
require 'onetime/sso_provider/saml'
require_relative '../../apps/web/auth/lib/public_host'
require_relative '../../spec/support/saml/test_idp'

module SamlBrowserSpec
  def self.capture(*command, timeout: 195)
    Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, child|
      stdin.close
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }
      begin
        Timeout.timeout(timeout) { [child.value, out.value, err.value] }
      ensure
        # A crashed/watchdog-exited parent may leave descendants holding the
        # pipes open. Reap the process group even when the parent is gone.
        begin
          Process.kill('KILL', -child.pid)
        rescue Errno::ESRCH
          # A normally completed harness has already closed its whole group.
        end
        child.join(5)
        [out, err].each { |reader| reader.join(1) || reader.kill.join }
      end
    end
  end

  # All browser-visible hosts are reserved example domains. CONNECT maps only
  # the explicit fixture authorities to our loopback TLS listener: no DNS,
  # hosts-file edits, external IdP, or forwarding to an arbitrary destination.
  class LoopbackProxy
    attr_reader :url

    def initialize(authorities, tls_port)
      @authorities = authorities
      @tls_port    = tls_port
      @listener    = TCPServer.new('127.0.0.1', 0)
      @url         = "http://127.0.0.1:#{@listener.addr[1]}"
      @clients     = []
      @workers     = []
      @mutex       = Mutex.new
      @acceptor    = Thread.new do
        loop do
          client = @listener.accept
          @mutex.synchronize do
            @clients << client
            @workers << Thread.new { tunnel(client) }
          end
        end
      rescue IOError, Errno::EBADF
        # Closing the listener ends accept during teardown.
      end
    end

    def stop
      @listener.close
      @acceptor.join(1) || @acceptor.kill.join
      @mutex.synchronize { @clients.each { |client| client.close unless client.closed? } }
      @workers.each { |worker| worker.join(1) || worker.kill.join }
    end

    private

    def tunnel(client)
      upstream = nil
      Timeout.timeout(180) do
        header = +''
        Timeout.timeout(5) do
          header << client.readpartial(1) until header.end_with?("\r\n\r\n") || header.bytesize > 4096
        end
        method, authority = header.lines.first.to_s.split
        unless method == 'CONNECT' && @authorities.include?(authority)
          client.write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
          return
        end

        upstream = TCPSocket.new('127.0.0.1', @tls_port)
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
        loop do
          readable = IO.select([client, upstream], nil, nil, 5)
          next unless readable

          readable.first.each do |source|
            destination = source == client ? upstream : client
            destination.write(source.readpartial(16_384))
          end
        end
      end
    rescue IOError, SystemCallError, Timeout::Error
      # Browsers close persistent tunnels between isolated contexts.
    ensure
      upstream&.close
      client.close unless client.closed?
    end
  end
end

# rubocop:disable-next RSpec/SpecFilePathFormat -- The browser lane owns this named transport harness.
RSpec.describe Onetime::Middleware::SamlCallbackTransport, lane_env: { 'SAML_ENABLED' => 'true' } do
  # Each matrix run owns global fixture configuration and a bounded child.
  # rubocop:disable-next Metrics/MethodLength, Metrics/PerceivedComplexity -- Keep the fixture's closures and cleanup in one failure-injectable scope.
  def run_browser_matrix
    config                             = OmniAuth.config
    saved                              = [:on_failure, :request_validation_phase, :logger, :test_mode, :full_host].to_h { |key| [key, config.public_send(key)] }
    domain_state                       = Onetime::Middleware::DomainStrategy.instance_variables.to_h do |key|
      [key, Onetime::Middleware::DomainStrategy.instance_variable_get(key)]
    end
    encryption                         = [Familia.config.encryption_keys, Familia.config.current_key_version]
    config.test_mode                   = false
    config.request_validation_phase    = nil # Initiation CSRF is outside this transport harness.
    config.logger                      = Logger.new(File::NULL)
    # The production full_host resolver uses this same allowlist, including
    # when rewriting is off. No host/classification/route predicate is stubbed.
    config.full_host                   = ->(env) { Auth::PublicHost.required_base_url!(env) }
    prefix                             = "spec:browser:saml:#{SecureRandom.hex(8)}"
    stub_const('Onetime::Security::SamlCallbackStore::PREFIX', "#{prefix}:callback")
    stub_const('Onetime::Security::SamlAssertionReplayGuard::KEY_PREFIX', "#{prefix}:assertion")
    Familia.config.encryption_keys     = { browser: Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    Familia.config.current_key_version = :browser
    idp                                = SamlSpec::TestIdp.new
    completion_gate                    = nil
    server_thread                      = nil

    Dir.mktmpdir('saml-browser') do |directory|
      key_path                                            = File.join(directory, 'key.pem')
      cert_path                                           = File.join(directory, 'cert.pem')
      File.write(key_path, idp.key.to_pem, perm: 0o600)
      File.write(cert_path, idp.cert_pem)
      tls                                                 = Puma::MiniSSL::Context.new
      tls.key                                             = key_path
      tls.cert                                            = cert_path
      rack_app                                            = nil
      server                                              = Puma::Server.new(->(env) { rack_app.call(env) }, nil, log_writer: Puma::LogWriter.strings, force_shutdown_after: 5)
      server.add_ssl_listener('127.0.0.1', 0, tls)
      port                                                = server.connected_ports.first
      hosts                                               = {
        canonical: 'sp.example.com',
        tenant: "tenant-#{SecureRandom.hex(6)}.example.net",
        idp: 'idp.example.org',
        unconfigured_idp: 'other-idp.example.org',
        origin: 'origin.example.com',
      }
      origins                                             = hosts.transform_values { |host| "https://#{host}:#{port}" }
      fixture_config                                      = Marshal.load(Marshal.dump(OT.conf))
      fixture_config['site']['host']                      = "#{hosts[:canonical]}:#{port}"
      fixture_config['site']['ssl']                       = true
      fixture_config['site']['session']['secure']         = true
      fixture_config['site']['session']['same_site']      = 'lax'
      fixture_config['site']['authentication']['enabled'] = true
      fixture_config['site']['network']                 ||= {}
      fixture_config['features']['domains']               = { 'enabled' => true, 'default' => hosts[:canonical] }
      allow(Onetime).to receive(:conf).and_return(fixture_config)
      allow(Onetime::Runtime).to receive(:features).and_return(Onetime::Runtime.features.with(domains_enabled: true))
      # Simple-mode deliberately disables platform SSO. Override only this
      # availability flag; keep real origin derivation and route admission.
      allow(Onetime.auth_config).to receive(:sso_enabled?).and_return(true)

      domain          = Onetime::CustomDomain.new(display_domain: hosts[:tenant], org_id: SecureRandom.uuid)
      domain.verified = true
      domain.save
      Onetime::CustomDomain.display_domain_index.put(hosts[:tenant], domain.identifier)
      proxy           = SamlBrowserSpec::LoopbackProxy.new(origins.values.map { |origin| URI.parse(origin).authority }, port)
      ClimateControl.modify(
        SAML_IDP_SSO_SERVICE_URL: "#{origins[:idp]}/idp",
        SAML_IDP_ENTITY_ID: idp.entity_id,
        SAML_IDP_CERT: idp.cert_pem,
        SAML_ENABLED: 'true',
      ) do
        tenant_config = Onetime::CustomDomain::SsoConfig.create!(
          domain_id: domain.identifier,
          provider_type: 'saml',
          enabled: true,
          idp_sso_service_url: "#{origins[:idp]}/idp",
          idp_entity_id: idp.entity_id,
          idp_cert: idp.cert_pem,
        )
        scenarios     = %w[Lax None Strict].map do |policy|
          { id: "direct-canonical-#{policy}", surface: 'canonical', sameSite: policy, proxy: false, postRewrite: false, getRewrite: false }
        end
        %w[canonical tenant].each do |surface|
          [false, true].product([false, true]).each do |post_rewrite, get_rewrite|
            policies = surface == 'tenant' ? %w[Lax None Strict] : ['Lax']
            policies.each do |policy|
              scenarios << {
                id: "proxy-#{surface}-#{post_rewrite}-#{get_rewrite}-#{policy}",
                surface: surface,
                sameSite: policy,
                proxy: true,
                postRewrite: post_rewrite,
                getRewrite: get_rewrite,
                bindingControls: policy == 'Lax' && !post_rewrite && get_rewrite,
              }
            end
          end
        end
        %w[unconfigured-origin switched-off].each do |control|
          scenarios << {
            id: control,
            surface: 'canonical',
            sameSite: 'None',
            proxy: true,
            postRewrite: true,
            getRewrite: true,
            refusal: control == 'switched-off' ? 404 : 403,
          }
        end
        # B-01 characterizes the existing port-less Origin policy, not a new
        # defect: proxy-authority-header.md documents rewrite off/refused and
        # on/admitted. Preserve public Host or opt in to rewriting to initiate.
        scenarios << {
          id: 'B-01-initiation-port-rewrite-off',
          surface: 'canonical',
          sameSite: 'Lax',
          proxy: true,
          postRewrite: false,
          getRewrite: false,
          initiationRefusal: 403,
        }
        observations    = {}
        current         = nil
        completion_gate = nil
        pending_sid     = nil
        snapshot        = ->(env) do
          request = Rack::Request.new(env)
          {
            detectedHost: env[Rack::DetectHost.result_field_name],
            displayHost: env['onetime.display_domain'],
            strategy: env['onetime.domain_strategy'].to_s,
            rackHost: request.host,
            rackBase: request.base_url,
            originalHost: Onetime::Middleware::PublicHostRewrite.original_http_host(env),
            rewritten: env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST),
            forwardedHostRemoved: !env.key?('HTTP_X_FORWARDED_HOST'),
            scope: Onetime::Security::SamlCallbackStore.scope(env),
            tenantResolved: env['onetime.custom_domain_id'] == domain.identifier,
          }
        end
        evidence = ->(env) do
          {
            **observations,
            method: env['REQUEST_METHOD'],
            cookie: env['HTTP_COOKIE'].to_s.include?('saml.browser.session='),
            originalSession: env['rack.session']['browser_original'] == 'original',
            pendingRequest: !env['rack.session'][OmniAuth::Strategies::RequestBoundSAML::REQUEST_ID_KEY].nil?,
            failure: env['omniauth.error.type']&.to_s,
            host: snapshot.call(env),
          }
        end
        html              = ->(title, env) do
          "<h1>#{title}</h1><pre data-testid=\"evidence\">#{CGI.escapeHTML(JSON.generate(evidence.call(env)))}</pre><a href=\"/probe\">Leave callback</a>"
        end
        config.on_failure = ->(env) { [401, { 'content-type' => 'text/html' }, [html.call('Refused', env)]] }
        apps              = [:canonical, :tenant].to_h do |surface|
          origin  = origins.fetch(surface)
          options = surface == :canonical ? Onetime::SsoProvider::Saml.platform_options : tenant_config.to_omniauth_options
          # Explicit fixture registration replaces Rodauth's tenant setup
          # hook, not the production route/origin/host/session decisions.
          options = options.merge(
            name: 'saml',
            path_prefix: '/auth/sso',
            sp_entity_id: "#{origin}/auth/sso/saml/metadata",
            assertion_consumer_service_url: "#{origin}/auth/sso/saml/callback",
          ).except(:strategy)
          app     = Rack::Builder.new do
            use Rack::DetectHost, logger: config.logger
            use Onetime::Middleware::StripForwardedHost
            use Onetime::Middleware::SamlCallbackTransport::Boundary
            use Onetime::Session, key: 'saml.browser.session', secret: 'x' * 64, namespace: "#{prefix}:session", same_site: :lax, secure: true, expire_after: 300
            use Onetime::Middleware::DomainStrategy
            use Onetime::Middleware::PublicHostRewrite
            use Rack::Protection::HttpOrigin, **Onetime::Middleware::HttpOriginOptions.options
            use(
              Class.new do
                              define_method(:initialize) { |downstream| @app = downstream }
                              define_method(:call) do |env|
                                if Onetime::Middleware::SamlCallbackTransport.callback_post?(env)
                                  observations[:postHost]           = snapshot.call(env)
                                  observations[:postSession]        = env['rack.session']['browser_original'] == 'original'
                                  observations[:postBoundaryCookie] = env['HTTP_COOKIE'].to_s.include?('saml.browser.session=')
                                end
                                @app.call(env)
                              end
              end,
            )
            use Onetime::Middleware::SamlCallbackTransport::Stage
            use OmniAuth::Strategies::RequestBoundSAML, **options
            run ->(env) {
              if env['PATH_INFO'] == '/start'
                env['rack.session']['browser_original'] = 'original'
                [200, { 'content-type' => 'text/html' }, ['<form method="post" action="/auth/sso/saml"><button>Start SAML sign-in</button></form>']]
              elsif env['PATH_INFO'] == '/probe'
                [200, { 'content-type' => 'text/html' }, [html.call('Session probe', env) + "<p data-testid=\"referrer\">#{env['HTTP_REFERER'].to_s.empty? ? 'absent' : 'present'}</p>"]]
              elsif env['omniauth.auth']
                [200, { 'content-type' => 'text/html' }, [html.call('Assertion accepted', env)]]
              else
                [404, { 'content-type' => 'text/plain' }, ['Not found']]
              end
            }
          end.to_app
          [hosts.fetch(surface), app]
        end
        rack_app = ->(env) do
          request      = Rack::Request.new(env)
          browser_host = request.host
          if [hosts[:idp], hosts[:unconfigured_idp]].include?(browser_host) && request.path == '/idp'
            inflater  = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            begin
              xml = inflater.inflate(Base64.decode64(request.params.fetch('SAMLRequest')))
            ensure
              inflater.close
            end
            acs       = xml[/AssertionConsumerServiceURL=['"]([^'"]+)['"]/, 1]
            audience  = CGI.unescapeHTML(xml[%r{<saml:Issuer[^>]*>([^<]+)</saml:Issuer>}, 1])
            assertion = idp.response(in_response_to: xml[/\sID=['"]([^'"]+)['"]/, 1], acs_url: acs, audience: audience, conditions_expiry: nil)
            form      = %(<form method="post" action="#{CGI.escapeHTML(acs)}">) +
                        %(<input type="hidden" name="SAMLResponse" value="#{CGI.escapeHTML(assertion)}">) +
                        '<button>Return signed assertion</button></form>'
            [200, { 'content-type' => 'text/html', 'cache-control' => 'no-store' }, [form]]
          elsif apps.key?(browser_host)
            if request.path == '/start'
              current = scenarios.find { |scenario| scenario[:id] == request.params['scenario'] }
              raise 'Unknown browser scenario' unless current

              observations.clear
              completion_gate     = Queue.new
              pending_sid         = nil
              ENV['SAML_ENABLED'] = 'true'
            end
            if request.path == '/__fixture/release' && request.post?
              pending_sid = nil
              completion_gate << true
              next [200, { 'content-type' => 'text/plain' }, ['Released']]
            end
            if request.path == '/auth/sso/saml' && request.post?
              pending_sid = request.cookies['saml.browser.session']
            end
            # Browser redirect interception does not run consistently on
            # WebKit. Delay only the rightful browser's natural GET until
            # the separate-context binding probes finish (bounded to 15s).
            if request.get? && described_class.callback?(env) && current[:bindingControls] &&
               browser_host == hosts.fetch(current[:surface].to_sym) &&
               request.cookies['saml.browser.session'] == pending_sid && !pending_sid.nil?
              Timeout.timeout(15) { completion_gate.pop }
            end
            callback                                                 = described_class.callback?(env)
            # The callback matrix isolates POST/GET settings. Initiation
            # uses rewrite on because this listener has a non-default port;
            # B-01 above exercises the real rewrite-off initiation refusal.
            rewrite                                                  = if callback
                        request.get? ? current.fetch(:getRewrite) : current.fetch(:postRewrite)
                      else
                        !current[:initiationRefusal]
                      end
            fixture_config['site']['network']['public_host_rewrite'] = rewrite
            ENV['SAML_ENABLED']                                      = 'false' if callback && request.post? && current[:id] == 'switched-off'
            if current.fetch(:proxy)
              # Fixture ingress overwrites forwarded authority like a proxy;
              # the real peer is loopback (DetectHost's bare-stack trust rule).
              env['HTTP_X_FORWARDED_HOST'] = env['HTTP_HOST']
              env['HTTP_HOST']             = "#{hosts[:origin]}:#{port}"
              env['SERVER_NAME']           = hosts[:origin]
            end
            if callback && request.post?
              observations[:postCookie] = env['HTTP_COOKIE'].to_s.include?('saml.browser.session=')
              observations[:postOrigin] = env['HTTP_ORIGIN']
            end
            response                                                 = apps.fetch(browser_host).call(env)
            observations[:postAuthenticated]                         = !env['omniauth.auth'].nil? if callback && request.post?
            response
          else
            [404, { 'content-type' => 'text/plain' }, ['Not found']]
          end
        end
        server_thread    = server.run
        manifest         = { origins: origins, proxy: proxy.url, scenarios: scenarios }
        status, out, err = SamlBrowserSpec.capture('node', File.join(__dir__, 'saml_callback.mjs'), JSON.generate(manifest))
        expect(status.success?).to be(true), "Browser harness failed:\n#{err}\n#{out}"
        results          = JSON.parse(out)
        results.each do |result|
          summary = result.slice(
            'browser',
            'version',
            'scenario',
            'sameSite',
            'status',
            'bindingChecks',
            'replayChecks',
            'postCookie',
            'cookie',
            'originalSession',
            'error',
            'at',
          )
          RSpec.configuration.reporter.message "Browser evidence: #{JSON.generate(summary)}"
        end
        expected_results = %w[chromium firefox webkit].product(scenarios.map { |scenario| scenario[:id] })
        expect(results.map { |result| [result['browser'], result['scenario']] }).to eq(expected_results)
        expect(results.reject { |result| result['status'] == 'passed' }).to be_empty
      end
    ensure
        completion_gate << true if completion_gate
        begin
          if server_thread
            server.stop(true)
          elsif server
            # Setup can fail after binding TLS but before starting Puma.
            server.binder.ios.each { |io| io.close unless io.closed? }
          end
        ensure
          begin
            proxy&.stop
          ensure
            begin
              domain&.destroy!
            ensure
              # Delete only this run's keys, even if another cleanup failed.
              Familia.dbclient.scan_each(match: "#{prefix}:*") { |key| Familia.dbclient.del(key) }
            end
          end
        end
    end
  ensure
    saved&.each { |key, value| config.public_send(:"#{key}=", value) }
    if domain_state
      domain_state.each { |key, value| Onetime::Middleware::DomainStrategy.instance_variable_set(key, value) }
    end
    if encryption
      Familia.config.encryption_keys, Familia.config.current_key_version = encryption
    end
  end

  # rubocop:disable-next RSpec/NoExpectationExample -- The matrix helper asserts every independently reported browser case.
  it 'classifies direct/proxied hosts and preserves callback sessions across rewrite off/on and SameSite controls' do
    run_browser_matrix
  end

  it 'bounds inherited output pipes after the Node parent exits' do
    # A bounded descendant reproduces the watchdog/crash path: waiting only
    # for the parent does not bound reads while another process owns its pipes.
    script = <<~JS
      const { spawn } = require('node:child_process');
      spawn(process.execPath, ['-e', 'setTimeout(() => {}, 10000)'], { stdio: 'inherit' });
      process.exit(0);
    JS
    expect { SamlBrowserSpec.capture('node', '-e', script, timeout: 0.5) }.to raise_error(Timeout::Error)
  end

  # rubocop:disable-next RSpec/ExampleLength, RSpec/MultipleExpectations -- Verify every acquired resource and manually changed global on setup failure.
  it 'cleans partial fixture setup and restores global state when proxy creation fails' do
    domain = nil
    server = nil
    port   = nil

    saved                                                                                                  = [:on_failure, :request_validation_phase, :logger, :test_mode, :full_host].to_h do |key|
      [key, OmniAuth.config.public_send(key)]
    end
    domain_state                                                                                           = Onetime::Middleware::DomainStrategy.instance_variables.to_h do |key|
      [key, Onetime::Middleware::DomainStrategy.instance_variable_get(key)]
    end
    encryption                                                                                             = [Familia.config.encryption_keys, Familia.config.current_key_version]
    allow(Puma::Server).to(receive(:new).and_wrap_original { |original, *args, **kwargs| server            = original.call(*args, **kwargs) })
    allow(Onetime::CustomDomain).to(receive(:new).and_wrap_original { |original, *args, **kwargs| domain ||= original.call(*args, **kwargs) })
    allow(SamlBrowserSpec::LoopbackProxy).to receive(:new) do |_authorities, tls_port|
      port = tls_port
      raise IOError, 'Injected proxy setup failure'
    end

    expect { run_browser_matrix }.to raise_error(IOError, 'Injected proxy setup failure')
    expect(domain.exists?).to be(false)
    expect(Onetime::CustomDomain.display_domain_index.get(domain.display_domain)).to be_nil
    expect { TCPSocket.open('127.0.0.1', port, &:close) }.to raise_error(Errno::ECONNREFUSED)
    saved.each { |key, value| expect(OmniAuth.config.public_send(key)).to eq(value) }
    domain_state.each { |key, value| expect(Onetime::Middleware::DomainStrategy.instance_variable_get(key)).to eq(value) }
    expect([Familia.config.encryption_keys, Familia.config.current_key_version]).to eq(encryption)
  ensure
    # Keep the failure-injection test safe even if its cleanup assertions fail.
    server.binder.ios.each { |io| io.close unless io.closed? } if server
    domain&.destroy!
  end
end
# rubocop:enable ThreadSafety/NewThread
