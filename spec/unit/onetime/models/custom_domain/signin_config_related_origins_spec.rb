# spec/unit/onetime/models/custom_domain/signin_config_related_origins_spec.rb
#
# frozen_string_literal: true

# Unit tests for the WebAuthn Related Origins field on
# {Onetime::CustomDomain::SigninConfig} (#4414). The field is stored as
# a JSON array of absolute origin URLs; read tolerates historical
# shapes, write validates and normalizes, and the surface-descriptor
# resolver hands the ReauthPolicy exactly the shape it expects.

require 'spec_helper'

RSpec.describe Onetime::CustomDomain::SigninConfig do
  let(:config) { described_class.new(domain_id: 'tenant-a') }

  describe '#related_origins (read)' do
    it 'returns an empty array when unset' do
      expect(config.related_origins).to eq([])
    end

    it 'returns the decoded array when set to a valid JSON list' do
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it 'returns [] on a JSON parse error (tolerant read)' do
      config.related_origins_json = 'not-json'
      expect(config.related_origins).to eq([])
    end

    it 'returns [] on a valid JSON scalar that is not an array' do
      config.related_origins_json = JSON.generate('https://vault.acme.com')
      expect(config.related_origins).to eq([])
    end
  end

  describe '#related_origins= (write)' do
    # The setter resolves each host to check ownership (#4421). These
    # examples are about shape, so no host is a served custom domain.
    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
    end

    it 'stores a normalized origin (lowercase scheme+host)' do
      config.related_origins = ['HTTPS://Vault.Acme.COM']
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it 'preserves a non-default port in the authority' do
      config.related_origins = ['https://vault.acme.com:8443']
      expect(config.related_origins).to eq(['https://vault.acme.com:8443'])
    end

    it 'drops a default port from the authority (443 for https, 80 for http)' do
      config.related_origins = ['https://vault.acme.com:443', 'http://plain.example:80']
      expect(config.related_origins).to eq(%w[https://vault.acme.com http://plain.example])
    end

    it 'tolerates a trailing "/" but does not write it back' do
      config.related_origins = ['https://vault.acme.com/']
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it 'deduplicates after normalization' do
      config.related_origins = ['https://vault.acme.com', 'HTTPS://VAULT.ACME.COM', 'https://vault.acme.com:443']
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it 'drops blank entries silently' do
      config.related_origins = ['https://vault.acme.com', '', '   ']
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it 'clears the underlying field when given an empty array' do
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])
      config.related_origins      = []
      expect(config.related_origins_json).to be_nil
      expect(config.related_origins).to eq([])
    end

    it 'raises Onetime::Problem on an entry with a non-http scheme' do
      expect { config.related_origins = ['ftp://vault.acme.com'] }.to raise_error(Onetime::Problem, /Invalid origin/)
    end

    it 'raises Onetime::Problem on an entry with a path component' do
      expect { config.related_origins = ['https://vault.acme.com/webauthn'] }.to raise_error(Onetime::Problem)
    end

    it 'raises Onetime::Problem on an entry with a query component' do
      expect { config.related_origins = ['https://vault.acme.com?x=1'] }.to raise_error(Onetime::Problem)
    end

    it 'raises Onetime::Problem on an entry with userinfo' do
      expect { config.related_origins = ['https://user:pass@vault.acme.com'] }.to raise_error(Onetime::Problem)
    end

    it 'raises Onetime::Problem on a bare hostname (missing scheme)' do
      expect { config.related_origins = ['vault.acme.com'] }.to raise_error(Onetime::Problem)
    end

    it 'raises Onetime::Problem on an entry that is not a valid URI at all' do
      expect { config.related_origins = ['http://['] }.to raise_error(Onetime::Problem)
    end
  end

  describe '#related_origins= ownership (write, #4421)' do
    let(:own_domain) { instance_double(Onetime::CustomDomain, identifier: 'tenant-a', org_id: 'org-a') }
    let(:same_org)   { instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id', org_id: 'org-a') }
    let(:rival)      { instance_double(Onetime::CustomDomain, identifier: 'rival-domain-id', org_id: 'org-b') }

    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).with('example.com').and_return(true)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a').and_return(own_domain)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('tenant.example').and_return(own_domain)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com').and_return(same_org)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.rival.example').and_return(rival)
    end

    it 'accepts a custom domain owned by the same organization' do
      config.related_origins = ['https://vault.acme.com']
      expect(config.related_origins).to eq(['https://vault.acme.com'])
    end

    it "accepts the config's own domain without an organization lookup" do
      config.related_origins = ['https://tenant.example']

      expect(config.related_origins).to eq(['https://tenant.example'])
      expect(Onetime::CustomDomain).not_to have_received(:find_by_identifier)
    end

    it 'accepts the canonical host without consulting custom-domain ownership' do
      config.related_origins = ['https://example.com']

      expect(config.related_origins).to eq(['https://example.com'])
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
    end

    it 'accepts a host this install does not serve (it resolves to no surface on read)' do
      config.related_origins = ['https://elsewhere.example']
      expect(config.related_origins).to eq(['https://elsewhere.example'])
    end

    it 'refuses a custom domain owned by another organization and names it' do
      expect { config.related_origins = ['https://vault.acme.com', 'https://vault.rival.example'] }
        .to raise_error(Onetime::Problem, %r{another organization: https://vault\.rival\.example\z})
    end

    it 'stores nothing from a refused write, the acceptable entries included' do
      config.related_origins = ['https://example.com']

      expect { config.related_origins = ['https://vault.acme.com', 'https://vault.rival.example'] }
        .to raise_error(Onetime::Problem)
      expect(config.related_origins).to eq(['https://example.com'])
    end

    it 'fails closed when the own domain cannot be resolved' do
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a').and_return(nil)

      expect { config.related_origins = ['https://vault.acme.com'] }
        .to raise_error(Onetime::Problem, /another organization/)
    end

    it 'fails closed when both sides have a blank org_id' do
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'tenant-a', org_id: nil))
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id', org_id: ''))

      expect { config.related_origins = ['https://vault.acme.com'] }.to raise_error(Onetime::Problem)
    end

    it 'does not store a write whose ownership lookup failed' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_raise(Redis::CannotConnectError)

      expect { config.related_origins = ['https://vault.acme.com'] }.to raise_error(Redis::CannotConnectError)
      expect(config.related_origins).to eq([])
    end
  end

  describe '.create! with related_origins (#4421)' do
    let(:own_domain) { instance_double(Onetime::CustomDomain, identifier: 'tenant-a', org_id: 'org-a') }
    let(:built)      { described_class.new(domain_id: 'tenant-a') }

    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a').and_return(own_domain)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id', org_id: 'org-a'))
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.rival.example')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'rival-domain-id', org_id: 'org-b'))
      allow(described_class).to receive(:exists_for_domain?).with('tenant-a').and_return(false)
      allow(described_class).to receive(:new).with(domain_id: 'tenant-a').and_return(built)
      allow(built).to receive(:save).and_return(true)
    end

    it 'stores the origins on a first write instead of dropping them' do
      created = described_class.create!(domain_id: 'tenant-a', related_origins: ['HTTPS://Vault.Acme.COM'])

      expect(created.related_origins).to eq(['https://vault.acme.com'])
      expect(built).to have_received(:save)
    end

    it 'refuses a cross-organization origin and saves nothing' do
      expect { described_class.create!(domain_id: 'tenant-a', related_origins: ['https://vault.rival.example']) }
        .to raise_error(Onetime::Problem, /another organization/)
      expect(built).not_to have_received(:save)
    end

    it 'leaves the field unset when the attribute is not given' do
      expect(described_class.create!(domain_id: 'tenant-a').related_origins_json).to be_nil
    end
  end

  describe '#related_origin_members' do
    # Stored rows are seeded through related_origins_json: the setter
    # refuses a cross-organization entry (#4421), and the read side exists
    # for exactly the rows that never went through it.
    #
    # tenant-a (this config's own domain) and vault.acme.com are both owned
    # by org-a; vault.rival.example belongs to org-b (#4421).
    let(:own_domain) { instance_double(Onetime::CustomDomain, identifier: 'tenant-a', org_id: 'org-a') }

    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).with('example.com').and_return(true)
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a').and_return(own_domain)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id', org_id: 'org-a'))
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.rival.example')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'rival-domain-id', org_id: 'org-b'))
      allow(OT).to receive(:lw)
    end

    it 'resolves a canonical-host origin to the canonical surface descriptor' do
      config.related_origins_json = JSON.generate(['https://example.com'])
      expect(config.related_origin_members).to eq(
        [{ 'origin' => 'https://example.com', 'surface' => Onetime::SessionSurface::CANONICAL }],
      )
    end

    it 'accepts a canonical-host origin without consulting organization ownership' do
      config.related_origins_json = JSON.generate(['https://example.com'])
      config.related_origin_members

      expect(Onetime::CustomDomain).not_to have_received(:find_by_identifier)
      expect(OT).not_to have_received(:lw)
    end

    it 'resolves a same-organization tenant-host origin without discarding the exact origin' do
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])
      expect(config.related_origin_members).to eq(
        [
          {
            'origin' => 'https://vault.acme.com',
            'surface' => { 'kind' => 'custom', 'id' => 'vault-domain-id' },
          },
        ],
      )
      expect(OT).not_to have_received(:lw)
    end

    it 'drops a tenant-host origin owned by another organization and logs the refusal (#4421)' do
      config.related_origins_json = JSON.generate(['https://vault.acme.com', 'https://vault.rival.example'])

      members = config.related_origin_members

      expect(members.map { |member| member['origin'] }).to eq(['https://vault.acme.com'])
      expect(OT).to have_received(:lw).once.with(
        /cross-organization related origin/,
        hash_including(
          domain_id: 'tenant-a',
          origin: 'https://vault.rival.example',
          related_domain_id: 'rival-domain-id',
        ),
      )
    end

    it 'drops a cross-organization origin even when the surface is served on the request (current_domain given)' do
      current_domain = instance_double(
        Onetime::CustomDomain,
        display_domain: 'tenant.example',
        identifier: 'tenant-a',
        org_id: 'org-a',
      )

      config.related_origins_json = JSON.generate(['https://vault.rival.example'])

      expect(config.related_origin_members(current_domain: current_domain)).to eq([])
      expect(Onetime::CustomDomain).not_to have_received(:find_by_identifier)
    end

    it 'fails closed when the config has no resolvable own domain to compare against' do
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a').and_return(nil)
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])

      expect(config.related_origin_members).to eq([])
      expect(OT).to have_received(:lw).once
    end

    it 'fails closed when the own domain has a blank org_id' do
      allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('tenant-a')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'tenant-a', org_id: nil))
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id', org_id: nil))
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])

      expect(config.related_origin_members).to eq([])
    end

    it 'resolves a platform subdomain without collapsing it to canonical or consulting ownership' do
      classification = Onetime::Middleware::DomainStrategy::Chooserator::Classification.new(
        strategy: :subdomain,
        custom_domain: nil,
      )
      allow(Onetime::Middleware::DomainStrategy::Chooserator).to receive(:classify)
        .with('eu.example.com', anything, anchor_domains: anything)
        .and_return(classification)
      config.related_origins_json = JSON.generate(['https://eu.example.com'])

      expect(config.related_origin_members).to eq(
        [
          {
            'origin' => 'https://eu.example.com',
            'surface' => { 'kind' => 'subdomain', 'host' => 'eu.example.com' },
          },
        ],
      )
      expect(Onetime::CustomDomain).not_to have_received(:find_by_identifier)
      expect(OT).not_to have_received(:lw)
    end

    it 'reuses the current custom-domain record instead of loading it again' do
      current_domain = instance_double(
        Onetime::CustomDomain,
        display_domain: 'vault.acme.com',
        identifier: 'vault-domain-id',
      )
      expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
      config.related_origins_json = JSON.generate(['https://vault.acme.com:8443'])

      expect(config.related_origin_members(current_domain: current_domain)).to eq(
        [
          {
            'origin' => 'https://vault.acme.com:8443',
            'surface' => { 'kind' => 'custom', 'id' => 'vault-domain-id' },
          },
        ],
      )
    end

    it 'silently drops an origin whose host we do not serve' do
      config.related_origins_json = JSON.generate(['https://unknown.example'])
      expect(config.related_origin_members).to eq([])
    end

    it 'returns a frozen array so callers cannot mutate the resolved set' do
      config.related_origins_json = JSON.generate(['https://example.com'])
      expect(config.related_origin_members).to be_frozen
    end

    it 'keeps scheme and non-default port distinct for the same surface' do
      config.related_origins_json = JSON.generate(['https://vault.acme.com', 'https://vault.acme.com:8443'])

      expect(config.related_origin_members.map { |member| member['origin'] }).to eq(
        ['https://vault.acme.com', 'https://vault.acme.com:8443'],
      )
    end

    it 'fails closed to [] when the CustomDomain lookup raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(StandardError, 'boom')
      config.related_origins_json = JSON.generate(['https://vault.acme.com'])
      expect(config.related_origin_members).to eq([])
    end
  end

  describe 'FIELD_SPECS' do
    it 'declares related_origins as a colonel-writable string_array' do
      expect(described_class::FIELD_SPECS['related_origins']).to eq(type: :string_array)
    end
  end
end
