# spec/integration/api/v2/plan_cache_miss_handling_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../apps/web/billing/errors'

# Integration tests for API behavior when Billing::PlanCacheMissError is raised.
#
# Issue #3089: Plan ID Matching Overhaul
#
# The fail-closed behavior raises PlanCacheMissError when a plan isn't found
# in cache or config. This test verifies the error propagation behavior:
#
# 1. When an org has an invalid/nonexistent planid, entitlement checks raise
#    PlanCacheMissError (not silently returning defaults)
# 2. Error carries plan_id, organization_id, and context for logging
# 3. Error type allows API layer to handle it as 500 without exposing internals
#
# The error flow:
# 1. API request triggers entitlement check via require_entitlement!
# 2. require_entitlement! calls auth_org.can?(entitlement)
# 3. can? calls entitlements which raises PlanCacheMissError for invalid planid
# 4. Otto catches unhandled exception and returns 500 server_error response
#
# Note: Full HTTP integration tests require SECRET env var. These tests verify
# the error behavior at the logic layer which is sufficient to confirm the
# fail-closed behavior works correctly.
#
RSpec.describe 'API V2 PlanCacheMissError Handling', type: :integration, billing: true do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    # Enable billing so entitlement checks are active
    BillingTestHelpers.restore_billing!(enabled: true)
  end

  after(:all) do
    BillingTestHelpers.cleanup_billing_state!
  end

  # Helper to create a real Organization-like object that includes WithEntitlements
  def create_test_org_class
    Class.new do
      include Onetime::Models::Features::WithEntitlements
      include Onetime::Models::Features::WithMaterializedLimits
      include Onetime::Models::Features::WithPlanEntitlements

      attr_accessor :planid, :extid

      def initialize(planid, extid)
        @planid = planid
        @extid = extid
      end

      def billing_enabled?
        true
      end
    end
  end

  describe 'PlanCacheMissError attributes' do
    # These tests verify the error carries the expected context for logging

    it 'includes plan_id in error for logging' do
      test_class = create_test_org_class
      org = test_class.new('nonexistent_plan_xyz_12345', 'org_test_123')

      expect { org.entitlements }.to raise_error(Billing::PlanCacheMissError) do |error|
        expect(error.plan_id).to eq('nonexistent_plan_xyz_12345')
        expect(error.organization_id).to eq('org_test_123')
        expect(error.context).to eq('WithPlanEntitlements#entitlements')
      end
    end

    it 'includes resource in limit_for errors' do
      test_class = create_test_org_class
      org = test_class.new('nonexistent_plan_xyz_12345', 'org_test_456')

      expect { org.limit_for('teams') }.to raise_error(Billing::PlanCacheMissError) do |error|
        expect(error.plan_id).to eq('nonexistent_plan_xyz_12345')
        expect(error.resource).to eq('teams.max')
        expect(error.context).to eq('WithMaterializedLimits#limit_for')
      end
    end

    it 'raises from can? (which calls entitlements internally)' do
      test_class = create_test_org_class
      org = test_class.new('nonexistent_plan_xyz_12345', 'org_test_789')

      # can? calls entitlements internally, so the error context reflects that
      expect { org.can?(:api_access) }.to raise_error(Billing::PlanCacheMissError) do |error|
        expect(error.plan_id).to eq('nonexistent_plan_xyz_12345')
        expect(error.organization_id).to eq('org_test_789')
        expect(error.context).to eq('WithPlanEntitlements#entitlements')
      end
    end

    it 'includes descriptive error message' do
      test_class = create_test_org_class
      org = test_class.new('invalid_plan_abc', 'org_xyz')

      expect { org.can?('api_access') }.to raise_error(Billing::PlanCacheMissError) do |error|
        expect(error.message).to include('Plan not found in cache or config')
        expect(error.plan_id).to eq('invalid_plan_abc')
      end
    end
  end

  describe 'when org has invalid/nonexistent planid' do
    let(:test_class) { create_test_org_class }
    let(:invalid_org) { test_class.new('nonexistent_plan_xyz_12345', 'org_invalid_123') }

    context 'entitlement checks' do
      it 'raises PlanCacheMissError from can?' do
        expect { invalid_org.can?(:api_access) }.to raise_error(Billing::PlanCacheMissError)
      end

      it 'raises PlanCacheMissError from entitlements' do
        expect { invalid_org.entitlements }.to raise_error(Billing::PlanCacheMissError)
      end

      it 'raises PlanCacheMissError from limit_for' do
        expect { invalid_org.limit_for('teams') }.to raise_error(Billing::PlanCacheMissError)
      end
    end

    context 'error message safety' do
      it 'does not expose internal class names in message' do
        expect { invalid_org.can?(:api_access) }.to raise_error(Billing::PlanCacheMissError) do |error|
          expect(error.message).not_to include('WithEntitlements')
          expect(error.message).not_to include('Onetime::')
        end
      end

      it 'provides context via attributes for logging' do
        expect { invalid_org.can?(:api_access) }.to raise_error(Billing::PlanCacheMissError) do |error|
          # The message is generic, but attributes provide logging context
          expect(error.message).to include('not found')
          expect(error.plan_id).to eq('nonexistent_plan_xyz_12345')
          expect(error.organization_id).to eq('org_invalid_123')
        end
      end
    end
  end

  describe 'error isolation' do
    context 'when one org has invalid planid' do
      it 'does not affect other orgs with valid plans' do
        # Populate a valid plan
        BillingTestHelpers.populate_test_plans([
          {
            plan_id: 'free_v1',
            name: 'Free',
            tier: 1,
            interval: 'month',
            region: 'us',
            entitlements: %w[create_secrets api_access],
            limits: { 'teams.max' => '0' },
          },
        ])

        test_class = create_test_org_class
        valid_org = test_class.new('free_v1', 'org_valid_123')
        invalid_org = test_class.new('nonexistent_plan_xyz_12345', 'org_invalid_456')

        # Valid org should work
        expect { valid_org.can?(:api_access) }.not_to raise_error
        expect(valid_org.can?(:api_access)).to be true

        # Invalid org should fail
        expect { invalid_org.can?(:api_access) }.to raise_error(Billing::PlanCacheMissError)
      end
    end
  end

  describe 'multiple entitlement methods' do
    # Test that all entitlement-checking methods raise PlanCacheMissError
    # This ensures any code path that checks entitlements will fail-closed

    let(:test_class) { create_test_org_class }
    let(:invalid_org) { test_class.new('nonexistent_plan_xyz_12345', 'org_multi_test') }

    it 'can? raises PlanCacheMissError for any entitlement name' do
      %w[api_access view_receipt create_secrets extended_default_expiration].each do |entitlement|
        expect { invalid_org.can?(entitlement) }.to raise_error(Billing::PlanCacheMissError),
          "Expected PlanCacheMissError for entitlement '#{entitlement}'"
      end
    end

    it 'limit_for raises PlanCacheMissError for any resource' do
      %w[teams secrets secret_lifetime api_requests].each do |resource|
        expect { invalid_org.limit_for(resource) }.to raise_error(Billing::PlanCacheMissError),
          "Expected PlanCacheMissError for resource '#{resource}'"
      end
    end

    it 'entitlements raises PlanCacheMissError' do
      expect { invalid_org.entitlements }.to raise_error(Billing::PlanCacheMissError)
    end
  end

  describe 'PlanCacheMissError inheritance' do
    it 'inherits from StandardError' do
      expect(Billing::PlanCacheMissError.ancestors).to include(StandardError)
    end

    it 'is not a user-actionable error type' do
      # Unlike EntitlementRequired which returns 403, PlanCacheMissError
      # should result in 500 because it represents a configuration problem
      expect(Billing::PlanCacheMissError.ancestors).not_to include(Onetime::EntitlementRequired)
    end
  end
end
