# spec/unit/onetime/middleware/public_host_rewrite_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'middleware/detect_host'
require 'onetime/middleware/public_host_rewrite'

# Unit tests for PublicHostRewrite (#4223).
#
# The middleware reads what Rack::DetectHost and DomainStrategy left in the
# env, so each example hands it an env in the state those two produce. The
# request shapes themselves, through the mounted stack, are in
# apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb.
RSpec.describe Onetime::Middleware::PublicHostRewrite do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(env) { @seen_env = env; [200, {}, ['ok']] } }
  let(:enabled) { true }

  before { allow(described_class).to receive(:enabled?).and_return(enabled) }

  # An env as it stands below DomainStrategy: the received Host, the detected
  # host, and the classification.
  def classified_env(host:, detected:, strategy:, display: detected, **extra)
    Rack::MockRequest.env_for(
      'https://origin.example.test/auth',
      'HTTP_HOST' => host,
      Rack::DetectHost.result_field_name => detected,
      'onetime.display_domain' => display,
      'onetime.domain_strategy' => strategy,
      **extra,
    )
  end

  def call_with(env)
    middleware.call(env)
    @seen_env
  end

  describe 'a classified request whose Host names another host' do
    %i[canonical subdomain custom].each do |strategy|
      it "sets the Rack authority to the detected host (#{strategy})" do
        env = call_with(classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: strategy))

        expect(env['HTTP_HOST']).to eq('tenant.example.com')
        expect(env['SERVER_NAME']).to eq('tenant.example.com')
        expect(Rack::Request.new(env).host).to eq('tenant.example.com')
      end
    end

    it 'keeps the received Host under the original key' do
      env = call_with(classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: :custom))

      expect(env[described_class::ORIGINAL_HTTP_HOST]).to eq('origin.example.test:3000')
      expect(described_class.original_http_host(env)).to eq('origin.example.test:3000')
    end

    it 'writes no port, so the port of the origin hop does not carry over' do
      env = call_with(classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: :custom))

      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com')
    end

    it 'leaves SERVER_PORT as the server set it' do
      before_port = classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: :custom)['SERVER_PORT']
      env         = call_with(classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: :custom))

      expect(env['SERVER_PORT']).to eq(before_port)
    end

    it 'accepts the strategy as a String' do
      env = call_with(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: 'custom'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
    end
  end

  describe 'validated forwarded authority metadata' do
    around do |example|
      original = Rack::Request.forwarded_priority
      Rack::Request.forwarded_priority = [:x_forwarded]
      example.run
    ensure
      Rack::Request.forwarded_priority = original
    end

    def forwarded_env(authority, **extra)
      classified_env(host: 'origin.example.test:3000', detected: 'tenant.example.com', strategy: :custom,
        Rack::DetectHost.forwarded_authority_field_name => authority, **extra)
    end

    it 'preserves the public port rather than the origin-hop port' do
      env = call_with(forwarded_env('tenant.example.com:8443'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com:8443')
      expect(env['SERVER_NAME']).to eq('tenant.example.com')
      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com:8443')
      expect(described_class.original_http_host(env)).to eq('origin.example.test:3000')
    end

    it 'does not write the scheme-default port' do
      env = call_with(forwarded_env('tenant.example.com:443'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com')
    end

    it 'writes a port that is the default of the other scheme' do
      env = call_with(forwarded_env('tenant.example.com:80'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com:80')
      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com:80')
    end

    it 'uses Rack authority-port precedence over X-Forwarded-Port' do
      env = call_with(forwarded_env('tenant.example.com:8443', 'HTTP_X_FORWARDED_PORT' => '9443'))

      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com:8443')
    end

    it 'does not write an X-Forwarded-Port that DetectHost did not validate' do
      env = call_with(forwarded_env(nil, 'HTTP_X_FORWARDED_PORT' => '9443'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
    end

    # The hostname and the port in separate headers, through DetectHost.
    context 'with a bare X-Forwarded-Host and X-Forwarded-Port from a trusted proxy' do
      def detected_env(port, **extra)
        env = classified_env(host: 'origin.example.test:3000', detected: nil, display: 'tenant.example.com',
          strategy: :custom, 'HTTP_X_FORWARDED_HOST' => 'tenant.example.com',
          'HTTP_X_FORWARDED_PORT' => port, 'REMOTE_ADDR' => '127.0.0.1', **extra)
        Rack::DetectHost.new(->(_env) { [200, {}, []] }).call(env)
        env.delete('HTTP_X_FORWARDED_HOST') # as StripForwardedHost does
        env
      end

      it 'gives Rack one port for #port and #base_url' do
        request = Rack::Request.new(call_with(detected_env('8443')))

        expect(request.get_header('HTTP_HOST')).to eq('tenant.example.com:8443')
        expect(request.port).to eq(8443)
        expect(request.base_url).to eq('https://tenant.example.com:8443')
      end

      it 'writes no port when it is the scheme default' do
        request = Rack::Request.new(call_with(detected_env('443')))

        expect(request.get_header('HTTP_HOST')).to eq('tenant.example.com')
        expect(request.base_url).to eq('https://tenant.example.com')
      end

      it 'writes no port for a peer that is not a trusted proxy' do
        env = call_with(detected_env('8443', 'HTTP_HOST' => 'tenant.example.com, tenant.example.com',
          'REMOTE_ADDR' => '203.0.113.7'))

        expect(env['HTTP_HOST']).to eq('tenant.example.com')
      end
    end

    it 'does not take a port from metadata for another host' do
      env = call_with(forwarded_env('other.example.com:8443'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
    end

    it 'leaves an already matching Host and its port unchanged' do
      env = call_with(forwarded_env('tenant.example.com:8443', 'HTTP_HOST' => 'tenant.example.com:9443'))

      expect(env['HTTP_HOST']).to eq('tenant.example.com:9443')
      expect(env).not_to have_key(described_class::ORIGINAL_HTTP_HOST)
    end

    it 'does not rewrite an invalid classification even with accepted metadata' do
      env = call_with(forwarded_env('tenant.example.com:8443', 'onetime.domain_strategy' => :invalid))

      expect(env['HTTP_HOST']).to eq('origin.example.test:3000')
      expect(env).not_to have_key(described_class::ORIGINAL_HTTP_HOST)
    end

    context 'with the setting off' do
      let(:enabled) { false }

      it 'leaves the received authority unchanged' do
        env = call_with(forwarded_env('tenant.example.com:8443'))

        expect(env['HTTP_HOST']).to eq('origin.example.test:3000')
        expect(env).not_to have_key(described_class::ORIGINAL_HTTP_HOST)
      end
    end
  end

  describe 'a Host that Rack cannot parse' do
    it 'is replaced by the detected host' do
      env = call_with(classified_env(host: 'tenant.example.com, tenant.example.com', detected: 'tenant.example.com', strategy: :custom))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
      expect(env[described_class::ORIGINAL_HTTP_HOST]).to eq('tenant.example.com, tenant.example.com')
      expect(Rack::Request.new(env).base_url).to eq('https://tenant.example.com')
    end

    it 'does not take a port from it' do
      env = call_with(classified_env(host: 'tenant.example.com:8443, tenant.example.com:8443', detected: 'tenant.example.com', strategy: :custom))

      expect(env['HTTP_HOST']).to eq('tenant.example.com')
    end
  end

  describe 'requests left as received' do
    def expect_untouched(env)
      received = env['HTTP_HOST']
      name     = env['SERVER_NAME']
      seen     = call_with(env)

      expect(seen['HTTP_HOST']).to eq(received)
      expect(seen['SERVER_NAME']).to eq(name)
      expect(seen).not_to have_key(described_class::ORIGINAL_HTTP_HOST)
      expect(described_class.original_http_host(seen)).to eq(received)
    end

    it 'Host already names the detected host' do
      expect_untouched(classified_env(host: 'tenant.example.com', detected: 'tenant.example.com', strategy: :custom))
    end

    it 'Host already names the detected host, with a port' do
      expect_untouched(classified_env(host: 'tenant.example.com:8443', detected: 'tenant.example.com', strategy: :custom))
    end

    it 'Host names the detected host in another case' do
      expect_untouched(classified_env(host: 'Tenant.Example.COM', detected: 'tenant.example.com', strategy: :custom))
    end

    it 'an :invalid classification' do
      expect_untouched(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: :invalid))
    end

    it 'no classification' do
      expect_untouched(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: nil))
    end

    it 'a classification this middleware does not know' do
      expect_untouched(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: :default))
    end

    it 'no detected host' do
      expect_untouched(classified_env(host: 'localhost:3000', detected: nil, display: 'canonical.example.org', strategy: :canonical))
    end

    it 'a detected host that is not a valid hostname' do
      expect_untouched(classified_env(host: 'origin.example.test', detected: 'bad host', display: 'bad host', strategy: :canonical))
    end

    it 'a display domain that is not the detected host' do
      # Domains feature off: the display domain is site.host whatever the
      # request named.
      expect_untouched(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', display: 'site.example.net', strategy: :canonical))
    end

    it 'X-Forwarded-Host still in the env' do
      expect_untouched(
        classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: :custom,
          'HTTP_X_FORWARDED_HOST' => 'tenant.example.com'),
      )
    end

    it 'Forwarded still in the env' do
      expect_untouched(
        classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: :custom,
          'HTTP_FORWARDED' => 'host=tenant.example.com'),
      )
    end

    context 'with the setting off' do
      let(:enabled) { false }

      it 'a classified request whose Host names another host' do
        expect_untouched(classified_env(host: 'origin.example.test', detected: 'tenant.example.com', strategy: :custom))
      end
    end
  end

  describe 'a display domain that carries a port' do
    it 'matches the detected host on the hostname' do
      env = call_with(
        classified_env(host: 'site.example.net, site.example.net', detected: 'site.example.net',
          display: 'site.example.net:443', strategy: :canonical),
      )

      expect(env['HTTP_HOST']).to eq('site.example.net')
    end
  end

  describe '.enabled?' do
    before { allow(described_class).to receive(:enabled?).and_call_original }

    it 'is true only for a literal true' do
      allow(OT).to receive(:conf).and_return('site' => { 'network' => { 'public_host_rewrite' => true } })
      expect(described_class.enabled?).to be(true)

      allow(OT).to receive(:conf).and_return('site' => { 'network' => { 'public_host_rewrite' => 'true' } })
      expect(described_class.enabled?).to be(false)
    end

    it 'is false when the setting or the configuration is absent' do
      allow(OT).to receive(:conf).and_return('site' => {})
      expect(described_class.enabled?).to be(false)

      allow(OT).to receive(:conf).and_return(nil)
      expect(described_class.enabled?).to be(false)
    end
  end
end
