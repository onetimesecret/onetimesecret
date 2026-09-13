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
  let(:operation) { described_class.new(db) }

  before do
    allow(Auth::Operations::ReadWebauthnCredentials).to receive(:new).with(db).and_return(reader)
    allow(reader).to receive(:call).and_return([])
    allow(Auth::SigninEnabled).to receive(:enabled_for_request?).and_return(true)
    allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id).and_return(nil)
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

        expect(result[:surface]).to eq(kind: :canonical)
        expect(result[:methods]).to eq(%w[password])
        expect(result[:webauthn_credentials]).to eq([])
        expect(result[:related_origins]).to eq([])
      end

      it 'orders webauthn before password when the account has a platform credential' do
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        result = operation.call(account_id: 42, env: env_for(strategy: :canonical))

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
        allow(reader).to receive(:call).with(42).and_return([{ scope: :tenant, id: 'tenant-a' }])
        env = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:methods]).to include('webauthn')
      end
    end

    context 'on a custom surface that has declared related origins' do
      it 'pulls the surface descriptors from the tenant SigninConfig and offers a platform credential' do
        signin_config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          related_origin_surfaces: [
            Onetime::SessionSurface::CANONICAL,
            { kind: :custom, id: 'tenant-a' },
          ].freeze,
        )
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with('tenant-a').and_return(signin_config)
        allow(reader).to receive(:call).with(42).and_return([{ scope: :platform }])
        env           = env_for(strategy: :custom, custom_domain_id: 'tenant-a')

        result = operation.call(account_id: 42, env: env)

        expect(result[:methods]).to include('webauthn')
        expect(result[:related_origins]).to eq(
          [
            Onetime::SessionSurface::CANONICAL,
            { kind: :custom, id: 'tenant-a' },
          ],
        )
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
