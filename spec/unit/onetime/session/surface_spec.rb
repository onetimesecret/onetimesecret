# spec/unit/onetime/session/surface_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::SessionSurface — the pure classifier and comparator
# behind surface-bound sessions (#4409). Terms (surface, marker) are defined in
# the module doc. The strategy symbols (:canonical, :subdomain, :custom,
# :invalid) mirror what DomainStrategy stashes in env.

require 'spec_helper'
require 'onetime/session/surface'
require 'onetime/session/codec'

RSpec.describe Onetime::SessionSurface do
  def env_for(strategy:, display_domain: nil, custom_domain_id: nil)
    {
      'onetime.domain_strategy'  => strategy,
      'onetime.display_domain'   => display_domain,
      'onetime.custom_domain_id' => custom_domain_id,
    }
  end

  describe '.for_env' do
    it 'returns the canonical descriptor for :canonical' do
      expect(described_class.for_env(env_for(strategy: :canonical)))
        .to eq({ 'kind' => 'canonical' })
    end

    it 'distinguishes :subdomain from :canonical and carries the host' do
      env = env_for(strategy: :subdomain, display_domain: 'eu.example.com')
      expect(described_class.for_env(env))
        .to eq({ 'kind' => 'subdomain', 'host' => 'eu.example.com' })
    end

    it 'returns nil for :subdomain when the display_domain is missing' do
      expect(described_class.for_env(env_for(strategy: :subdomain))).to be_nil
    end

    it 'returns a :custom descriptor keyed on the resolved custom_domain_id' do
      env = env_for(strategy: :custom, display_domain: 'secrets.acme.com', custom_domain_id: 'domain-abc')
      expect(described_class.for_env(env))
        .to eq({ 'kind' => 'custom', 'id' => 'domain-abc' })
    end

    it 'returns nil for :custom when the id could not be resolved (blip)' do
      env = env_for(strategy: :custom, display_domain: 'secrets.acme.com', custom_domain_id: nil)
      expect(described_class.for_env(env)).to be_nil
    end

    it 'returns nil for :invalid' do
      expect(described_class.for_env(env_for(strategy: :invalid))).to be_nil
    end

    it 'returns nil when the strategy is missing entirely' do
      expect(described_class.for_env({})).to be_nil
    end

    it 'freezes returned descriptors so callers cannot mutate the marker' do
      env  = env_for(strategy: :custom, custom_domain_id: 'x')
      expect(described_class.for_env(env)).to be_frozen
    end
  end

  describe '.record' do
    it 'stamps the session under KEY' do
      session = {}
      described_class.record(session, env_for(strategy: :canonical))
      expect(session).to eq('authenticated_surface' => { 'kind' => 'canonical' })
    end

    it 'stores nil when the request has no authoritative surface' do
      session = {}
      described_class.record(session, env_for(strategy: :invalid))
      expect(session).to have_key(described_class::KEY)
      expect(session[described_class::KEY]).to be_nil
    end
  end

  describe '.matches_request?' do
    it 'matches when the stored canonical surface equals the request surface' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      expect(described_class.matches_request?(session, env_for(strategy: :canonical))).to be true
    end

    it 'matches after the session marker is encoded and decoded' do
      env     = env_for(strategy: :custom, display_domain: 'secrets.acme.com', custom_domain_id: 'domain-abc')
      session = {}
      codec   = Onetime::SessionCodec.new('surface-round-trip-test-secret')

      described_class.record(session, env)
      restored = codec.decode(codec.encode(session))

      expect(restored).to eq(
        'authenticated_surface' => { 'kind' => 'custom', 'id' => 'domain-abc' },
      )
      expect(described_class.matches_request?(restored, env)).to be true
    end

    it 'refuses platform session on tenant surface' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      env     = env_for(strategy: :custom, custom_domain_id: 'domain-abc')
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses tenant session on platform surface' do
      session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }
      env     = env_for(strategy: :canonical)
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses tenant A session on tenant B surface' do
      session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'tenant-a' } }
      env     = env_for(strategy: :custom, custom_domain_id: 'tenant-b')
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses canonical session on canonical subdomain (distinct surface classes)' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      env     = env_for(strategy: :subdomain, display_domain: 'eu.example.com')
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses subdomain session on canonical' do
      session = { described_class::KEY => { 'kind' => 'subdomain', 'host' => 'eu.example.com' } }
      env     = env_for(strategy: :canonical)
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses subdomain A session on subdomain B' do
      session = { described_class::KEY => { 'kind' => 'subdomain', 'host' => 'eu.example.com' } }
      env     = env_for(strategy: :subdomain, display_domain: 'us.example.com')
      expect(described_class.matches_request?(session, env)).to be false
    end

    it 'refuses a legacy session with no marker (missing-marker case)' do
      session = {}
      expect(described_class.matches_request?(session, env_for(strategy: :canonical))).to be false
    end

    it 'refuses when the request surface is unresolved (:invalid)' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      expect(described_class.matches_request?(session, env_for(strategy: :invalid))).to be false
    end

    it 'refuses a custom session whose recorded id no longer resolves (stale-domain case)' do
      session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }
      env     = env_for(strategy: :custom, display_domain: 'secrets.acme.com', custom_domain_id: nil)
      expect(described_class.matches_request?(session, env)).to be false
    end
  end

  describe '.clear' do
    it 'removes the marker from the session' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      described_class.clear(session)
      expect(session).not_to have_key(described_class::KEY)
    end
  end
end
