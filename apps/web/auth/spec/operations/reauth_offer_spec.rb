# apps/web/auth/spec/operations/reauth_offer_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::ReauthOffer (#4414). The operation
# assembles the four inputs Onetime::ReauthPolicy.eligible_methods
# needs — surface, password_enabled, webauthn_credentials,
# related_origins — and returns the offer callers act on. Every
# fail-closed branch is covered here: unresolved surface, missing
# account_id, and any StandardError from a dependency.

require 'spec_helper'
require_relative '../../operations/reauth_offer'

RSpec.describe Auth::Operations::ReauthOffer do
  let(:db)        { instance_double(Sequel::Database) }
  let(:reader)    { instance_double(Auth::Operations::ReadWebauthnCredentials) }
  let(:operation) { described_class.new(db, webauthn_loaded: true) }

  before do
    allow(Auth::Operations::ReadWebauthnCredentials).to receive(:new).with(db).and_return(reader)
    allow(reader).to receive(:call).and_return([])
    allow(Auth::SigninEnabled).to receive(:enabled_for_request?).and_return(true)
    allow(operation).to receive(:password_challengeable?).and_return(true)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id).and_return(nil)
    allow(Auth::PublicHost).to receive(:webauthn_base_url).and_return('https://example.com')
  end

  def env_for(strategy:, display_domain: nil, custom_domain_id: nil)
    {
      'onetime.domain_strategy' => strategy,
      'onetime.display_domain' => display_domain,
      'onetime.custom_domain_id' => custom_domain_id,
    }
  end

  describe '#call' do
    context 'on a canonical surface with password enabled' do
      it 'reports the canonical surface and password as the only offered method' do
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result[:surface]).to eq('kind' => 'canonical')
        expect(result[:methods]).to eq(%w[password])
        expect(result[:webauthn_credentials]).to eq([])
        expect(result[:related_origins]).to eq([])
      end

      it 'does not advertise password when this account has no challengeable password' do
        allow(operation).to receive(:password_challengeable?).with(42).and_return(false)

        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result[:methods]).to eq([])
      end

      it 'orders webauthn before password when the account has a platform credential' do
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(reader).to have_received(:call).with(42)
        expect(result[:methods]).to eq(%w[webauthn password])
        expect(result[:webauthn_credentials]).to eq([{ scope: :platform }])
      end
    end

    context 'on a custom surface with only a platform credential' do
      it 'offers password only (no related-origins deployment configured)' do
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:methods]).to eq(%w[password])
        expect(result[:related_origins]).to eq([])
      end
    end

    context 'on a custom surface with a matching tenant credential' do
      it 'offers webauthn (rule 2 of the policy fires)' do
        allow(reader).to receive(:call).with(42)
          .and_return([{ scope: :tenant, id: 'tenant-a', rp_id: 'tenant.example' }])
        allow(Auth::PublicHost).to receive(:webauthn_base_url).and_return('https://tenant.example')
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:methods]).to include('webauthn')
      end
    end

    context 'on a custom surface that has declared related origins' do
      it 'pulls the surface descriptors from the tenant SigninConfig and offers a platform credential' do
        signin_config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          enabled?: true,
          related_origin_members: [
            {
              'origin' => 'https://example.com',
              'surface' => Onetime::SessionSurface::CANONICAL,
            },
            {
              'origin' => 'https://tenant.example',
              'surface' => { 'kind' => 'custom', 'id' => 'tenant-a' },
            },
          ].freeze,
        )
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('tenant-a').and_return(signin_config)
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform, rp_id: 'example.com' }])
        allow(Auth::PublicHost).to receive(:webauthn_base_url).and_return('https://tenant.example')
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:methods]).to include('webauthn')
        expect(result[:related_origins].map { |member| member['origin'] }).to eq(
          ['https://example.com', 'https://tenant.example'],
        )
      end

      it 'does not widen from a disabled tenant sign-in configuration' do
        signin_config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          enabled?: false,
        )
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('tenant-a').and_return(signin_config)
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform, rp_id: 'example.com' }])
        allow(Auth::PublicHost).to receive(:webauthn_base_url).and_return('https://tenant.example')

        result = operation.call(account_id: 42, env: env_for(strategy: :custom, custom_domain_id: 'tenant-a'))

        expect(result[:methods]).not_to include('webauthn')
      end

      it 'never lets a cross-organization custom origin reach the offer (#4421)' do
        # Real SigninConfig, not a double: the org-ownership gate lives in
        # SigninConfig#surface_for_origin and this example proves the offer
        # inherits it. tenant.example (org-a) declares vault.rival.example
        # (org-b) as related; the account holds a passkey registered on the
        # rival tenant. Before the gate, rule 3 of the policy would offer it.
        own_domain = instance_double(
          Onetime::CustomDomain,
          display_domain: 'tenant.example',
          identifier: 'tenant-a',
          org_id: 'org-a',
        )
        signin_config = Onetime::CustomDomain::SigninConfig.new(domain_id: 'tenant-a')
        signin_config.enabled = true
        # Seeded as a stored row: the setter refuses this entry, and the read
        # side is what neutralizes one that is already there.
        signin_config.related_origins_json = JSON.generate(['https://tenant.example', 'https://vault.rival.example'])
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('tenant-a').and_return(signin_config)
        allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_host?).and_return(false)
        allow(Onetime::CustomDomain).to receive(:from_display_domain).with('vault.rival.example')
          .and_return(instance_double(Onetime::CustomDomain, identifier: 'rival-domain-id', org_id: 'org-b'))
        allow(reader).to receive(:call).with(42)
          .and_return([{ scope: :tenant, id: 'rival-domain-id', rp_id: 'vault.rival.example' }])
        allow(Auth::PublicHost).to receive(:webauthn_base_url).and_return('https://tenant.example')
        allow(OT).to receive(:lw)
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a').merge('onetime.custom_domain' => own_domain)

        result = operation.call(account_id: 42, env: env)

        expect(result[:related_origins].map { |member| member['origin'] }).to eq(['https://tenant.example'])
        expect(result[:related_origins].map { |member| member['surface']['id'] }).not_to include('rival-domain-id')
        expect(result[:methods]).not_to include('webauthn')
        expect(OT).to have_received(:lw).with(/cross-organization related origin/, hash_including(domain_id: 'tenant-a'))
      end

      it 'silently skips the tenant lookup when custom_domain_id is missing' do
        env = env_for(strategy: :custom, custom_domain_id: nil)
        operation.call(account_id: 42, env: env)

        expect(Onetime::CustomDomain::SigninConfig).not_to have_received(:find_by_domain_id)
      end
    end

    context 'when password is disabled by SigninPolicyUnavailable' do
      it 'refuses to offer password (fail-closed)' do
        allow(Auth::SigninEnabled).to receive(:enabled_for_request?)
          .and_raise(Onetime::SigninPolicyUnavailable)
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result[:methods]).to eq([])
      end

      it 'refuses to offer password when SigninEnabled raises any other StandardError' do
        allow(Auth::SigninEnabled).to receive(:enabled_for_request?).and_raise('boom')
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result[:methods]).to eq([])
      end
    end

    context 'when the WebAuthn feature is not loaded on this install' do
      let(:operation) { described_class.new(db, webauthn_loaded: false) }

      it 'never reads passkey rows and offers password only' do
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(reader).not_to have_received(:call)
        expect(result[:webauthn_credentials]).to eq([])
        expect(result[:methods]).to eq(%w[password])
      end
    end

    context 'when the credential reader raises' do
      it 'reports [] credentials and does not offer webauthn' do
        allow(reader).to receive(:call).and_raise('boom')
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result[:webauthn_credentials]).to eq([])
        expect(result[:methods]).not_to include('webauthn')
      end
    end

    context 'when the related-origins lookup raises' do
      it 'reports [] related_origins and does not extend the offer' do
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id).and_raise('boom')
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:related_origins]).to eq([])
        expect(result[:methods]).not_to include('webauthn')
      end
    end

    context 'fail-closed boundaries' do
      it 'returns methods: [] and surface: nil for an :invalid domain_strategy' do
        result = operation.call(account_id: 42, env: env_for(strategy: :invalid))

        expect(result[:surface]).to be_nil
        expect(result[:methods]).to eq([])
      end

      it 'returns methods: [] for a nil account_id' do
        result = operation.call(account_id: nil, env: env_for(strategy: :canonical))

        expect(result[:methods]).to eq([])
        expect(result[:webauthn_credentials]).to eq([])
      end

      it 'freezes the returned payload' do
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

        expect(result).to be_frozen
        expect(result[:webauthn_credentials]).to be_frozen
      end
    end
  end
end
