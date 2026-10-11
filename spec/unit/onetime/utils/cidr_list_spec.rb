# spec/unit/onetime/utils/cidr_list_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Onetime::Utils::CidrList — the one normalizer and the one verdict shared by
# the per-domain homepage network rules' write path (what a list may hold)
# and read path (what a stored list means). Pure: no I/O.
#
# The verdict is judged exclusively through the env['otto.ip_match'] closure
# IPPrivacyMiddleware installs over the resolved PRE-MASK client IP. The
# stand-in below mirrors that contract: called with Array<IPAddr>, answers
# true/false for ONE client, false when no client IP resolved.
RSpec.describe Onetime::Utils::CidrList do
  # A verdict closure for one client IP (nil = no resolvable client).
  def matcher_for(ip)
    return ->(_ranges) { false } if ip.nil?

    addr = IPAddr.new(ip)
    ->(ranges) { ranges.any? { |range| range.family == addr.family && range.include?(addr) } }
  end

  describe '.canonical' do
    it 'renders a bare IPv4 address as a /32' do
      expect(described_class.canonical('10.1.2.3')).to eq('10.1.2.3/32')
    end

    it 'renders a bare IPv6 address as a /128' do
      expect(described_class.canonical('2001:db8::1')).to eq('2001:db8::1/128')
    end

    it 'drops host bits below the prefix and trims whitespace' do
      expect(described_class.canonical(' 10.1.2.3/8 ')).to eq('10.0.0.0/8')
    end

    it 'lowercases IPv6 hex' do
      expect(described_class.canonical('2001:DB8::/32')).to eq('2001:db8::/32')
    end

    it 'refuses a blank entry' do
      expect { described_class.canonical('  ') }
        .to raise_error(described_class::InvalidEntry) { |ex| expect(ex.entry).to eq('') }
    end

    it 'refuses hostnames, ports, bad prefixes and zone ids, naming the entry' do
      %w[example.com 10.0.0.1:8080 10.0.0.0/33 fe80::1%eth0 1.2.3 10.0.0.256].each do |bad|
        expect { described_class.canonical(bad) }
          .to raise_error(described_class::InvalidEntry) { |ex| expect(ex.entry).to eq(bad) }
      end
    end
  end

  describe '.normalize' do
    it 'canonicalizes, de-duplicates after normalization and preserves order' do
      expect(described_class.normalize(['10.0.0.0/8', '10.1.1.1/8', '192.168.0.0/16', '10.0.0.0/8']))
        .to eq(['10.0.0.0/8', '192.168.0.0/16'])
    end

    it 'reads nil as an empty list' do
      expect(described_class.normalize(nil)).to eq([])
    end

    it 'caps the list at MAX_ENTRIES distinct ranges' do
      ok  = (1..described_class::MAX_ENTRIES).map { |i| "10.0.#{i % 256}.0/24" }.uniq
      too = ok + ['192.168.0.0/16']
      expect(described_class.normalize(ok).length).to eq(ok.length)
      expect { described_class.normalize(too) }
        .to raise_error(described_class::TooManyEntries) do |ex|
          expect(ex.count).to eq(too.length)
          expect(ex.max).to eq(described_class::MAX_ENTRIES)
        end
    end

    it 'counts duplicates once against the cap' do
      dupes = Array.new(described_class::MAX_ENTRIES + 5, '10.0.0.0/8')
      expect(described_class.normalize(dupes)).to eq(['10.0.0.0/8'])
    end
  end

  describe '.parse' do
    it 'returns IPAddr ranges' do
      ranges = described_class.parse(['10.0.0.0/8', '2001:db8::/32'])
      expect(ranges.map(&:to_s)).to eq(['10.0.0.0', '2001:db8::'])
      expect(ranges.map(&:prefix)).to eq([8, 32])
    end

    it 'raises on an unparseable stored entry instead of skipping it' do
      expect { described_class.parse(['10.0.0.0/8', 'junk']) }.to raise_error(IPAddr::Error)
    end
  end

  describe '.permitted?' do
    context 'with no rules' do
      it 'permits without consulting a matcher at all' do
        expect(described_class.permitted?(nil)).to be(true)
        expect(described_class.permitted?('not callable', allowed: [], denied: [])).to be(true)
      end
    end

    context 'with rules but no usable matcher' do
      it 'fails closed on nil' do
        expect(described_class.permitted?(nil, allowed: ['10.0.0.0/8'])).to be(false)
      end

      it 'fails closed on a non-callable value' do
        expect(described_class.permitted?('nope', denied: ['10.0.0.0/8'])).to be(false)
      end
    end

    context 'with an allow list' do
      it 'permits a client inside a range' do
        expect(described_class.permitted?(matcher_for('10.1.2.3'), allowed: ['10.0.0.0/8'])).to be(true)
      end

      it 'refuses a client outside every range' do
        expect(described_class.permitted?(matcher_for('192.168.1.1'), allowed: ['10.0.0.0/8'])).to be(false)
      end

      it 'judges single-address entries at full precision' do
        expect(described_class.permitted?(matcher_for('203.0.113.7'), allowed: ['203.0.113.7/32'])).to be(true)
        expect(described_class.permitted?(matcher_for('203.0.113.8'), allowed: ['203.0.113.7/32'])).to be(false)
      end

      it 'refuses an IPv6 client when only IPv4 ranges are allowed' do
        expect(described_class.permitted?(matcher_for('2001:db8::5'), allowed: ['10.0.0.0/8'])).to be(false)
      end

      it 'accepts pre-parsed IPAddr entries' do
        expect(described_class.permitted?(matcher_for('10.1.2.3'), allowed: [IPAddr.new('10.0.0.0/8')])).to be(true)
      end
    end

    context 'with a deny list' do
      it 'refuses a client inside a denied range' do
        expect(described_class.permitted?(matcher_for('10.1.2.3'), denied: ['10.0.0.0/8'])).to be(false)
      end

      it 'permits a client outside every denied range when nothing is allow-listed' do
        expect(described_class.permitted?(matcher_for('192.168.1.1'), denied: ['10.0.0.0/8'])).to be(true)
      end

      it 'does not deny an IPv6 client on an IPv4-only deny list' do
        expect(described_class.permitted?(matcher_for('2001:db8::5'), denied: ['10.0.0.0/8'])).to be(true)
      end
    end

    context 'with both lists' do
      it 'lets a deny match win over an allow match' do
        expect(described_class.permitted?(matcher_for('10.1.2.3'), allowed: ['10.0.0.0/8'], denied: ['10.1.0.0/16']))
          .to be(false)
      end

      it 'permits a client in the allow list and outside the deny list' do
        expect(described_class.permitted?(matcher_for('10.2.2.3'), allowed: ['10.0.0.0/8'], denied: ['10.1.0.0/16']))
          .to be(true)
      end
    end

    context 'when the request has no resolvable client IP' do
      # The closure answers false for every range, which is indistinguishable
      # from "outside" — except against the UNIVERSAL probe.
      it 'fails closed even for a deny-only policy' do
        expect(described_class.permitted?(matcher_for(nil), denied: ['10.0.0.0/8'])).to be(false)
      end

      it 'fails closed for an allow policy' do
        expect(described_class.permitted?(matcher_for(nil), allowed: ['10.0.0.0/8'])).to be(false)
      end
    end

    it 'raises on an unparseable configured entry rather than skipping it' do
      expect { described_class.permitted?(matcher_for('10.1.2.3'), allowed: ['junk']) }
        .to raise_error(IPAddr::Error)
    end
  end
end
