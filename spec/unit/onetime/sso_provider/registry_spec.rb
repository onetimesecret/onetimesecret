# spec/unit/onetime/sso_provider/registry_spec.rb
#
# frozen_string_literal: true

# Shape validation for Onetime::SsoProvider::Registry — the single source of
# truth for SSO provider wiring (serializer gating, CSP origins, and
# boot-time strategy registration all read it).
#
# These specs are the guard rail for ADDING a provider: a new entry that
# is missing a field, reuses a route name, or mixes up its env prefix
# fails here before it can half-register at boot.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit

require 'spec_helper'
require 'climate_control'
require_relative '../../../../lib/onetime/sso_provider/registry'

RSpec.describe Onetime::SsoProvider::Registry do
  let(:definitions) { described_class::DEFINITIONS }

  REQUIRED_FIELDS = [
    :key, :label, :strategy, :gem_require, :issuer_capable, :required_vars, :route_var, :route_default, :display_var, :display_default, :trust_var, :trust_default, :placeholder_options, :strategy_options
  ].freeze

  it 'defines at least the four launch providers' do
    expect(definitions.map { |d| d[:key] }).to include(:oidc, :entra, :google, :github)
  end

  it 'gives every definition the full field set' do
    definitions.each do |defn|
      missing = REQUIRED_FIELDS.reject { |field| defn.key?(field) }
      expect(missing).to be_empty,
        "definition #{defn[:key].inspect} is missing fields: #{missing.inspect}"
    end
  end

  it 'uses unique keys and unique default route names' do
    keys   = definitions.map { |d| d[:key] }
    routes = definitions.map { |d| d[:route_default] }
    expect(keys).to eq(keys.uniq)
    expect(routes).to eq(routes.uniq)
  end

  it 'types every field correctly' do
    definitions.each do |defn|
      expect(defn[:key]).to be_a(Symbol)
      expect(defn[:label]).to be_a(String)
      expect(defn[:strategy]).to be_a(Symbol)
      expect(defn[:gem_require]).to be_a(String)
      expect(defn[:issuer_capable]).to be(true).or be(false)
      expect(defn[:required_vars]).to all(be_a(String))
      expect(defn[:required_vars]).not_to be_empty
      expect(defn[:placeholder_options]).to be_a(Hash)
      expect(defn[:strategy_options]).to respond_to(:call)
      expect(defn[:trust_default]).to be(true).or be(false)
    end
  end

  it 'keeps env var names on a consistent per-provider prefix' do
    definitions.each do |defn|
      # The prefix is derived from the route/display/trust vars, which must
      # all agree (required_vars may differ, e.g. OIDC's ISSUER var).
      prefix = defn[:route_var].delete_suffix('_ROUTE_NAME')
      expect(defn[:display_var]).to eq("#{prefix}_DISPLAY_NAME")
      expect(defn[:trust_var]).to eq("#{prefix}_TRUST_EMAIL_FOR_LINKING")
    end
  end

  it 'gives every definition exactly one CSP origin source' do
    definitions.each do |defn|
      sources = [defn[:idp_origin], defn[:idp_origin_from]].compact
      expect(sources.length).to eq(1),
        "definition #{defn[:key].inspect} must set exactly one of idp_origin/idp_origin_from"
    end
  end

  it 'requires any idp_origin_from var to be in required_vars' do
    # The CSP origin gate and the sso_providers gate share required_vars; an
    # idp_origin_from var outside that list could emit a CSP origin for a
    # provider whose serializer gating never checks the same var.
    definitions.each do |defn|
      next unless defn[:idp_origin_from]

      expect(defn[:required_vars]).to include(defn[:idp_origin_from]),
        "definition #{defn[:key].inspect}: idp_origin_from #{defn[:idp_origin_from].inspect} " \
        'must be one of its required_vars'
    end
  end

  it 'never uses real-looking credentials in placeholder_options' do
    definitions.each do |defn|
      defn[:placeholder_options].each do |opt, value|
        next unless [:client_id, :client_secret, :tenant_id].include?(opt)

        expect(value).to eq('placeholder'),
          "definition #{defn[:key].inspect} placeholder option #{opt} must be 'placeholder'"
      end
    end
  end

  it 'freezes the registry and every definition' do
    expect(definitions).to be_frozen
    expect(definitions).to all(be_frozen)
  end

  describe '.find' do
    it 'returns the definition for a known key' do
      expect(described_class.find(:entra)[:strategy]).to eq(:entra_id)
    end

    it 'returns nil for an unknown key instead of raising' do
      # AuthConfig#tenant_idp_origin resolves a PROVIDER_ROUTE_MAP route name
      # through here per request, inside the CSP middleware, where a KeyError
      # would 500 the response.
      expect(described_class.find(:facebook)).to be_nil
    end
  end

  describe '.fetch' do
    it 'returns the definition for a known key' do
      expect(described_class.fetch(:oidc)[:strategy]).to eq(:openid_connect)
    end

    it 'raises KeyError for an unknown key' do
      expect { described_class.fetch(:facebook) }.to raise_error(KeyError, /facebook/)
    end

    it 'delegates the lookup to .find (one predicate, no second copy)' do
      allow(described_class).to receive(:find).and_call_original
      described_class.fetch(:oidc)
      expect(described_class).to have_received(:find).with(:oidc)
    end
  end

  describe 'strategy_options' do
    it 'builds options from the env without raising when vars are present' do
      ClimateControl.modify(
        OIDC_ISSUER: 'https://idp.example.com',
        OIDC_CLIENT_ID: 'cid',
        OIDC_CLIENT_SECRET: '',
        ENTRA_TENANT_ID: 'tid',
        ENTRA_CLIENT_ID: 'cid',
        ENTRA_CLIENT_SECRET: 'cs',
        GOOGLE_CLIENT_ID: 'cid',
        GOOGLE_CLIENT_SECRET: 'cs',
        GITHUB_CLIENT_ID: 'cid',
        GITHUB_CLIENT_SECRET: 'cs',
        APPLE_CLIENT_ID: 'com.example.web',
        APPLE_TEAM_ID: 'TEAM123456',
        APPLE_KEY_ID: 'KEY1234567',
        APPLE_PRIVATE_KEY: "-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n",
      ) do
        definitions.each do |defn|
          expect(defn[:strategy_options].call).to be_a(Hash)
        end
      end
    end

    # :vars_valid is opt-in — a definition without it is presence-only and
    # always valid once required_vars are present. No current definition
    # needs one; a definition whose strategy_options can raise must add it
    # (see the registry header) so the advertised and registered sets agree.
    it 'carries no :vars_valid predicate on any current definition' do
      with_predicate = described_class::DEFINITIONS.select { |defn| defn[:vars_valid] }
      expect(with_predicate.map { |defn| defn[:key] }).to be_empty
    end

    # Deployments routinely carry multi-line secrets as a single line with
    # literal backslash-n. OpenSSL::PKey::EC cannot parse that, and the
    # failure would surface as a per-request client-secret error at the Apple
    # request phase rather than at boot.
    it 'un-escapes a backslash-n encoded Apple private key' do
      ClimateControl.modify(APPLE_PRIVATE_KEY: '-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n') do
        opts = described_class.fetch(:apple)[:strategy_options].call
        expect(opts[:pem]).to eq("-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n")
      end
    end

    it 'leaves an already multi-line Apple private key untouched' do
      pem = "-----BEGIN TEST KEY-----\nMHc=\n-----END TEST KEY-----\n"
      ClimateControl.modify(APPLE_PRIVATE_KEY: pem) do
        opts = described_class.fetch(:apple)[:strategy_options].call
        expect(opts[:pem]).to eq(pem)
      end
    end

    # resolve_issuer precedence #1 reads this option. Apple's strategy
    # hard-codes the same constant in verify_iss!, so a row can only exist if
    # Apple itself asserted it — but the strategy nests the claim under
    # extra.raw_info.id_info with symbol keys, which the token-issuer branch
    # does not read. Dropping this option would silently collapse Apple to the
    # '' sentinel and make it issuerless.
    it 'declares the Apple issuer so resolve_issuer does not fall through' do
      opts = described_class.fetch(:apple)[:strategy_options].call
      expect(opts[:issuer]).to eq('https://appleid.apple.com')
    end

    it 'omits the OIDC client secret when blank (PKCE-only flows)' do
      ClimateControl.modify(OIDC_CLIENT_ID: 'cid', OIDC_CLIENT_SECRET: '') do
        opts = described_class.fetch(:oidc)[:strategy_options].call
        expect(opts[:client_options]).not_to have_key(:secret)
      end
    end
  end
end
