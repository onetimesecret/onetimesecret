# spec/unit/onetime/helpers/client_ip_helpers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'onetime/helpers/client_ip_helpers'

RSpec.describe Onetime::ClientIpHelpers do
  let(:remote_addr) { '10.244.8.0' }

  def env(overrides = {})
    { 'REMOTE_ADDR' => remote_addr }.merge(overrides)
  end

  # ---------------------------------------------------------------------------
  # .extract
  # ---------------------------------------------------------------------------

  describe '.extract' do
    context 'with depth 0 (no proxy trust)' do
      it 'returns REMOTE_ADDR regardless of X-Forwarded-For' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.8.0')
        expect(described_class.extract(e, depth: 0, header: 'X-Forwarded-For'))
          .to eq('10.244.8.0')
      end

      it 'returns REMOTE_ADDR when header is absent' do
        expect(described_class.extract(env, depth: 0, header: 'X-Forwarded-For'))
          .to eq('10.244.8.0')
      end
    end

    context 'with depth 1 (standard single reverse proxy)' do
      it 'strips the rightmost proxy hop and returns the client IP' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.8.0')
        expect(described_class.extract(e, depth: 1, header: 'X-Forwarded-For'))
          .to eq('203.0.113.42')
      end

      it 'works when all IPs in chain are RFC 1918 (k8s all-private chains)' do
        e = env(
          'REMOTE_ADDR'              => '10.244.8.0',
          'HTTP_X_FORWARDED_FOR'     => '10.0.1.55, 10.244.8.0',
        )
        expect(described_class.extract(e, depth: 1, header: 'X-Forwarded-For'))
          .to eq('10.0.1.55')
      end

      it 'falls back to REMOTE_ADDR when header is absent' do
        expect(described_class.extract(env, depth: 1, header: 'X-Forwarded-For'))
          .to eq('10.244.8.0')
      end

      it 'falls back to first IP when chain is shorter than depth' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42')
        expect(described_class.extract(e, depth: 1, header: 'X-Forwarded-For'))
          .to eq('203.0.113.42')
      end
    end

    context 'with depth 2 (CDN + reverse proxy)' do
      it 'strips two rightmost hops' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42, 198.51.100.1, 10.244.8.0')
        expect(described_class.extract(e, depth: 2, header: 'X-Forwarded-For'))
          .to eq('203.0.113.42')
      end

      it 'uses first IP when chain has exactly depth IPs' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.8.0')
        expect(described_class.extract(e, depth: 2, header: 'X-Forwarded-For'))
          .to eq('203.0.113.42')
      end
    end

    context 'with Forwarded header (RFC 7239)' do
      it 'extracts client IP from Forwarded header' do
        e = env('HTTP_FORWARDED' => 'for=203.0.113.42, for=10.244.8.0')
        expect(described_class.extract(e, depth: 1, header: 'Forwarded'))
          .to eq('203.0.113.42')
      end

      it 'handles quoted IPv6 addresses' do
        e = env('HTTP_FORWARDED' => 'for="[2001:db8::1]", for=10.244.8.0')
        expect(described_class.extract(e, depth: 1, header: 'Forwarded'))
          .to eq('2001:db8::1')
      end
    end

    context 'with Both header strategy' do
      it 'prefers Forwarded over X-Forwarded-For when both present' do
        e = env(
          'HTTP_FORWARDED'         => 'for=203.0.113.42, for=10.244.8.0',
          'HTTP_X_FORWARDED_FOR'   => '198.51.100.1, 10.244.8.0',
        )
        expect(described_class.extract(e, depth: 1, header: 'Both'))
          .to eq('203.0.113.42')
      end

      it 'falls back to X-Forwarded-For when Forwarded absent' do
        e = env('HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.244.8.0')
        expect(described_class.extract(e, depth: 1, header: 'Both'))
          .to eq('198.51.100.1')
      end
    end

    context 'with malformed header values' do
      it 'returns REMOTE_ADDR for empty X-Forwarded-For' do
        e = env('HTTP_X_FORWARDED_FOR' => '')
        expect(described_class.extract(e, depth: 1, header: 'X-Forwarded-For'))
          .to eq('10.244.8.0')
      end

      it 'ignores blank entries from comma-split' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42,  , 10.244.8.0')
        expect(described_class.extract(e, depth: 1, header: 'X-Forwarded-For'))
          .to eq('203.0.113.42')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .extract_forwarded_ips / parsers
  # ---------------------------------------------------------------------------

  describe '.extract_x_forwarded_for' do
    it 'splits comma-separated IPs' do
      e = env('HTTP_X_FORWARDED_FOR' => '1.2.3.4, 5.6.7.8')
      expect(described_class.extract_x_forwarded_for(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'returns nil when header absent' do
      expect(described_class.extract_x_forwarded_for(env)).to be_nil
    end
  end

  describe '.extract_rfc7239_forwarded' do
    it 'extracts IPs from for= params' do
      e = env('HTTP_FORWARDED' => 'for=1.2.3.4; host=example.com, for=5.6.7.8')
      expect(described_class.extract_rfc7239_forwarded(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'returns nil when header absent' do
      expect(described_class.extract_rfc7239_forwarded(env)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # RackExtension mixin
  # ---------------------------------------------------------------------------

  describe 'Rack::Request#trusted_client_ip' do
    let(:rack_env) do
      {
        'REMOTE_ADDR'          => '10.244.8.0',
        'HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.8.0',
        'rack.input'           => StringIO.new,
      }
    end

    it 'is available on Rack::Request instances' do
      req = Rack::Request.new(rack_env)
      expect(req).to respond_to(:trusted_client_ip)
    end

    it 'returns REMOTE_ADDR when OT.conf has depth 0' do
      allow(Onetime::ClientIpHelpers).to receive(:site_depth).and_return(0)
      req = Rack::Request.new(rack_env)
      expect(req.trusted_client_ip).to eq('10.244.8.0')
    end

    it 'returns client IP from header when OT.conf has depth 1' do
      allow(Onetime::ClientIpHelpers).to receive(:site_depth).and_return(1)
      allow(Onetime::ClientIpHelpers).to receive(:site_header).and_return('X-Forwarded-For')
      req = Rack::Request.new(rack_env)
      expect(req.trusted_client_ip).to eq('203.0.113.42')
    end
  end
end
