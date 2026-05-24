# spec/unit/onetime/logic/sso_only_gating_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/logic/sso_only_gating'

# Unit tests for SsoOnlyGating module
#
# Tests the module method directly without requiring full logic class setup.
# Focused on the i18n error_key shape on the Forbidden raise — the resolver
# itself is covered by spec/unit/onetime/application/error_resolver_spec.rb.
#
RSpec.describe Onetime::Logic::SsoOnlyGating do
  let(:test_class) do
    Class.new do
      include Onetime::Logic::SsoOnlyGating
    end
  end

  let(:instance) { test_class.new }

  let(:auth_config) { double('AuthConfig') }

  before do
    allow(Onetime).to receive(:auth_config).and_return(auth_config)
  end

  describe '#require_non_sso_only!' do
    context 'when SSO-only mode is not active' do
      before do
        allow(auth_config).to receive(:sso_only_enabled?).and_return(false)
      end

      it 'returns true without raising' do
        expect(instance.require_non_sso_only!).to be true
      end
    end

    context 'when SSO-only mode is active' do
      before do
        allow(auth_config).to receive(:sso_only_enabled?).and_return(true)
      end

      it 'raises Onetime::Forbidden' do
        expect { instance.require_non_sso_only! }.to raise_error(Onetime::Forbidden)
      end

      it 'preserves the legacy English message as the fallback' do
        expect { instance.require_non_sso_only! }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.message).to eq('This action is not available in SSO-only mode')
          end
      end

      it 'tags the error with the sso_only_action_blocked i18n key' do
        expect { instance.require_non_sso_only! }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key).to eq('api.errors.sso_only_action_blocked')
          end
      end

      it 'sets args to an empty hash (no interpolation values)' do
        expect { instance.require_non_sso_only! }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.args).to eq({})
          end
      end

      it 'serializes error_key into to_h for the HTTP response body' do
        expect { instance.require_non_sso_only! }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.to_h).to include(
              error: 'Forbidden',
              message: 'This action is not available in SSO-only mode',
              error_key: 'api.errors.sso_only_action_blocked',
            )
          end
      end
    end
  end
end
