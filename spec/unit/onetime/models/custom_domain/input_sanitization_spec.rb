# spec/unit/onetime/models/custom_domain/input_sanitization_spec.rb
#
# frozen_string_literal: true

# TDD red-phase tests for two security findings in the domain input
# validation pipeline. These test desired behavior that is NOT YET
# implemented -- most tests are expected to FAIL until the fixes land.
#
# Finding 1: Null bytes and control characters pass PublicSuffix.valid?
#            and flow through unchecked.
# Finding 2: Trailing dots -- PublicSuffix already normalizes these, so
#            those tests serve as regression guards (expected GREEN).

require 'spec_helper'

RSpec.describe Onetime::CustomDomain, 'input sanitization' do
  # ------------------------------------------------------------------ #
  # Finding 1 — Null bytes and control characters
  # ------------------------------------------------------------------ #
  #
  # PublicSuffix.valid?("example\x00.com", default_rule: nil) => true
  # These are invalid per RFC 952/1123. CustomDomain.valid? must reject
  # them before they reach storage or DNS record instructions.
  # ------------------------------------------------------------------ #

  describe '.valid?' do
    context 'with null bytes' do
      it 'rejects a domain containing a null byte' do
        expect(described_class.valid?("example\x00.com")).to be false
      end

      it 'rejects a null byte in the subdomain' do
        expect(described_class.valid?("sub\x00domain.example.com")).to be false
      end

      it 'rejects a null byte in the TLD' do
        expect(described_class.valid?("example.co\x00m")).to be false
      end
    end

    context 'with control characters (0x01..0x1F, 0x7F)' do
      it 'rejects SOH (0x01)' do
        expect(described_class.valid?("example\x01.com")).to be false
      end

      it 'rejects TAB (0x09)' do
        expect(described_class.valid?("example\t.com")).to be false
      end

      it 'rejects LF (0x0A)' do
        expect(described_class.valid?("example\n.com")).to be false
      end

      it 'rejects CR (0x0D)' do
        expect(described_class.valid?("example\r.com")).to be false
      end

      it 'rejects US (0x1F)' do
        expect(described_class.valid?("example\x1F.com")).to be false
      end

      it 'rejects DEL (0x7F)' do
        expect(described_class.valid?("example\x7F.com")).to be false
      end
    end

    context 'with legitimate domains (sanity checks)' do
      it 'accepts a normal domain' do
        expect(described_class.valid?('example.com')).to be true
      end

      it 'accepts a subdomain' do
        expect(described_class.valid?('sub.example.com')).to be true
      end

      it 'accepts a hyphenated domain' do
        expect(described_class.valid?('my-site.example.com')).to be true
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Finding 2 — Trailing dots
  #
  # PublicSuffix.parse normalizes trailing dots, so display_domain and
  # base_domain already return clean output. These are regression guards
  # (expected to pass now).
  # ------------------------------------------------------------------ #

  describe '.display_domain' do
    context 'with trailing dot (regression guard)' do
      it 'returns the domain without a trailing dot' do
        expect(described_class.display_domain('example.com.')).to eq('example.com')
      end

      it 'returns the subdomain without a trailing dot' do
        expect(described_class.display_domain('sub.example.com.')).to eq('sub.example.com')
      end
    end

    context 'with null byte (security finding)' do
      it 'rejects a domain containing a null byte' do
        expect {
          described_class.display_domain("example\x00.com")
        }.to raise_error(Onetime::Problem)
      end
    end
  end

  describe '.base_domain' do
    context 'with trailing dot (regression guard)' do
      it 'returns the base domain without a trailing dot' do
        expect(described_class.base_domain('example.com.')).to eq('example.com')
      end

      it 'normalizes a subdomain with trailing dot to the base domain' do
        expect(described_class.base_domain('sub.example.com.')).to eq('example.com')
      end
    end

    context 'with null byte (security finding)' do
      it 'returns nil for a domain containing a null byte' do
        expect(described_class.base_domain("example\x00.com")).to be_nil
      end
    end
  end

  # ------------------------------------------------------------------ #
  # overlaps_canonical_domain? — must catch trailing-dot variants AND
  # null-byte injection attempts that try to bypass the canonical check.
  # ------------------------------------------------------------------ #

  describe '.overlaps_canonical_domain?' do
    before do
      allow(OT).to receive(:conf).and_return({
        'site' => { 'host' => 'example.com' }
      })
    end

    context 'with trailing dot variants of the canonical domain (regression guard)' do
      it 'detects exact canonical domain with trailing dot' do
        expect(described_class.overlaps_canonical_domain?('example.com.')).to be true
      end

      it 'detects a subdomain of the canonical domain with trailing dot' do
        expect(described_class.overlaps_canonical_domain?('sub.example.com.')).to be true
      end
    end

    context 'with null-byte injection bypassing canonical check (security finding)' do
      # The attack: "example\x00.com" has base_domain "example\x00.com"
      # which != "example.com", so overlaps_canonical_domain? currently
      # returns false — the attacker registers the canonical domain.
      it 'detects null-byte variant of the canonical domain' do
        expect(described_class.overlaps_canonical_domain?("example\x00.com")).to be true
      end

      it 'detects null-byte variant in subdomain of canonical domain' do
        expect(described_class.overlaps_canonical_domain?("sub.example\x00.com")).to be true
      end
    end

    context 'with unrelated domains (sanity checks)' do
      it 'returns false for a completely different domain' do
        expect(described_class.overlaps_canonical_domain?('other-site.org')).to be false
      end
    end
  end
end
