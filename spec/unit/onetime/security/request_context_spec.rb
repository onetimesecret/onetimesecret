# spec/unit/onetime/security/request_context_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/security/request_context'

# Unit coverage for the privacy-safe network-context capture (#3640, ADR-022).
#
# This is the primary safety net for the privacy stance: the stored
# representation must ALWAYS be the masked partial IP, the partial UA, and the
# keyed correlation hash -- and NEVER a raw dotted-quad IP or a full user-agent
# string. The examples below pin masking, keyed hashing (stable + keyed), UA
# reduction, and -- critically -- that no raw value can survive capture.
RSpec.describe Onetime::Security::RequestContext do
  # A deliberately raw, un-masked public IPv4 and a full real-browser UA. In
  # production these are already edge-masked by Otto before reaching the app;
  # feeding the RAW values here proves the helper reduces them regardless.
  let(:raw_ipv4) { '203.0.113.42' }
  let(:raw_ipv6) { '2001:db8:1234:5678:9abc:def0:1234:5678' }
  let(:full_ua) do
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
      '(KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'
  end
  let(:key) { 'a-stable-server-secret' }

  describe '.mask_ip' do
    it 'zeros the last IPv4 octet' do
      expect(described_class.mask_ip('203.0.113.42')).to eq('203.0.113.0')
    end

    it 'masks the trailing IPv6 bits' do
      expect(described_class.mask_ip(raw_ipv6)).to eq('2001:db8:1234::')
    end

    it 'is idempotent on an already-masked address' do
      once  = described_class.mask_ip(raw_ipv4)
      twice = described_class.mask_ip(once)
      expect(twice).to eq(once)
    end

    it 'returns nil for blank or malformed input (never a raw fall-through)' do
      expect(described_class.mask_ip(nil)).to be_nil
      expect(described_class.mask_ip('')).to be_nil
      expect(described_class.mask_ip('   ')).to be_nil
      expect(described_class.mask_ip('not-an-ip')).to be_nil
    end
  end

  describe '.hash_ip' do
    it 'is a 64-char hex HMAC that is stable for the same input + key' do
      h1 = described_class.hash_ip('203.0.113.0', key)
      h2 = described_class.hash_ip('203.0.113.0', key)
      expect(h1).to match(/\A[0-9a-f]{64}\z/)
      expect(h1).to eq(h2)
    end

    it 'differs for a different key (keyed, not a plain digest)' do
      expect(described_class.hash_ip('203.0.113.0', 'key-a'))
        .not_to eq(described_class.hash_ip('203.0.113.0', 'key-b'))
    end

    it 'differs for different inputs' do
      expect(described_class.hash_ip('203.0.113.0', key))
        .not_to eq(described_class.hash_ip('198.51.100.0', key))
    end

    it 'omits the hash when the key is blank rather than using a weak key' do
      expect(described_class.hash_ip('203.0.113.0', nil)).to be_nil
      expect(described_class.hash_ip('203.0.113.0', '')).to be_nil
    end
  end

  describe '.mask_user_agent' do
    it 'strips version numbers so the full UA is never retained verbatim' do
      partial = described_class.mask_user_agent(full_ua)

      expect(partial).not_to eq(full_ua)
      expect(partial).not_to include('119.0.0.0')
      expect(partial).not_to include('10.0')
      # Family/OS info survives -- the point is a partial, not a redaction.
      expect(partial).to include('Windows NT')
      expect(partial).to include('Chrome')
    end

    it 'strips build identifiers' do
      ua = 'Dalvik/2.1.0 (Linux; U; Android 9; SM-G960F Build/PPR1.180610.011)'
      expect(described_class.mask_user_agent(ua)).to include('Build/*')
      expect(described_class.mask_user_agent(ua)).not_to include('PPR1.180610.011')
    end

    it 'truncates to UA_MAX_LENGTH' do
      long = "Agent/#{'x' * 1000}"
      expect(described_class.mask_user_agent(long).length)
        .to eq(described_class::UA_MAX_LENGTH)
    end

    it 'is idempotent on an already-stripped UA' do
      once  = described_class.mask_user_agent(full_ua)
      twice = described_class.mask_user_agent(once)
      expect(twice).to eq(once)
    end

    it 'returns nil for blank input' do
      expect(described_class.mask_user_agent(nil)).to be_nil
      expect(described_class.mask_user_agent('')).to be_nil
    end
  end

  describe '.capture' do
    subject(:attrs) { described_class.capture(ip: raw_ipv4, user_agent: full_ua, key: key) }

    it 'returns exactly the three privacy-safe, string-keyed attributes' do
      expect(attrs.keys).to contain_exactly(
        'net_ip_partial', 'net_ua_partial', 'net_ip_hash'
      )
    end

    it 'stores the masked partial IP, not the raw IP' do
      expect(attrs['net_ip_partial']).to eq('203.0.113.0')
    end

    it 'produces a stable, keyed correlation hash over the PARTIAL IP' do
      # Hash is computed over the /24, so a different host in the same /24
      # correlates to the same token; a different /24 does not.
      same_24  = described_class.capture(ip: '203.0.113.9', user_agent: full_ua, key: key)
      other_24 = described_class.capture(ip: '198.51.100.7', user_agent: full_ua, key: key)

      expect(attrs['net_ip_hash']).to eq(described_class.hash_ip('203.0.113.0', key))
      expect(same_24['net_ip_hash']).to eq(attrs['net_ip_hash'])
      expect(other_24['net_ip_hash']).not_to eq(attrs['net_ip_hash'])
    end

    it 'omits keys whose value could not be derived' do
      expect(described_class.capture(ip: nil, user_agent: nil, key: key)).to eq({})
      ip_only = described_class.capture(ip: raw_ipv4, user_agent: nil, key: key)
      expect(ip_only.keys).to contain_exactly('net_ip_partial', 'net_ip_hash')
    end

    # THE NO-REGRESSION GUARANTEE: no captured value may contain the raw IP or
    # the full UA -- not in a partial, not embedded in the hash, nowhere.
    it 'never emits a raw dotted-quad IP or the full user-agent string' do
      serialized = attrs.to_json

      expect(serialized).not_to include(raw_ipv4)
      expect(serialized).not_to include(full_ua)
      expect(serialized).not_to include('119.0.0.0')
      attrs.each_value { |v| expect(v).not_to include(raw_ipv4) }
    end

    it 'reduces even a raw IPv6 address to its masked prefix' do
      out = described_class.capture(ip: raw_ipv6, user_agent: nil, key: key)
      expect(out['net_ip_partial']).to eq('2001:db8:1234::')
      expect(out.to_json).not_to include(raw_ipv6)
    end

    it 'defaults the hash key to the app global secret' do
      allow(OT).to receive(:global_secret).and_return('global-secret-xyz')
      out = described_class.capture(ip: raw_ipv4, user_agent: nil)
      expect(out['net_ip_hash']).to eq(described_class.hash_ip('203.0.113.0', 'global-secret-xyz'))
    end
  end
end
