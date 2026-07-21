# spec/unit/onetime/models/custom_domain/input_sanitization_spec.rb
#
# frozen_string_literal: true

# Security regression tests for the domain input validation pipeline.
#
# Finding 1: Null bytes and control characters are rejected before they
#            reach storage or DNS record instructions.
# Finding 2: Trailing dots -- PublicSuffix normalizes these; regression
#            guards.
# Finding 3 (#3841): the canonical-domain overlap guard covers both
#            site.host and features.domains.default, fails closed on
#            unparseable input, and is enforced at the create! write gate.

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

    context 'with unparseable input (fail closed)' do
      it 'treats a bare unknown label as overlap' do
        expect(described_class.overlaps_canonical_domain?('not_a_domain')).to be true
      end
    end

    # The DomainStrategy middleware treats features.domains.default as
    # canonical when set, so the guard must cover it too (#3841).
    context 'when features.domains.default differs from site.host' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => { 'host' => 'example.com' },
          'features' => { 'domains' => { 'default' => 'branded-links.net' } },
        })
      end

      it 'detects the default link domain verbatim' do
        expect(described_class.overlaps_canonical_domain?('branded-links.net')).to be true
      end

      it 'detects a subdomain of the default link domain' do
        expect(described_class.overlaps_canonical_domain?('secrets.branded-links.net')).to be true
      end

      it 'still detects the site host' do
        expect(described_class.overlaps_canonical_domain?('sub.example.com')).to be true
      end

      it 'returns false for an unrelated domain' do
        expect(described_class.overlaps_canonical_domain?('other-site.org')).to be false
      end
    end

    context 'when no canonical hosts are configured' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'returns false' do
        expect(described_class.overlaps_canonical_domain?('example.com')).to be false
      end
    end
  end

  # ------------------------------------------------------------------ #
  # create! backstop — the write gate enforces the canonical invariant
  # itself, so console/CLI callers can't bypass the endpoint guard (#3841).
  # The guard raises before any Redis access.
  # ------------------------------------------------------------------ #

  describe '.create! canonical backstop' do
    before do
      allow(OT).to receive(:conf).and_return({
        'site' => { 'host' => 'example.com' },
      })

      # Spy on the Redis-touching collaborators so we can prove the
      # guard raises before any of them run (mirrors the index spies in
      # update_display_domain_spec).
      index_double = instance_double('Familia::UniqueIndex', hsetnx: 1)
      allow(described_class).to receive(:display_domain_index).and_return(index_double)
      allow(described_class).to receive(:load_by_display_domain)
    end

    it 'rejects the canonical domain verbatim' do
      expect {
        described_class.create!('example.com', 'org-test-001')
      }.to raise_error(Onetime::Problem, /overlaps with the default site domain/)
    end

    it 'rejects a subdomain of the canonical domain' do
      expect {
        described_class.create!('secrets.example.com', 'org-test-001')
      }.to raise_error(Onetime::Problem, /overlaps with the default site domain/)
    end

    it 'raises before any Redis access' do
      expect {
        described_class.create!('example.com', 'org-test-001')
      }.to raise_error(Onetime::Problem)

      expect(described_class).not_to have_received(:load_by_display_domain)
      expect(described_class.display_domain_index).not_to have_received(:hsetnx)
    end
  end
end
