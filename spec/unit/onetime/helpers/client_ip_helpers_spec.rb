# spec/unit/onetime/helpers/client_ip_helpers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/helpers/client_ip_helpers'

RSpec.describe Onetime::ClientIpHelpers do
  let(:remote_addr) { '10.244.8.0' }

  def env(overrides = {})
    { 'REMOTE_ADDR' => remote_addr }.merge(overrides)
  end

  describe '.extract_forwarded_ips' do
    context 'with X-Forwarded-For header' do
      it 'extracts IPs from the header' do
        e = env('HTTP_X_FORWARDED_FOR' => '203.0.113.42, 10.244.8.0')
        expect(described_class.extract_forwarded_ips(e, 'X-Forwarded-For'))
          .to eq(%w[203.0.113.42 10.244.8.0])
      end

      it 'returns nil when header absent' do
        expect(described_class.extract_forwarded_ips(env, 'X-Forwarded-For'))
          .to be_nil
      end
    end

    context 'with Forwarded header (RFC 7239)' do
      it 'extracts IPs from for= params' do
        e = env('HTTP_FORWARDED' => 'for=203.0.113.42, for=10.244.8.0')
        expect(described_class.extract_forwarded_ips(e, 'Forwarded'))
          .to eq(%w[203.0.113.42 10.244.8.0])
      end

      it 'handles quoted IPv6 addresses' do
        e = env('HTTP_FORWARDED' => 'for="[2001:db8::1]", for=10.244.8.0')
        expect(described_class.extract_forwarded_ips(e, 'Forwarded'))
          .to eq(%w[2001:db8::1 10.244.8.0])
      end
    end

    context 'with Both header strategy' do
      it 'prefers Forwarded over X-Forwarded-For when both present' do
        e = env(
          'HTTP_FORWARDED'       => 'for=203.0.113.42',
          'HTTP_X_FORWARDED_FOR' => '198.51.100.1',
        )
        expect(described_class.extract_forwarded_ips(e, 'Both'))
          .to eq(%w[203.0.113.42])
      end

      it 'falls back to X-Forwarded-For when Forwarded absent' do
        e = env('HTTP_X_FORWARDED_FOR' => '198.51.100.1, 10.244.8.0')
        expect(described_class.extract_forwarded_ips(e, 'Both'))
          .to eq(%w[198.51.100.1 10.244.8.0])
      end
    end
  end

  describe '.extract_x_forwarded_for' do
    it 'splits comma-separated IPs' do
      e = env('HTTP_X_FORWARDED_FOR' => '1.2.3.4, 5.6.7.8')
      expect(described_class.extract_x_forwarded_for(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'strips whitespace from entries' do
      e = env('HTTP_X_FORWARDED_FOR' => '  1.2.3.4  ,   5.6.7.8  ')
      expect(described_class.extract_x_forwarded_for(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'ignores empty entries' do
      e = env('HTTP_X_FORWARDED_FOR' => '1.2.3.4, , 5.6.7.8')
      expect(described_class.extract_x_forwarded_for(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'returns nil when header absent' do
      expect(described_class.extract_x_forwarded_for(env)).to be_nil
    end

    it 'returns nil when header empty' do
      e = env('HTTP_X_FORWARDED_FOR' => '')
      expect(described_class.extract_x_forwarded_for(e)).to be_nil
    end
  end

  describe '.extract_rfc7239_forwarded' do
    it 'extracts IPs from for= params' do
      e = env('HTTP_FORWARDED' => 'for=1.2.3.4; host=example.com, for=5.6.7.8')
      expect(described_class.extract_rfc7239_forwarded(e)).to eq(%w[1.2.3.4 5.6.7.8])
    end

    it 'handles quoted values' do
      e = env('HTTP_FORWARDED' => 'for="1.2.3.4"')
      expect(described_class.extract_rfc7239_forwarded(e)).to eq(%w[1.2.3.4])
    end

    it 'handles bracketed IPv6' do
      e = env('HTTP_FORWARDED' => 'for="[2001:db8::1]"')
      expect(described_class.extract_rfc7239_forwarded(e)).to eq(%w[2001:db8::1])
    end

    it 'returns nil when header absent' do
      expect(described_class.extract_rfc7239_forwarded(env)).to be_nil
    end

    it 'returns nil when header empty' do
      e = env('HTTP_FORWARDED' => '')
      expect(described_class.extract_rfc7239_forwarded(e)).to be_nil
    end
  end
end
