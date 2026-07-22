# spec/unit/onetime/initializers/check_tenant_sso_trust_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Boot guard for the #3836 email-linking trust flag. It WARNS (non-fatal)
# when the flag is enabled AND tenant CustomDomain::SsoConfig records exist,
# because the flag is ignored on the multi-tenant surface by construction.
#
# Truth table:
#   flag off,           any SsoConfig count  -> no warn (returns before count)
#   flag on,  count 0                        -> no warn
#   flag on,  count > 0                      -> warn, never raises
RSpec.describe Onetime::Initializers::CheckTenantSsoTrust do
  subject(:initializer) { described_class.new }

  let(:logger) { instance_double('SemanticLogger::Logger', warn: nil) }

  before do
    # Spy on the Auth logger the guard emits through.
    allow(initializer).to receive(:auth_logger).and_return(logger)
  end

  def stub_flag(enabled)
    allow(Onetime.auth_config)
      .to receive(:trust_email_for_linking_enabled?).and_return(enabled)
  end

  def stub_sso_config_count(count)
    allow(Onetime::CustomDomain::SsoConfig).to receive(:count).and_return(count)
  end

  describe '#execute' do
    context 'when the trust flag is OFF' do
      before { stub_flag(false) }

      it 'does not warn even if tenant SsoConfigs exist' do
        stub_sso_config_count(5)
        initializer.execute({})
        expect(logger).not_to have_received(:warn)
      end

      it 'never touches the datastore (returns before counting)' do
        # If the guard queried count here it would defeat the silent-boot goal.
        expect(Onetime::CustomDomain::SsoConfig).not_to receive(:count)
        initializer.execute({})
      end
    end

    context 'when the trust flag is ON but no tenant SsoConfig exists' do
      before do
        stub_flag(true)
        stub_sso_config_count(0)
      end

      it 'does not warn (nothing on the multi-tenant surface to flag)' do
        initializer.execute({})
        expect(logger).not_to have_received(:warn)
      end
    end

    context 'when the trust flag is ON and tenant SsoConfig(s) exist' do
      before do
        stub_flag(true)
        stub_sso_config_count(3)
      end

      it 'emits a single warn-level message' do
        initializer.execute({})
        expect(logger).to have_received(:warn).once
      end

      it 'names the flag and the multi-tenant scope in the message' do
        initializer.execute({})
        expect(logger).to have_received(:warn) do |msg|
          expect(msg).to include('check_tenant_sso_trust')
          expect(msg).to match(/multi-tenant/i)
        end
      end

      it 'does NOT raise (production has live tenant SsoConfigs + ~200k accounts)' do
        expect { initializer.execute({}) }.not_to raise_error
      end

      it 'uses the O(1) count, never enumerates records' do
        expect(Onetime::CustomDomain::SsoConfig).not_to receive(:all)
        initializer.execute({})
      end
    end
  end

  describe 'registration metadata' do
    it 'depends on :database' do
      expect(described_class.depends_on).to eq([:database])
    end

    it 'is optional (a guard, never fatal to boot)' do
      expect(described_class.optional).to be true
    end

    it 'derives the expected initializer key' do
      expect(described_class.initializer_name)
        .to eq(:'onetime.initializers.check_tenant_sso_trust')
    end
  end
end
