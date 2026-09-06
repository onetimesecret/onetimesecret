# spec/unit/onetime/initializers/configure_rack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/initializers/configure_rack'

# Pins the process-wide Rack::Request forwarding policy.
#
# Rack 3.2 defaults `forwarded_priority` to `[:forwarded, :x_forwarded]`, so
# an RFC 7239 `Forwarded` header from ANY client outranks the X-Forwarded-*
# family the proxy actually manages. Caddy does not strip an unmanaged
# `Forwarded`, which leaves `request.host` resolvable to a client-chosen
# authority. The initializer pins the priority to `[:x_forwarded]`; these
# examples verify both the setting and its observable effect on
# Rack::Request#host.
RSpec.describe Onetime::Initializers::ConfigureRack do
  let(:instance) { described_class.new }
  let(:context) { {} }
  let(:logger) { instance_double(SemanticLogger::Logger, debug: nil) }

  before do
    allow(Onetime).to receive(:boot_logger).and_return(logger)
  end

  around do |example|
    original = Rack::Request.forwarded_priority
    example.run
  ensure
    Rack::Request.forwarded_priority = original
  end

  describe 'metadata' do
    it 'provides the :rack_request_policy capability' do
      expect(described_class.provides).to eq([:rack_request_policy])
    end

    it 'has no dependencies so it runs in every boot mode, including connect_to_db=false' do
      expect(described_class.depends_on).to be_nil.or be_empty
    end

    it 'is NOT fork-sensitive: class-level Rack state is inherited by forked workers' do
      expect(described_class.phase).to eq(:preload)
    end
  end

  describe '#execute' do
    it 'pins forwarded_priority to the X-Forwarded-* family only' do
      Rack::Request.forwarded_priority = [:forwarded, :x_forwarded]
      instance.execute(context)
      expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
    end

    it 'assigns a fresh array rather than the frozen constant' do
      instance.execute(context)
      expect(Rack::Request.forwarded_priority).not_to be_frozen
    end

    it 'keeps the source constant frozen' do
      expect(described_class::FORWARDED_PRIORITY).to be_frozen
    end

    it 'is idempotent' do
      instance.execute(context)
      instance.execute(context)
      expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
    end

    context 'with a client-supplied Forwarded header' do
      let(:env) do
        Rack::MockRequest.env_for(
          'http://onetime.test/',
          'HTTP_HOST' => 'onetime.test',
          'HTTP_FORWARDED' => 'host=evil.example.com;proto=https',
        )
      end

      it 'under the Rack default, a client Forwarded header poisons request.host' do
        Rack::Request.forwarded_priority = [:forwarded, :x_forwarded]
        expect(Rack::Request.new(env).host).to eq('evil.example.com')
      end

      it 'after the initializer, Forwarded is never consulted for request.host' do
        instance.execute(context)
        expect(Rack::Request.new(env).host).to eq('onetime.test')
      end

      it 'still honors the proxy-managed X-Forwarded-Host (gated upstream by StripForwardedHost)' do
        instance.execute(context)
        env['HTTP_X_FORWARDED_HOST'] = 'tenant.example.com'
        expect(Rack::Request.new(env).host).to eq('tenant.example.com')
      end

      it 'also stops reading the Forwarded proto parameter for request.scheme' do
        # forwarded_priority governs every forwarded_* reader, not just the
        # authority. A Forwarded-only proxy must emit X-Forwarded-Proto.
        instance.execute(context)
        expect(Rack::Request.new(env).scheme).to eq('http')
      end

      it 'still resolves scheme from the proxy-managed X-Forwarded-Proto' do
        instance.execute(context)
        env['HTTP_X_FORWARDED_PROTO'] = 'https'
        expect(Rack::Request.new(env).scheme).to eq('https')
      end
    end
  end
end
