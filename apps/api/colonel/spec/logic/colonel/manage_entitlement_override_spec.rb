# apps/api/colonel/spec/logic/colonel/manage_entitlement_override_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The HTTP adapter over Onetime::Operations::Org::EntitlementOverride. The op
# is stubbed: these examples pin how each op status maps to the response, in
# particular that a PARTIAL membership cascade is not reported as a 200 —
# members the cascade missed still read their previous entitlements.
RSpec.describe ColonelAPI::Logic::Colonel::ManageEntitlementOverride do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', role: 'colonel',
      verified?: true, anonymous?: false)
  end

  let(:org) do
    double('Organization',
      objid: 'org_internal', extid: 'on_org_ext', display_name: 'Acme',
      exists?: true, billing_enabled?: true)
  end

  # X-OTS-Confirm carries the org's NAME (#4326, TIER 2).
  def strategy_result_for(confirm_token = 'Acme')
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  let(:strategy_result) { strategy_result_for }

  def result_with(status, memberships: nil)
    Onetime::Operations::Org::EntitlementOverride::Result.new(
      status: status,
      org_id: 'on_org_ext',
      action: 'revoke',
      entitlement: 'api_access',
      effective: ['create_secrets'],
      grants: [],
      revokes: ['api_access'],
      standalone: false,
      dry_run: false,
      memberships: memberships,
    )
  end

  let(:op_result) { result_with(:revoked, memberships: { success: 2, failed: 0, total: 2, failed_ids: [] }) }
  let(:operation) { instance_double(Onetime::Operations::Org::EntitlementOverride, call: op_result) }

  def run(params = {})
    logic = described_class.new(
      strategy_result,
      { 'org_id' => 'on_org_ext', 'action' => 'revoke', 'entitlement' => 'api_access' }.merge(params),
    )
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext').and_return(org)
    allow(Onetime::Operations::Org::EntitlementOverride).to receive(:new).and_return(operation)
    allow(Onetime::Operations::Org::EntitlementOverride).to receive(:known_entitlement?).and_return(true)
  end

  it 'returns the record with the cascade counts when every member was reached' do
    data = run

    expect(data[:record]).to include(
      action: 'revoked',
      effective_entitlements: ['create_secrets'],
      memberships: { success: 2, failed: 0, total: 2, failed_ids: [] },
    )
  end

  it 'always applies (no preview flow on this surface)' do
    run

    expect(Onetime::Operations::Org::EntitlementOverride).to have_received(:new)
      .with(hash_including(org: org, action: 'revoke', entitlement: 'api_access', actor: 'ur_colonel', dry_run: false))
  end

  context 'when the membership cascade was partial' do
    let(:op_result) do
      result_with(:partial, memberships: { success: 1, failed: 1, total: 2, failed_ids: ['mem_stale'] })
    end

    it 'refuses to answer 200 and carries the stale membership ids' do
      expect { run }.to raise_error(OT::FormError) { |ex|
        expect(ex.message).to include('1 of 2 memberships')
        expect(ex.message).to include('org reconcile')
        expect(ex.field).to eq(:memberships)
        expect(ex.details).to eq(memberships: { success: 1, failed: 1, total: 2, failed_ids: ['mem_stale'] })
      }
    end

    it 'does not audit from the adapter (the op already recorded :partial)' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)

      expect { run }.to raise_error(OT::FormError)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  context 'when the membership cascade raised before reaching any member' do
    let(:op_result) do
      result_with(:partial, memberships: {
        success: 0, failed: nil, total: nil, failed_ids: [], cascade_error: 'RuntimeError: valkey unreachable',
      })
    end

    it 'refuses to answer 200 and names the error instead of "nil of nil"' do
      expect { run }.to raise_error(OT::FormError) { |ex|
        expect(ex.message).to include('cascade raised (RuntimeError: valkey unreachable)')
        expect(ex.message).to include('every member still carries their previous entitlements')
        expect(ex.message).to include('org reconcile')
        expect(ex.message).not_to include(' of ')
        expect(ex.field).to eq(:memberships)
      }
    end
  end

  context 'when the op refuses the input' do
    let(:op_result) { result_with(:missing_entitlement) }

    it 'maps :missing_entitlement to a form error on the entitlement field' do
      expect { run }.to raise_error(OT::FormError) { |ex| expect(ex.field).to eq(:entitlement) }
    end
  end
end
