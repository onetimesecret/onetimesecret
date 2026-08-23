# spec/unit/onetime/utils/canonical_hosts_spec.rb
#
# frozen_string_literal: true

# Unit tests for the single derivation point of the deployment's canonical
# host set (#3841, extended by #4063).
#
# Three sets come out of this module and they are deliberately NOT
# interchangeable:
#
#   hosts / normalized_hosts        classification + admission; includes the
#                                   operator link pool.
#   anchor_hosts / normalized_...   what ANCHORS generated links
#                                   (CustomDomain.default_domain?); NEVER
#                                   contains a pool member.
#   link_pool                       what the domain-context picker offers.
#
# The ordering contract (primary at element 0) and the nil-vs-[]-vs-populated
# axis of link_domains are the two things most likely to be "tidied" into
# breakage, so they are pinned explicitly here.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/utils/canonical_hosts_spec.rb

require 'spec_helper'
require 'onetime/utils/canonical_hosts'

RSpec.describe Onetime::Utils::CanonicalHosts do
  # Whole-conf replacement (the idiom used by
  # spec/unit/onetime/models/custom_domain/input_sanitization_spec.rb), so the
  # private config_* readers are exercised rather than bypassed by kwargs.
  #
  # link_domains: :unset omits the key entirely, which is what an operator who
  # never wrote LINK_DOMAINS gets. Pass nil to write an explicit null (the
  # shape the ERB template renders); both must behave identically.
  def stub_conf(site_host: nil, default_host: nil, link_domains: :unset)
    domains                 = {}
    domains['default']      = default_host unless default_host.nil?
    domains['link_domains'] = link_domains unless link_domains == :unset

    allow(OT).to receive(:conf).and_return(
      'site' => { 'host' => site_host },
      'features' => { 'domains' => domains },
    )
  end

  # ------------------------------------------------------------------ #
  # .hosts — the full canonical set, ordering contract included
  # ------------------------------------------------------------------ #

  describe '.hosts' do
    context 'with no link pool configured (pre-#4063 behavior)' do
      before { stub_conf(site_host: 'app.example.com', default_host: 'links.example.net') }

      it 'returns the two anchors with the default link domain first' do
        expect(described_class.hosts).to eq(%w[links.example.net app.example.com])
      end

      it 'behaves identically when link_domains is present but null' do
        stub_conf(site_host: 'app.example.com', default_host: 'links.example.net', link_domains: nil)
        expect(described_class.hosts).to eq(%w[links.example.net app.example.com])
      end
    end

    context 'with a link pool configured' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: ['go.acme.com'],
        )
      end

      it 'appends the pool AFTER both anchors' do
        expect(described_class.hosts).to eq(%w[links.example.net app.example.com go.acme.com])
      end

      it 'leaves element 0 as the primary anchor' do
        # DomainStrategy takes @canonical_domains.first as THE canonical
        # domain; a pool entry landing there would rewrite the deployment's
        # identity from a picker setting.
        expect(described_class.hosts.first).to eq('links.example.net')
      end
    end

    context 'with a multi-entry pool' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: ['go.acme.com', 'short.example.com'],
        )
      end

      it 'preserves the configured pool order after the anchors' do
        expect(described_class.hosts)
          .to eq(%w[links.example.net app.example.com go.acme.com short.example.com])
      end
    end

    context 'when the pool repeats an anchor' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: ['app.example.com', 'go.acme.com'],
        )
      end

      it 'de-duplicates without disturbing anchor ordering' do
        expect(described_class.hosts).to eq(%w[links.example.net app.example.com go.acme.com])
      end
    end

    context 'with blank and whitespace-padded entries' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: nil,
          link_domains: ['  go.acme.com  ', '', '   '],
        )
      end

      it 'strips padding and drops blanks' do
        expect(described_class.hosts).to eq(%w[app.example.com go.acme.com])
      end
    end

    context 'with no features.domains.default' do
      before { stub_conf(site_host: 'app.example.com', link_domains: ['go.acme.com']) }

      it 'makes site.host the primary and still appends the pool' do
        expect(described_class.hosts).to eq(%w[app.example.com go.acme.com])
      end
    end

    it 'accepts explicit overrides for all three inputs' do
      stub_conf(site_host: 'ignored.example.com', default_host: 'ignored.example.net')

      expect(
        described_class.hosts(
          default_host: 'links.example.net',
          site_host: 'app.example.com',
          link_hosts: ['go.acme.com'],
        ),
      ).to eq(%w[links.example.net app.example.com go.acme.com])
    end
  end

  # ------------------------------------------------------------------ #
  # .normalized_hosts / .primary / .canonical_host?
  # ------------------------------------------------------------------ #

  describe '.normalized_hosts' do
    before do
      stub_conf(
        site_host: 'App.Example.com:3000',
        default_host: 'links.example.net',
        link_domains: ['GO.acme.com'],
      )
    end

    it 'lowercases and strips ports while keeping the primary first' do
      expect(described_class.normalized_hosts)
        .to eq(%w[links.example.net app.example.com go.acme.com])
    end
  end

  describe '.primary' do
    it 'is the default link domain when one is configured' do
      stub_conf(
        site_host: 'app.example.com',
        default_host: 'links.example.net',
        link_domains: ['go.acme.com'],
      )
      expect(described_class.primary).to eq('links.example.net')
    end

    it 'falls back to site.host when no default is configured' do
      stub_conf(site_host: 'app.example.com', link_domains: ['go.acme.com'])
      expect(described_class.primary).to eq('app.example.com')
    end
  end

  describe '.canonical_host?' do
    before do
      stub_conf(
        site_host: 'app.example.com',
        default_host: 'links.example.net',
        link_domains: ['short.example.com'],
      )
    end

    it 'is true for a pool member (this is what stops it classifying :invalid)' do
      expect(described_class.canonical_host?('short.example.com')).to be true
    end

    it 'is true for either anchor' do
      expect(described_class.canonical_host?('links.example.net')).to be true
      expect(described_class.canonical_host?('app.example.com')).to be true
    end

    it 'normalizes case and port on the way in' do
      expect(described_class.canonical_host?('SHORT.Example.com:443')).to be true
    end

    it 'is false for a subdomain of a pool member (exact membership only)' do
      expect(described_class.canonical_host?('evil.short.example.com')).to be false
    end

    it 'is false for an unrelated host' do
      expect(described_class.canonical_host?('other-site.org')).to be false
    end
  end

  # ------------------------------------------------------------------ #
  # .anchor_hosts — the link-ANCHOR set. A pool member landing here is the
  # single highest-value regression in #4063: CustomDomain.default_domain?
  # reads this set and process_share_domain returns early when it is true,
  # silently discarding every picker selection.
  # ------------------------------------------------------------------ #

  describe '.anchor_hosts' do
    it 'equals the full canonical set when no pool is configured' do
      stub_conf(site_host: 'app.example.com', default_host: 'links.example.net')

      expect(described_class.anchor_hosts).to eq(described_class.hosts)
      expect(described_class.anchor_hosts).to eq(%w[links.example.net app.example.com])
    end

    it 'never contains a pool member' do
      stub_conf(
        site_host: 'app.example.com',
        default_host: 'links.example.net',
        link_domains: ['go.acme.com', 'short.example.com'],
      )

      expect(described_class.anchor_hosts).to eq(%w[links.example.net app.example.com])
      expect(described_class.anchor_hosts).not_to include('go.acme.com')
      expect(described_class.anchor_hosts).not_to include('short.example.com')
    end

    it 'ignores an explicitly forwarded link_hosts kwarg' do
      # Callers forward the same kwargs they pass to hosts/normalized_hosts;
      # the pool must be discarded rather than honoured.
      stub_conf(site_host: 'app.example.com', default_host: 'links.example.net')

      expect(described_class.anchor_hosts(link_hosts: ['go.acme.com']))
        .to eq(%w[links.example.net app.example.com])
    end

    it 'keeps the primary anchor first' do
      stub_conf(site_host: 'app.example.com', default_host: 'links.example.net')
      expect(described_class.anchor_hosts.first).to eq('links.example.net')
    end
  end

  describe '.normalized_anchor_hosts' do
    before do
      stub_conf(
        site_host: 'App.Example.com:3000',
        default_host: 'Links.Example.NET',
        link_domains: ['go.acme.com'],
      )
    end

    it 'lowercases and strips ports, still excluding the pool' do
      expect(described_class.normalized_anchor_hosts)
        .to eq(%w[links.example.net app.example.com])
    end
  end

  # ------------------------------------------------------------------ #
  # .link_pool — the picker pool. nil / [] / populated are three distinct
  # answers and collapsing any pair of them breaks a stated requirement.
  # ------------------------------------------------------------------ #

  describe '.link_pool' do
    context 'when link_domains is unset (nil)' do
      before { stub_conf(site_host: 'app.example.com', default_host: 'links.example.net') }

      it 'offers the primary canonical host, preserving pre-#4063 behavior' do
        expect(described_class.link_pool).to eq(['links.example.net'])
      end

      it 'offers exactly one host, not the whole anchor set' do
        expect(described_class.link_pool.length).to eq(1)
      end

      it 'answers the same for an explicit null as for an absent key' do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: nil,
        )
        expect(described_class.link_pool).to eq(['links.example.net'])
      end

      it 'falls back to site.host when there is no default link domain' do
        stub_conf(site_host: 'app.example.com')
        expect(described_class.link_pool).to eq(['app.example.com'])
      end
    end

    context 'when link_domains names hosts' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: ['go.acme.com', 'short.example.com'],
        )
      end

      it 'returns them verbatim, in configured order' do
        expect(described_class.link_pool).to eq(%w[go.acme.com short.example.com])
      end

      it 'does not add the canonical host back in' do
        # The whole point of the feature: an operator hiding
        # ge-abcd123.eu.otshosted.com must not see it re-offered.
        expect(described_class.link_pool).not_to include('links.example.net')
        expect(described_class.link_pool).not_to include('app.example.com')
      end
    end

    context 'when link_domains is set but empty' do
      before do
        stub_conf(
          site_host: 'app.example.com',
          default_host: 'links.example.net',
          link_domains: [],
        )
      end

      it 'returns [] rather than silently rewriting to the canonical host' do
        # Onetime::Config.validate_link_domains! raises at boot for this
        # input; rewriting it here would hide the operator's typo instead.
        expect(described_class.link_pool).to eq([])
      end
    end

    context 'with untidy entries' do
      it 'strips padding, drops blanks, and de-duplicates' do
        stub_conf(
          site_host: 'app.example.com',
          link_domains: ['  go.acme.com ', '', 'go.acme.com', '   ', 'short.example.com'],
        )

        expect(described_class.link_pool).to eq(%w[go.acme.com short.example.com])
      end

      it 'is [] when every configured entry is blank' do
        stub_conf(site_host: 'app.example.com', link_domains: ['', '  '])
        expect(described_class.link_pool).to eq([])
      end
    end

    it 'accepts an explicit link_hosts override' do
      stub_conf(site_host: 'app.example.com', default_host: 'links.example.net')

      expect(described_class.link_pool(link_hosts: ['go.acme.com'])).to eq(['go.acme.com'])
      expect(described_class.link_pool(link_hosts: nil)).to eq(['links.example.net'])
    end
  end

  # ------------------------------------------------------------------ #
  # AC1 at the derivation layer: an operator who never set LINK_DOMAINS
  # sees no change at all.
  # ------------------------------------------------------------------ #

  describe 'backward compatibility with link_domains unset' do
    before { stub_conf(site_host: 'app.example.com', default_host: 'links.example.net') }

    it 'derives the canonical set from the anchors alone' do
      expect(described_class.hosts).to eq(described_class.anchor_hosts)
      expect(described_class.normalized_hosts).to eq(described_class.normalized_anchor_hosts)
    end

    it 'still answers canonical_host? for both anchors and nothing else' do
      expect(described_class.canonical_host?('links.example.net')).to be true
      expect(described_class.canonical_host?('app.example.com')).to be true
      expect(described_class.canonical_host?('go.acme.com')).to be false
    end
  end

  describe 'with no hosts configured at all' do
    before { allow(OT).to receive(:conf).and_return({}) }

    it 'returns empty sets rather than raising' do
      expect(described_class.hosts).to eq([])
      expect(described_class.anchor_hosts).to eq([])
      expect(described_class.primary).to be_nil
      expect(described_class.canonical_host?('example.com')).to be false
    end

    it 'returns an empty pool because there is no primary to offer' do
      expect(described_class.link_pool).to eq([])
    end
  end
end
