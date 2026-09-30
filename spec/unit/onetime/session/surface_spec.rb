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

    it 'returns nil for :invalid without a display domain' do
      expect(described_class.for_env(env_for(strategy: :invalid))).to be_nil
    end

    it 'returns nil when the strategy is missing entirely' do
      expect(described_class.for_env({})).to be_nil
    end

    it 'returns nil when there is no Rack env' do
      expect(described_class.for_env(nil)).to be_nil
    end

    it 'freezes returned descriptors so callers cannot mutate the marker' do
      env  = env_for(strategy: :custom, custom_domain_id: 'x')
      expect(described_class.for_env(env)).to be_frozen
    end
  end

  # DomainStrategy answers :invalid both for a host we do not serve and for
  # any host whose custom-domain lookup RAISED. SessionSurface classifies an
  # :invalid request again with Chooserator.classify!, the middleware's own
  # classifier minus its rescue. These run the real classifier against a
  # real canonical set; only the datastore read is stubbed.
  describe 'an :invalid request' do
    let(:parser) { Onetime::Middleware::DomainStrategy::Parser }
    let(:http_logger) { instance_double(SemanticLogger::Logger, error: nil) }

    before do
      allow(Onetime::Middleware::DomainStrategy).to receive_messages(
        canonical_domains_parsed: [parser.parse('example.com')],
        anchor_domains_parsed: [parser.parse('example.com')],
      )
      allow(Onetime).to receive(:http_logger).and_return(http_logger)
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
    end

    def invalid_env(host)
      env_for(strategy: :invalid, display_domain: host)
    end

    context 'when the lookup answers this time (a blip)' do
      it 'gives a registered custom domain its custom descriptor' do
        domain = instance_double(Onetime::CustomDomain, identifier: 'domain-abc')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('secrets.acme.com').and_return(domain)

        expect(described_class.for_env(invalid_env('secrets.acme.com')))
          .to eq({ 'kind' => 'custom', 'id' => 'domain-abc' })
      end

      # The same answer as a healthy request: DomainStrategy classifies a
      # registered host :custom whether or not it is verified.
      it 'does not require the custom domain to be verified' do
        domain = instance_double(Onetime::CustomDomain, identifier: 'domain-pending', verified: false)
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('pending.acme.com').and_return(domain)

        expect(described_class.for_env(invalid_env('pending.acme.com')))
          .to eq({ 'kind' => 'custom', 'id' => 'domain-pending' })
      end

      it 'gives a platform subdomain its subdomain descriptor' do
        expect(described_class.for_env(invalid_env('eu.example.com')))
          .to eq({ 'kind' => 'subdomain', 'host' => 'eu.example.com' })
      end

      it 'answers nil for a host we do not serve' do
        expect(described_class.for_env(invalid_env('elsewhere.org'))).to be_nil
      end

      it 'matches a session recorded on the same custom domain' do
        domain = instance_double(Onetime::CustomDomain, identifier: 'domain-abc')
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('secrets.acme.com').and_return(domain)
        session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }

        expect(described_class.match_status(session, invalid_env('secrets.acme.com'))).to eq(:match)
      end
    end

    context 'when the lookup fails again (an outage)' do
      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(Redis::BaseError, 'datastore unavailable')
      end

      it 'answers nil to descriptor consumers' do
        expect(described_class.for_env(invalid_env('secrets.acme.com'))).to be_nil
      end

      it 'reports :unavailable, not :mismatch, for a session with a marker' do
        session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }

        expect(described_class.match_status(session, invalid_env('secrets.acme.com'))).to eq(:unavailable)
        expect(described_class.matches_request?(session, invalid_env('secrets.acme.com'))).to be false
      end

      it 'reports :unavailable for a subdomain session too' do
        session = { described_class::KEY => { 'kind' => 'subdomain', 'host' => 'eu.example.com' } }

        expect(described_class.match_status(session, invalid_env('eu.example.com'))).to eq(:unavailable)
      end

      it 'still reports :mismatch for a session with no marker' do
        expect(described_class.match_status({}, invalid_env('secrets.acme.com'))).to eq(:mismatch)
      end

      it 'logs the failure with the host' do
        described_class.for_env(invalid_env('secrets.acme.com'))

        expect(http_logger).to have_received(:error).with(
          '[SessionSurface] Could not re-classify an :invalid request',
          hash_including(exception: kind_of(Redis::BaseError), request_domain: 'secrets.acme.com'),
        )
      end

      it 'stores nil when a login records the surface' do
        session = {}
        described_class.record(session, invalid_env('secrets.acme.com'))

        expect(session).to have_key(described_class::KEY)
        expect(session[described_class::KEY]).to be_nil
      end
    end

    it 'reads the datastore once per request, however many consumers ask' do
      env     = invalid_env('secrets.acme.com')
      session = { described_class::KEY => { 'kind' => 'canonical' } }

      described_class.for_env(env)
      described_class.match_status(session, env)
      described_class.for_env(env)

      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    it 'remembers an outage for the rest of the request' do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(Redis::BaseError, 'datastore unavailable')
      env     = invalid_env('secrets.acme.com')
      session = { described_class::KEY => { 'kind' => 'custom', 'id' => 'domain-abc' } }

      expect(described_class.match_status(session, env)).to eq(:unavailable)
      expect(described_class.match_status(session, env)).to eq(:unavailable)
      expect(Onetime::CustomDomain).to have_received(:from_display_domain).once
    end

    # DomainStrategy substitutes the canonical host when the Host header is
    # not a valid hostname. The canonical host classifies before any read,
    # so an :invalid request showing it was never on the canonical host.
    it 'does not re-classify the canonical host DomainStrategy substituted' do
      expect(described_class.for_env(invalid_env('example.com'))).to be_nil
      expect(Onetime::CustomDomain).not_to have_received(:from_display_domain)
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

    it 'refuses when there is no Rack env' do
      session = { described_class::KEY => { 'kind' => 'canonical' } }
      expect(described_class.matches_request?(session, nil)).to be false
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
