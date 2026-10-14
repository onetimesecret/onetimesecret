# frozen_string_literal: true

require 'base64'
require 'json'
require 'securerandom'
require 'uri'
require 'rack/mock'
require 'omniauth-entra-id'

# Opt-in diagnostics only: requiring this file neither boots OTS nor sends a request.
module EntraTokenExchangeDiagnostic
  class Report
    def initialize(stored:, host:, route:, output:, mode:, injected:)
      @expected     = stored.to_omniauth_options
      @token_url    = "https://login.microsoftonline.com/#{@expected.fetch(:tenant_id)}/oauth2/v2.0/token"
      @redirect_uri = "https://#{host}/auth/sso/#{route}/callback"
      @output       = output
      @metadata     = {
        diagnostic: 'entra_token_exchange',
        mode: mode,
        pid: Process.pid,
        probe_id: SecureRandom.hex(8),
        tenant_config_in_request: injected,
      }
    end

    def request(env)
      form          = URI.decode_www_form(env.body.to_s).to_h
      header        = env.request_headers['Authorization'].to_s
      id            = @expected.fetch(:client_id)
      secret        = @expected.fetch(:client_secret)
      raw_basic     = "Basic #{Base64.strict_encode64("#{id}:#{secret}")}"
      encoded_basic = "Basic #{Base64.strict_encode64("#{URI.encode_www_form_component(id)}:#{URI.encode_www_form_component(secret)}")}"
      scheme        = if header.start_with?('Basic ')
        'basic'
      elsif header.empty?
        'none'
      else
        'other'
      end
      emit(
        event: 'request',
        token_endpoint_matches_stored: env.url.to_s == @token_url,
        authorization_scheme: scheme,
        raw_basic_matches_stored: header == raw_basic,
        form_encoded_basic_matches_stored: header == encoded_basic,
        body_client_id_present: form.key?('client_id'),
        body_secret_present: form.key?('client_secret'),
        body_client_id_matches_stored: form['client_id'] == id,
        body_secret_matches_stored: form['client_secret'] == secret,
        authorization_code_grant: form['grant_type'] == 'authorization_code',
        client_credentials_grant: form['grant_type'] == 'client_credentials',
        code_present: !form['code'].to_s.empty?,
        code_verifier_present: !form['code_verifier'].to_s.empty?,
        redirect_uri_matches_expected: form['redirect_uri'] == @redirect_uri,
      )
    rescue StandardError => ex
      failure(ex)
    end

    def response(env)
      body        = env.body.is_a?(String) ? JSON.parse(env.body) : env.body
      description = body.is_a?(Hash) ? body['error_description'].to_s : ''
      emit(
        event: 'response',
        http_status: env.status,
        access_token_present: body.is_a?(Hash) && body.key?('access_token'),
        aadsts_code: description[/AADSTS[0-9]+/],
      )
    rescue StandardError => ex
      failure(ex)
    end

    def failure(error)
      emit(event: 'exception', exception_class: error.class.name)
    end

    def emit(fields)
      @output.puts(JSON.generate(@metadata.merge(fields)))
    rescue StandardError
      # A broken diagnostic sink must not change the sign-in outcome.
      nil
    end
  end

  # Appended after the existing request middleware, immediately before the adapter.
  # It reads the encoded request, forwards it unchanged, and returns the response.
  class WireReport < Faraday::Middleware
    def initialize(app, report)
      super(app)
      @report = report
    end

    def on_request(env)
      @report.request(env)
    end

    def on_complete(env)
      @report.response(env)
    end

    def on_error(error)
      @report.failure(error)
    end
  end

  module StrategyObservation
    def client
      result = super
      result.connection.builder.use(WireReport, @entra_diagnostic_report) if @entra_diagnostic_report
      result
    end

    protected

    def build_access_token
      previous                   = @entra_diagnostic_report
      @entra_diagnostic_report ||= EntraTokenExchangeDiagnostic.callback_report(self)
      super
    ensure
      @entra_diagnostic_report = previous
    end
  end

  class << self
    # Uses the registered middleware's options, not a freshly invented strategy config.
    # This deliberately retains client_credentials so it can be compared with A/B.
    def probe(domain:, output: $stdout)
      install_strategy_observation
      stored                        = load_stored(domain.identifier)
      route                         = stored.platform_route_name
      env                           = Rack::MockRequest.env_for("https://#{domain.display_domain}/auth/sso/#{route}/callback")
      env['rack.session']           = {}
      env['onetime.display_domain'] = domain.display_domain
      rodauth                       = Auth::Router.rodauth.new(Auth::Router.new(env))
      middleware                    = rodauth.send(:omniauth_app)
      until middleware.is_a?(OmniAuth::Strategies::EntraId) && middleware.options.name.to_s == route.to_s
        middleware = middleware.instance_variable_get(:@app)
        raise 'No registered Entra strategy for this route' unless middleware
      end
      strategy                               = middleware.dup
      strategy.instance_variable_set(:@env, env)
      env['omniauth.strategy']               = strategy
      Auth::Config::Hooks::OmniAuthTenant.inject_tenant_credentials(stored, Rack::Request.new(env), rodauth)
      report                                 = Report.new(
        stored: stored,
        host: domain.display_domain,
        route: route,
        output: output,
        mode: 'console_client_credentials',
        injected: true,
      )
      strategy.instance_variable_set(:@entra_diagnostic_report, report)
      client                                 = strategy.client
      client.connection.options.timeout      = 30
      client.connection.options.open_timeout = 10
      begin
        client.client_credentials.get_token(scope: 'https://graph.microsoft.com/.default')
      rescue StandardError => ex
        report.failure(ex)
      end
      nil
    rescue StandardError => ex
      output.puts(JSON.generate(diagnostic: 'entra_token_exchange', event: 'probe_failed', exception_class: ex.class.name))
      nil
    ensure
      strategy&.instance_variable_set(:@entra_diagnostic_report, nil)
    end

    # Call in the WEB process after application registration, never just in bin/console.
    def observe!(domain_id:, host:, output: $stderr)
      install_strategy_observation
      @observer = { domain_id: domain_id.to_s, host: host.to_s, output: output }.freeze
      nil
    end

    def stop!
      @observer = nil
      nil
    end

    def callback_report(strategy)
      observer = @observer
      return unless observer

      cached = strategy.env['onetime.tenant_sso_config']
      return unless strategy.env['onetime.display_domain'].to_s == observer[:host] ||
                    cached&.domain_id.to_s == observer[:domain_id]

      stored = load_stored(observer[:domain_id])
      Report.new(
        stored: stored,
        host: observer[:host],
        route: stored.platform_route_name,
        output: observer[:output],
        mode: 'browser_authorization_code',
        injected: cached&.domain_id.to_s == observer[:domain_id],
      )
    rescue StandardError => ex
      begin
        observer[:output].puts(
          JSON.generate(
            diagnostic: 'entra_token_exchange',
            event: 'observer_failed',
            exception_class: ex.class.name,
          ),
        )
      rescue StandardError
        nil
      end
      nil
    end

    private

    def install_strategy_observation
      OmniAuth::Strategies::EntraId.prepend(StrategyObservation) unless OmniAuth::Strategies::EntraId < StrategyObservation
    end

    def load_stored(domain_id)
      stored = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
      raise 'No stored Entra SSO configuration' unless stored&.provider_type == 'entra_id'

      options = stored.to_omniauth_options
      raise 'Stored credentials are incomplete' if [:client_id, :client_secret, :tenant_id].any? { |key| options[key].to_s.empty? }

      stored
    end
  end
end
