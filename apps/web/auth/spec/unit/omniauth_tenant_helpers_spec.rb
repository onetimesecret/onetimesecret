# apps/web/auth/spec/unit/omniauth_tenant_helpers_spec.rb
#
# frozen_string_literal: true

# Unit tests for OmniAuthTenant HELPERS module methods
#
# Issue: #2786 - Per-domain SSO credential injection
#
# These tests verify the credential injection, strategy matching,
# options merging, and OIDC memoization clearing logic in isolation.
# No Valkey, no HTTP -- pure Ruby method testing with doubles.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/omniauth_tenant_helpers_spec.rb

require_relative '../spec_helper'

# Define module structure for hooks (normally provided by auth app boot)
module Auth
  module Config
    module Hooks
    end
  end
end unless defined?(Auth::Config::Hooks)

# Require Auth::Logging (used by the hook for audit events)
require_relative '../../lib/logging'

# Require the hook module under test
require_relative '../../config/hooks/omniauth_tenant'

RSpec.describe Auth::Config::Hooks::OmniAuthTenant do
  let(:helpers) { described_class }

  # Stub Auth::Logging globally -- these are unit tests, not audit tests
  before do
    allow(Auth::Logging).to receive(:log_auth_event)
  end

  # ==========================================================================
  # strategy_matches?
  # ==========================================================================

  describe '.strategy_matches?' do
    context 'with a matching strategy class' do
      it 'returns true for OpenIDConnect strategy matched to :openid_connect' do
        strategy = instance_double('OmniAuth::Strategies::OpenIDConnect')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :openid_connect)).to be true
      end

      it 'returns true for EntraId strategy matched to :entra_id' do
        strategy = instance_double('OmniAuth::Strategies::EntraId')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::EntraId')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be true
      end

      it 'returns true for AzureActivedirectoryV2 (legacy Entra alias)' do
        strategy = instance_double('OmniAuth::Strategies::AzureActivedirectoryV2')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::AzureActivedirectoryV2')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be true
      end

      it 'returns true for GoogleOauth2 strategy' do
        strategy = instance_double('OmniAuth::Strategies::GoogleOauth2')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GoogleOauth2')

        expect(helpers.strategy_matches?(strategy, :google_oauth2)).to be true
      end

      it 'returns true for GitHub strategy' do
        strategy = instance_double('OmniAuth::Strategies::GitHub')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')

        expect(helpers.strategy_matches?(strategy, :github)).to be true
      end
    end

    context 'with a mismatched strategy class' do
      it 'returns false when Google credentials target an OIDC strategy' do
        strategy = instance_double('OmniAuth::Strategies::OpenIDConnect')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :google_oauth2)).to be false
      end

      it 'returns false when Entra credentials target a GitHub strategy' do
        strategy = instance_double('OmniAuth::Strategies::GitHub')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')

        expect(helpers.strategy_matches?(strategy, :entra_id)).to be false
      end
    end

    context 'with nil or missing inputs' do
      it 'returns false when strategy is nil' do
        expect(helpers.strategy_matches?(nil, :openid_connect)).to be false
      end

      it 'returns false when expected_type is nil' do
        strategy = instance_double('OmniAuth::Strategies::OpenIDConnect')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, nil)).to be false
      end

      it 'returns false when both are nil' do
        expect(helpers.strategy_matches?(nil, nil)).to be false
      end

      it 'returns false for an unknown expected_type symbol' do
        strategy = instance_double('OmniAuth::Strategies::OpenIDConnect')
        allow(strategy).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')

        expect(helpers.strategy_matches?(strategy, :saml)).to be false
      end
    end
  end

  # ==========================================================================
  # merge_strategy_options
  # ==========================================================================

  describe '.merge_strategy_options' do
    let(:options_hash) { {} }
    let(:strategy) do
      double('strategy').tap do |s|
        allow(s).to receive(:options).and_return(options_hash)
      end
    end

    context 'with flat options' do
      it 'writes simple key/value pairs into strategy.options' do
        helpers.merge_strategy_options(strategy, { issuer: 'https://idp.example.com', pkce: true })

        expect(options_hash[:issuer]).to eq('https://idp.example.com')
        expect(options_hash[:pkce]).to be true
      end
    end

    context 'with nested client_options' do
      it 'deep-merges client_options into strategy.options[:client_options]' do
        helpers.merge_strategy_options(strategy, {
          client_options: { identifier: 'my-client', secret: 'my-secret' },
        })

        expect(options_hash[:client_options][:identifier]).to eq('my-client')
        expect(options_hash[:client_options][:secret]).to eq('my-secret')
      end

      it 'preserves existing client_options keys not in the merge' do
        options_hash[:client_options] = { host: 'existing.example.com' }

        helpers.merge_strategy_options(strategy, {
          client_options: { identifier: 'new-client' },
        })

        expect(options_hash[:client_options][:host]).to eq('existing.example.com')
        expect(options_hash[:client_options][:identifier]).to eq('new-client')
      end

      it 'overwrites conflicting client_options keys' do
        options_hash[:client_options] = { identifier: 'old-client', secret: 'old-secret' }

        helpers.merge_strategy_options(strategy, {
          client_options: { identifier: 'new-client' },
        })

        expect(options_hash[:client_options][:identifier]).to eq('new-client')
        expect(options_hash[:client_options][:secret]).to eq('old-secret')
      end

      it 'initializes client_options hash when it does not exist' do
        helpers.merge_strategy_options(strategy, {
          client_options: { identifier: 'first-client' },
        })

        expect(options_hash[:client_options]).to be_a(Hash)
        expect(options_hash[:client_options][:identifier]).to eq('first-client')
      end
    end

    context 'with mixed flat and nested options' do
      it 'handles both in a single call' do
        helpers.merge_strategy_options(strategy, {
          issuer: 'https://idp.example.com',
          discovery: true,
          client_options: { identifier: 'cid', secret: 'csecret' },
        })

        expect(options_hash[:issuer]).to eq('https://idp.example.com')
        expect(options_hash[:discovery]).to be true
        expect(options_hash[:client_options][:identifier]).to eq('cid')
        expect(options_hash[:client_options][:secret]).to eq('csecret')
      end
    end
  end

  # ==========================================================================
  # clear_oidc_memoization
  # ==========================================================================

  describe '.clear_oidc_memoization' do
    context 'when strategy has discovery enabled' do
      let(:strategy) do
        obj = Object.new
        obj.instance_variable_set(:@config, { some: 'cached_config' })
        obj.instance_variable_set(:@client, double('OpenIDConnect::Client'))

        # Provide an options hash with discovery: true
        opts = { discovery: true }
        obj.define_singleton_method(:options) { opts }
        obj.define_singleton_method(:respond_to?) { |m, *| m == :options ? true : super(m) }
        obj
      end

      it 'clears @config instance variable' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@config)).to be_nil
      end

      it 'clears @client instance variable' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@client)).to be_nil
      end
    end

    context 'when strategy does not have discovery enabled' do
      let(:strategy) do
        obj = Object.new
        obj.instance_variable_set(:@config, { some: 'data' })
        obj.instance_variable_set(:@client, double('client'))
        opts = { discovery: false }
        obj.define_singleton_method(:options) { opts }
        obj
      end

      it 'does not clear @config' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@config)).not_to be_nil
      end

      it 'does not clear @client' do
        helpers.clear_oidc_memoization(strategy)
        expect(strategy.instance_variable_get(:@client)).not_to be_nil
      end
    end

    context 'when strategy has no memoized ivars' do
      let(:strategy) do
        obj = Object.new
        opts = { discovery: true }
        obj.define_singleton_method(:options) { opts }
        obj
      end

      it 'does not raise' do
        expect { helpers.clear_oidc_memoization(strategy) }.not_to raise_error
      end
    end

    context 'when strategy does not respond to options' do
      let(:strategy) { Object.new }

      it 'does not raise' do
        expect { helpers.clear_oidc_memoization(strategy) }.not_to raise_error
      end
    end
  end

  # ==========================================================================
  # inject_tenant_credentials (integration of the above)
  # ==========================================================================

  describe '.inject_tenant_credentials' do
    let(:options_hash) { {} }

    let(:strategy) do
      double('OmniAuth::Strategies::OpenIDConnect').tap do |s|
        allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::OpenIDConnect')
        allow(s).to receive(:options).and_return(options_hash)
        allow(s).to receive(:respond_to?).with(:options).and_return(true)
        allow(s).to receive(:instance_variable_defined?).with(:@config).and_return(false)
        allow(s).to receive(:instance_variable_defined?).with(:@client).and_return(false)
      end
    end

    let(:request) do
      double('Rack::Request').tap do |r|
        allow(r).to receive(:env).and_return({ 'omniauth.strategy' => strategy })
      end
    end

    let(:sso_config) do
      double('Onetime::DomainSsoConfig',
        domain_id: 'dom_test_123',
        provider_type: 'oidc',
        to_omniauth_options: {
          strategy: :openid_connect,
          name: 'dom_test_123',
          issuer: 'https://auth.tenant.com',
          discovery: true,
          pkce: true,
          client_options: {
            identifier: 'tenant-client-id',
            secret: 'tenant-client-secret',
          },
        },
      )
    end

    it 'writes tenant credentials into strategy.options' do
      helpers.inject_tenant_credentials(sso_config, request)

      expect(options_hash[:issuer]).to eq('https://auth.tenant.com')
      expect(options_hash[:discovery]).to be true
      expect(options_hash[:pkce]).to be true
      expect(options_hash[:client_options][:identifier]).to eq('tenant-client-id')
      expect(options_hash[:client_options][:secret]).to eq('tenant-client-secret')
    end

    it 'does not leak :strategy or :name keys into strategy.options' do
      helpers.inject_tenant_credentials(sso_config, request)

      # :strategy and :name are consumed by inject_tenant_credentials,
      # not passed through to the strategy's runtime options
      expect(options_hash).not_to have_key(:strategy)
      expect(options_hash).not_to have_key(:name)
    end

    context 'when strategy type does not match configuration' do
      let(:mismatched_strategy) do
        double('OmniAuth::Strategies::GitHub').tap do |s|
          allow(s).to receive_message_chain(:class, :name).and_return('OmniAuth::Strategies::GitHub')
          allow(s).to receive(:options).and_return({})
        end
      end

      let(:request) do
        double('Rack::Request').tap do |r|
          allow(r).to receive(:env).and_return({ 'omniauth.strategy' => mismatched_strategy })
        end
      end

      it 'raises Onetime::Problem' do
        expect { helpers.inject_tenant_credentials(sso_config, request) }
          .to raise_error(Onetime::Problem, /SSO provider mismatch/)
      end
    end

    context 'when no strategy is present in the request env' do
      let(:request) do
        double('Rack::Request').tap do |r|
          allow(r).to receive(:env).and_return({ 'omniauth.strategy' => nil })
        end
      end

      it 'returns early without raising' do
        expect { helpers.inject_tenant_credentials(sso_config, request) }.not_to raise_error
      end
    end
  end
end
