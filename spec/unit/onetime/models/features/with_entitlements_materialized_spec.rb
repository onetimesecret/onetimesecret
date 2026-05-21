# spec/unit/onetime/models/features/with_entitlements_materialized_spec.rb
#
# frozen_string_literal: true

# Unit tests for the Phase 2 read path in WithEntitlements (Issue #3134).
#
# The guard in #entitlements and #limit_for:
#   if respond_to?(:entitlements_materialized?) && entitlements_materialized?
#     return materialized_entitlements.to_a   # or materialized_limit_for(key)
#   end
#
# Verifies:
#  - Materialized org reads from materialized sets, never calls Plan.load
#  - Unmaterialized org (WithMaterializedEntitlements not included, or not yet
#    stamped) falls back to the legacy Plan.load chain
#  - limit_for reads from limits_plan when materialized
#  - can?(entitlement) works correctly end-to-end for a materialized org
#
# Run: pnpm run test:rspec spec/unit/onetime/models/features/with_entitlements_materialized_spec.rb

require 'spec_helper'

RSpec.describe 'WithEntitlements read path — materialized guard', billing: true do

  # ============================================================================
  # Shared test class factory
  # ============================================================================

  # Build a class that includes both features in the same order as Organization.
  # We pass the materialized state in at construction time so tests can control
  # the guard without touching Redis.
  #
  # @param is_materialized [Boolean] whether entitlements_materialized? returns true
  # @param ents [Array<String>] what materialized_entitlements.to_a returns
  # @param limits [Hash] what limits_plan[key] returns
  def build_class(is_materialized:, ents: [], limits: {})
    materialized_flag = is_materialized
    materialized_ents  = ents
    materialized_lims  = limits

    Class.new do
      include Onetime::Models::Features::WithEntitlements

      attr_accessor :planid, :extid

      def initialize(planid, extid: 'test_org_mat_spec')
        @planid = planid
        @extid  = extid
      end

      def billing_enabled?
        true
      end

      # Simulate WithMaterializedEntitlements being present
      define_method(:entitlements_materialized?) { materialized_flag }

      define_method(:materialized_entitlements) do
        # Simple struct (not an RSpec double) — usable inside Class.new
        mat = Object.new
        mat.define_singleton_method(:to_a) { materialized_ents }
        mat
      end

      define_method(:materialized_limit_for) do |key|
        val = materialized_lims[key]
        return 0 if val.nil?

        val == 'unlimited' ? Float::INFINITY : val.to_i
      end
    end
  end

  # ============================================================================
  # Section 1: #entitlements — materialized path
  # ============================================================================

  describe '#entitlements — materialized path' do
    context 'when entitlements_materialized? is true' do
      let(:klass) do
        build_class(
          is_materialized: true,
          ents: %w[api_access custom_domains manage_teams],
        )
      end
      let(:org) { klass.new('identity_plus_v1') }

      it 'returns materialized_entitlements directly' do
        expect(org.entitlements).to contain_exactly('api_access', 'custom_domains', 'manage_teams')
      end

      it 'never calls Billing::Plan.load' do
        expect(Billing::Plan).not_to receive(:load)

        org.entitlements
      end

      it 'never calls Billing::Plan.load_from_config' do
        expect(Billing::Plan).not_to receive(:load_from_config)

        org.entitlements
      end
    end
  end

  # ============================================================================
  # Section 2: #entitlements — unmaterialized legacy fallback
  # ============================================================================

  describe '#entitlements — unmaterialized / legacy fallback' do
    context 'when entitlements_materialized? is false (org not yet migrated)' do
      let(:klass) do
        build_class(is_materialized: false)
      end
      let(:org) { klass.new('identity_plus_v1') }

      it 'calls Billing::Plan.load (legacy path)' do
        mock_plan = instance_double(
          Billing::Plan,
          entitlements: double(to_a: %w[api_access custom_domains]),
        )
        expect(Billing::Plan).to receive(:load).with('identity_plus_v1').and_return(mock_plan)

        org.entitlements
      end
    end

    context 'when respond_to?(:entitlements_materialized?) is false (feature not included)' do
      let(:klass) do
        Class.new do
          include Onetime::Models::Features::WithEntitlements

          attr_accessor :planid, :extid

          def initialize(planid)
            @planid = planid
            @extid  = 'test_no_feature'
          end

          def billing_enabled?
            true
          end
          # Does NOT define entitlements_materialized? — simulates pre-migration class
        end
      end
      let(:org) { klass.new('identity_plus_v1') }

      it 'falls through to Plan.load without error' do
        mock_plan = instance_double(
          Billing::Plan,
          entitlements: double(to_a: %w[api_access]),
        )
        allow(Billing::Plan).to receive(:load).and_return(mock_plan)

        expect { org.entitlements }.not_to raise_error
      end
    end
  end

  # ============================================================================
  # Section 3: #limit_for — materialized path
  # ============================================================================

  describe '#limit_for — materialized path' do
    context 'when entitlements_materialized? is true' do
      let(:klass) do
        build_class(
          is_materialized: true,
          limits: {
            'teams.max'           => '5',
            'secret_lifetime.max' => 'unlimited',
          },
        )
      end
      let(:org) { klass.new('identity_plus_v1') }

      it 'returns integer limit from materialized limits' do
        expect(org.limit_for('teams')).to eq(5)
      end

      it 'returns Float::INFINITY for "unlimited"' do
        expect(org.limit_for('secret_lifetime')).to eq(Float::INFINITY)
      end

      it 'returns 0 for unknown resource' do
        expect(org.limit_for('nonexistent_resource')).to eq(0)
      end

      it 'never calls Billing::Plan.load' do
        expect(Billing::Plan).not_to receive(:load)

        org.limit_for('teams')
      end
    end
  end

  # ============================================================================
  # Section 4: #can? end-to-end with materialized entitlements
  # ============================================================================

  describe '#can? with materialized entitlements' do
    let(:klass) do
      build_class(
        is_materialized: true,
        ents: %w[api_access manage_teams],
      )
    end
    let(:org) { klass.new('identity_plus_v1') }

    it 'returns true for an included entitlement' do
      expect(org.can?('api_access')).to be true
    end

    it 'returns true for symbol form' do
      expect(org.can?(:manage_teams)).to be true
    end

    it 'returns false for an entitlement not in materialized set' do
      expect(org.can?('custom_domains')).to be false
    end
  end
end
