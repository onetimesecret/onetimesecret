# spec/unit/onetime/logic/require_entitlement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for the require_entitlement! helper method
#
# This method is defined in Onetime::Logic::Base and is used to gate
# access to protected API endpoints based on organization entitlements.
#
# The method (fail-closed behavior):
# - Returns true if the user is anonymous (entitlement checks skipped)
# - Raises EntitlementRequired if no auth_org context (system issue)
# - Returns true if the auth_org has the requested entitlement
# - Raises EntitlementRequired if the auth_org lacks the entitlement
#
# These tests subclass the real Onetime::Logic::Base to exercise the real
# require_entitlement! (and the real auth_org from OrganizationContext,
# and the real anonymous_user? from AuthorizationPolicies) via the
# inheritance chain — avoiding mock-vs-prod drift from a reimplemented stub.
#
RSpec.describe 'Onetime::Logic::Base#require_entitlement!' do
  # Subclass the real Onetime::Logic::Base so the inherited
  # require_entitlement! (and auth_org / anonymous_user?) is exercised.
  #
  # We bypass the real Base#initialize side effects (process_settings,
  # extract_organization_context, extract_domain_context, process_params,
  # etc.) and set only the ivars that require_entitlement! reads through
  # auth_org and anonymous_user?: @strategy_result and @cust.
  let(:test_class) do
    Class.new(Onetime::Logic::Base) do
      def initialize(strategy_result, cust: nil)
        @strategy_result = strategy_result
        @cust            = cust
      end

      # Expose the protected method for spec access
      public :require_entitlement!
    end
  end

  # Lightweight stand-in for StrategyResult. Provides the metadata
  # hash that auth_org reads via dig(:organization_context, :organization).
  let(:strategy_result_class) do
    Struct.new(:metadata, keyword_init: true)
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      planid: 'free',
      can?: false
    )
  end

  # Non-anonymous customer for examples that need to reach the auth_org /
  # entitlement-check branches (the anonymous short-circuit returns true
  # before either branch is hit).
  let(:authenticated_cust) do
    double('Customer', anonymous?: false, custid: 'cust123', organization_instances: [])
  end

  describe 'when auth_org is nil (fail-closed behavior)' do
    subject(:logic) { test_class.new(strategy_result_class.new(metadata: {}), cust: authenticated_cust) }

    before do
      # Stub lazy-creation to return nil so auth_org stays nil
      allow(Auth::Operations::CreateDefaultWorkspace).to receive(:new).and_return(
        double(call: nil)
      )
    end

    it 'raises EntitlementRequired (fail-closed)' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired)
    end

    it 'includes the entitlement name in the error' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('api_access')
        end
    end

    it 'includes a descriptive message about missing auth_org context' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.message).to include('organization context unavailable')
        end
    end

    it 'works with symbol entitlement names' do
      expect { logic.require_entitlement!(:api_access) }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('api_access')
        end
    end

    it 'sets error_key to the context_unavailable system-error key' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.error_key).to eq('api.entitlements.errors.context_unavailable')
        end
    end

    it 'includes the entitlement in args even on the no-auth_org branch' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.args).to eq(entitlement: 'api_access')
        end
    end

    context 'when strategy_result itself is nil' do
      subject(:logic) { test_class.new(nil, cust: authenticated_cust) }

      it 'raises EntitlementRequired (fail-closed)' do
        expect { logic.require_entitlement!('api_access') }
          .to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'when cust is anonymous' do
    let(:anonymous_cust) { double('Customer', anonymous?: true, custid: nil) }

    it 'returns true without checking entitlements (no raise)' do
      sr = strategy_result_class.new(metadata: {})
      instance = test_class.new(sr, cust: anonymous_cust)
      expect(instance.require_entitlement!('api_access')).to be true
    end

    it 'returns true even when entitlement string is unknown' do
      sr = strategy_result_class.new(metadata: {})
      instance = test_class.new(sr, cust: anonymous_cust)
      expect(instance.require_entitlement!('totally_made_up_entitlement')).to be true
    end
  end

  describe 'when auth_org has the entitlement' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr, cust: authenticated_cust)
    end

    before do
      allow(organization).to receive(:can?).with('api_access').and_return(true)
    end

    it 'returns true' do
      expect(logic.require_entitlement!('api_access')).to be true
    end

    it 'does not raise an error' do
      expect { logic.require_entitlement!('api_access') }.not_to raise_error
    end

    it 'converts symbol entitlement to string before checking' do
      allow(organization).to receive(:can?).with('custom_domains').and_return(true)
      expect(logic.require_entitlement!(:custom_domains)).to be true
    end
  end

  describe 'when auth_org lacks the entitlement' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr, cust: authenticated_cust)
    end

    before do
      allow(organization).to receive(:can?).with('api_access').and_return(false)
      allow(organization).to receive(:planid).and_return('free')
    end

    it 'raises EntitlementRequired error' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired)
    end

    it 'includes the entitlement name in the error' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('api_access')
        end
    end

    it 'includes the current plan in the error' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.current_plan).to eq('free')
        end
    end

    it 'includes a human-readable error message' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.message).to include('api access')
        end
    end

    it 'auto-derives error_key from the entitlement name' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.error_key).to eq('api.entitlements.errors.api_access_required')
        end
    end

    it 'auto-derives error_key when entitlement is given as a symbol' do
      allow(organization).to receive(:can?).with('custom_domains').and_return(false)
      expect { logic.require_entitlement!(:custom_domains) }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.error_key).to eq('api.entitlements.errors.custom_domains_required')
        end
    end

    it 'lets an explicit error_key argument override the auto-derived one' do
      expect { logic.require_entitlement!('api_access', error_key: 'custom.override.key') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.error_key).to eq('custom.override.key')
        end
    end

    it 'includes the entitlement in args for i18n interpolation' do
      expect { logic.require_entitlement!('api_access') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.args).to eq(entitlement: 'api_access')
        end
    end

    context 'with upgrade path available' do
      before do
        stub_const('Billing::PlanHelpers', double('PlanHelpers'))
        allow(Billing::PlanHelpers).to receive(:upgrade_path_for)
          .with('api_access', 'free')
          .and_return('identity_v1')
      end

      it 'includes upgrade_to suggestion in the error' do
        expect { logic.require_entitlement!('api_access') }
          .to raise_error(Onetime::EntitlementRequired) do |error|
            expect(error.upgrade_to).to eq('identity_v1')
          end
      end
    end

    context 'without upgrade path (Billing::PlanHelpers not defined)' do
      it 'sets upgrade_to to nil' do
        expect { logic.require_entitlement!('api_access') }
          .to raise_error(Onetime::EntitlementRequired) do |error|
            expect(error.upgrade_to).to be_nil
          end
      end
    end
  end

  describe 'EntitlementRequired error structure' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr, cust: authenticated_cust)
    end

    before do
      allow(organization).to receive(:can?).with('custom_domains').and_return(false)
      allow(organization).to receive(:planid).and_return('identity_v1')
    end

    it 'provides a to_h method for serialization' do
      expect { logic.require_entitlement!('custom_domains') }
        .to raise_error(Onetime::EntitlementRequired) do |error|
          hash = error.to_h
          expect(hash).to include(
            entitlement: 'custom_domains',
            current_plan: 'identity_v1',
            error_key: 'api.entitlements.errors.custom_domains_required',
          )
          expect(hash[:error]).to include('custom domains')
        end
    end

    it 'omits error_key from to_h when none is set' do
      # Direct construction without an error_key — to_h should compact it out
      # so legacy callers that don't use the i18n shape see the same hash.
      err = Onetime::EntitlementRequired.new('custom_domains', current_plan: 'identity_v1')
      expect(err.to_h).not_to have_key(:error_key)
      expect(err.to_h).to include(entitlement: 'custom_domains', current_plan: 'identity_v1')
    end
  end

  describe 'different entitlement types' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr, cust: authenticated_cust)
    end

    %w[api_access custom_domains create_teams audit_logs advanced_analytics].each do |entitlement|
      context "with '#{entitlement}' entitlement" do
        before do
          allow(organization).to receive(:can?).with(entitlement).and_return(false)
          allow(organization).to receive(:planid).and_return('free')
        end

        it 'raises EntitlementRequired with correct entitlement name' do
          expect { logic.require_entitlement!(entitlement) }
            .to raise_error(Onetime::EntitlementRequired) do |error|
              expect(error.entitlement).to eq(entitlement)
            end
        end
      end
    end
  end

end
