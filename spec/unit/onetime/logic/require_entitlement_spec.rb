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
# - Raises EntitlementRequired if no auth_org context (system issue)
# - Returns true if the auth_org has the requested entitlement
# - Raises EntitlementRequired if the auth_org lacks the entitlement
#
# These tests use a minimal test harness that wires up a @strategy_result
# with organization_context metadata, matching how the real auth_org
# method reads from StrategyResult in OrganizationContext.
#
RSpec.describe 'Onetime::Logic::Base#require_entitlement!' do
  # Minimal test harness that mirrors how auth_org and require_entitlement!
  # work in the real Onetime::Logic::Base + OrganizationContext.
  #
  # auth_org reads immutably from @strategy_result.metadata, matching
  # the production code path. This avoids the old pattern of storing
  # the org in a mutable @org ivar.
  let(:test_class) do
    Class.new do
      attr_reader :strategy_result

      def initialize(strategy_result)
        @strategy_result = strategy_result
      end

      # Mirrors OrganizationContext#auth_org: reads immutably from
      # strategy_result metadata, not from a mutable ivar.
      def auth_org
        @strategy_result&.metadata&.dig(:organization_context, :organization)
      end

      # Mirrors Onetime::Logic::Base#require_entitlement! — uses auth_org
      # to check entitlements against the authenticated session's org.
      def require_entitlement!(entitlement)
        entitlement = entitlement.to_s

        # Fail-closed: auth_org context required for entitlement checks.
        # OrganizationLoader self-heals, so nil auth_org indicates a system issue.
        unless auth_org
          raise Onetime::EntitlementRequired.new(
            entitlement,
            message: 'Unable to verify entitlements (organization context unavailable)',
          )
        end

        # Check if auth_org has the entitlement
        return true if auth_org.can?(entitlement)

        # Build upgrade path info
        current_plan = auth_org.planid
        upgrade_to   = if defined?(Billing::PlanHelpers)
                         Billing::PlanHelpers.upgrade_path_for(entitlement, current_plan)
                       end

        raise Onetime::EntitlementRequired.new(
          entitlement,
          current_plan: current_plan,
          upgrade_to: upgrade_to,
        )
      end
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

  describe 'when auth_org is nil (fail-closed behavior)' do
    subject(:logic) { test_class.new(strategy_result_class.new(metadata: {})) }

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

    context 'when strategy_result itself is nil' do
      subject(:logic) { test_class.new(nil) }

      it 'raises EntitlementRequired (fail-closed)' do
        expect { logic.require_entitlement!('api_access') }
          .to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'when auth_org has the entitlement' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr)
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
      test_class.new(sr)
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
      test_class.new(sr)
    end

    before do
      allow(organization).to receive(:can?).with('custom_domains').and_return(false)
      allow(organization).to receive(:planid).and_return('identity_v1')
    end

    it 'provides a to_h method for serialization' do
      begin
        logic.require_entitlement!('custom_domains')
      rescue Onetime::EntitlementRequired => e
        hash = e.to_h
        expect(hash).to include(
          entitlement: 'custom_domains',
          current_plan: 'identity_v1'
        )
        expect(hash[:error]).to include('custom domains')
      end
    end
  end

  describe 'different entitlement types' do
    subject(:logic) do
      sr = strategy_result_class.new(metadata: { organization_context: { organization: organization } })
      test_class.new(sr)
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
