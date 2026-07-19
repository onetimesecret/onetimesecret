# apps/web/core/spec/views/serializers/organization_serializer_degrade_spec.rb
#
# frozen_string_literal: true

# Degrade-path coverage for OrganizationSerializer (issue #3813).
#
# Billing::PlanCacheMissError is raised by the model's fail-closed
# entitlements/limits ladders when billing is enabled and a non-empty planid
# resolves in neither the plan cache nor billing.yaml. Before #3813 that raise
# propagated out of the bootstrap serializer and 503'd GET /bootstrap/me,
# blocking login entirely.
#
# Contract under test: the 503 path REMAINS for enforcement callers
# (require_entitlement! and friends stay fail-closed at the model layer —
# see spec/unit/onetime/models/features/with_entitlements_cache_miss_spec.rb
# and spec/api/v2/plan_cache_miss_handling_spec.rb). Only the bootstrap READ
# degrades, at the serializer edge: plan_derived_fields rescues
# PlanCacheMissError and substitutes free-tier entitlements + limits so the
# payload stays schema-valid (string arrays + integers) and login proceeds.
#
# Run with:
#   bundle exec rspec apps/web/core/spec/views/serializers/organization_serializer_degrade_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'
require_relative '../../../../billing/errors'

RSpec.describe Core::Views::OrganizationSerializer do
  before(:all) do
    # Idempotently load Billing::Plan so .load_from_config can be stubbed
    # (verify_partial_doubles requires the real method to exist).
    BillingTestHelpers.ensure_billing_loaded!
  end

  let(:free_tier_entitlements) do
    Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS
  end

  let(:org) do
    instance_double(
      Onetime::Organization,
      objid: 'org_obj_123',
      extid: 'onabc123',
      display_name: 'Acme Workspace',
      is_default: false,
      planid: 'identity_plus_v1',
    )
  end

  # cust: nil keeps determine_user_role out of scope (returns nil early);
  # this spec targets plan_derived_fields only.
  let(:view_vars) do
    {
      'authenticated' => true,
      'organization' => org,
      'cust' => nil,
    }
  end

  def serialized_org
    described_class.serialize(view_vars)['organization']
  end

  describe 'happy path (plan resolves)' do
    before do
      allow(org).to receive(:entitlements).and_return(%w[create_secrets api_access custom_domains])
      allow(org).to receive(:limit_for).with(:teams).and_return(3)
      allow(org).to receive(:limit_for).with(:total_members_per_org).and_return(Float::INFINITY)
      allow(org).to receive(:limit_for).with(:custom_domains).and_return(5)
    end

    it 'serializes live entitlements and limits without degrading' do
      payload = serialized_org

      expect(payload['entitlements']).to eq(%w[create_secrets api_access custom_domains])
      expect(payload['limits']).to eq(
        'teams' => 3,
        'total_members_per_org' => -1, # Float::INFINITY normalizes to -1
        'custom_domains' => 5,
      )
      expect(payload['planid']).to eq('identity_plus_v1')
    end

    it 'does not emit the degrade ops log' do
      expect(OT).not_to receive(:le)
      serialized_org
    end
  end

  describe 'degrade path: entitlements raises PlanCacheMissError' do
    before do
      allow(org).to receive(:entitlements).and_raise(
        Billing::PlanCacheMissError.new(
          plan_id: 'identity_plus_v1',
          organization_id: 'onabc123',
          context: 'WithPlanEntitlements#entitlements',
        )
      )
      allow(OT).to receive(:le)
    end

    context 'when free_v1 resolves from billing config' do
      before do
        # load_from_config returns flattened string keys/values
        # ('teams.max' absent for free tier; 'unlimited' -> -1).
        allow(::Billing::Plan).to receive(:load_from_config).with('free_v1').and_return(
          {
            planid: 'free_v1',
            limits: {
              'total_members_per_org.max' => '1',
              'custom_domains.max' => 'unlimited',
            },
          }
        )
      end

      it 'serializes free-tier entitlements as an array of strings instead of raising' do
        payload = serialized_org

        expect(payload['entitlements']).to eq(free_tier_entitlements)
        expect(payload['entitlements']).to all(be_a(String))
      end

      it 'returns a dup, not the frozen FREE_TIER_ENTITLEMENTS constant' do
        expect(serialized_org['entitlements']).not_to be(free_tier_entitlements)
        expect(serialized_org['entitlements']).not_to be_frozen
      end

      it 'normalizes config limits: missing key -> fallback literal, unlimited -> -1' do
        expect(serialized_org['limits']).to eq(
          'teams' => 0, # absent from config -> FALLBACK_FREE_TIER_LIMITS
          'total_members_per_org' => 1, # '1' -> 1
          'custom_domains' => -1, # 'unlimited' -> -1
        )
      end

      it 'emits exactly the three limit keys, all Integers' do
        limits = serialized_org['limits']

        expect(limits.keys).to contain_exactly('teams', 'total_members_per_org', 'custom_domains')
        expect(limits.values).to all(be_a(Integer))
      end

      it 'logs a single error-level ops line identifying plan and org' do
        serialized_org

        expect(OT).to have_received(:le).once.with(
          a_string_matching(
            /\[OrganizationSerializer\] Plan catalog unavailable.*plan=identity_plus_v1 org=onabc123/
          )
        )
      end
    end

    context 'when free_v1 is also unresolvable from config' do
      before do
        allow(::Billing::Plan).to receive(:load_from_config).with('free_v1').and_return(nil)
      end

      it 'falls back to FALLBACK_FREE_TIER_LIMITS literals' do
        expect(serialized_org['limits']).to eq(
          'teams' => 0,
          'total_members_per_org' => 1,
          'custom_domains' => 1,
        )
      end

      it 'still serializes free-tier entitlements' do
        expect(serialized_org['entitlements']).to eq(free_tier_entitlements)
      end
    end
  end

  describe 'degrade path: limit_for raises PlanCacheMissError' do
    before do
      # entitlements succeeds; the limits reader is what hits the cache miss.
      allow(org).to receive(:entitlements).and_return(%w[create_secrets api_access])
      allow(org).to receive(:limit_for).and_raise(
        Billing::PlanCacheMissError.new(
          plan_id: 'identity_plus_v1',
          organization_id: 'onabc123',
          resource: 'teams.max',
          context: 'WithMaterializedLimits#limit_for',
        )
      )
      allow(::Billing::Plan).to receive(:load_from_config).with('free_v1').and_return(nil)
      allow(OT).to receive(:le)
    end

    it 'degrades BOTH fields together: one rescue wraps both readers' do
      payload = serialized_org

      # The live entitlements read succeeded, but the payload still carries
      # free-tier values: plan_derived_fields degrades atomically so
      # entitlements and limits never disagree about which plan they reflect.
      expect(payload['entitlements']).to eq(free_tier_entitlements)
      expect(payload['limits']).to eq(
        'teams' => 0,
        'total_members_per_org' => 1,
        'custom_domains' => 1,
      )
    end

    it 'logs the degrade once' do
      serialized_org

      expect(OT).to have_received(:le).once.with(a_string_matching(/Plan catalog unavailable/))
    end
  end

  describe 'non-billing errors propagate untouched' do
    before do
      allow(org).to receive(:entitlements).and_raise(ArgumentError, 'not a plan problem')
    end

    it 're-raises instead of swallowing into the degrade path' do
      expect(OT).not_to receive(:le)
      expect { described_class.serialize(view_vars) }
        .to raise_error(ArgumentError, 'not a plan problem')
    end
  end
end
