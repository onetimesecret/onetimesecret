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

  describe '#related_origin_surfaces' do
    before do
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
      allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).with('example.com').and_return(true)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id'))
    end

    it 'resolves a canonical-host origin to the canonical surface descriptor' do
      config.related_origins = ['https://example.com']
      expect(config.related_origin_surfaces).to eq([Onetime::SessionSurface::CANONICAL])
    end

    it 'resolves a known tenant-host origin to its custom-domain descriptor' do
      config.related_origins = ['https://vault.acme.com']
      expect(config.related_origin_surfaces).to eq([{ 'kind' => 'custom', 'id' => 'vault-domain-id' }])
    end

    it 'silently drops an origin whose host we do not serve' do
      config.related_origins = ['https://unknown.example']
      expect(config.related_origin_surfaces).to eq([])
    end

    it 'returns a frozen array so callers cannot mutate the resolved set' do
      config.related_origins = ['https://example.com']
      expect(config.related_origin_surfaces).to be_frozen
    end

    it 'deduplicates surfaces when multiple origins resolve to the same custom-domain host' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.acme.com')
        .and_return(instance_double(Onetime::CustomDomain, identifier: 'vault-domain-id'))
      # Different origin ports resolve to the same tenant surface descriptor
      # (surface identity is the CustomDomain id, not the origin's port), so
      # the resolved set is deduplicated.
      config.related_origins = ['https://vault.acme.com', 'https://vault.acme.com:8443']
      expect(config.related_origin_surfaces).to eq([{ 'kind' => 'custom', 'id' => 'vault-domain-id' }])
    end

    it 'fails closed to [] when the CustomDomain lookup raises' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(StandardError, 'boom')
      config.related_origins = ['https://vault.acme.com']
      expect(config.related_origin_surfaces).to eq([])
    end
  end

  describe 'FIELD_SPECS' do
    it 'declares related_origins as a colonel-writable string_array' do
      expect(described_class::FIELD_SPECS['related_origins']).to eq(type: :string_array)
    end
  end
end
