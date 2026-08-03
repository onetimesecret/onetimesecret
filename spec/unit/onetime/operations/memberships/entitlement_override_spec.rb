# spec/unit/onetime/operations/memberships/entitlement_override_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Memberships::EntitlementOverride (#3907,
# closing D19 of #3731).
#
# Two layers, mirroring the org op spec + set_role_spec:
#   1. Mocked contract — action validation, membership resolution
#      (:not_found), the DELIBERATELY asymmetric no-change rule (grant/revoke
#      short-circuit, clear never does — D15), the dry-run projection, the
#      exactly-once audit event with the membership-scoped verb, and the
#      standalone flag. The membership double reproduces the MODEL's override
#      semantics (grant removes from revokes and vice versa; every mutation
#      recomputes plan ∪ grants − revokes) so the op is tested against the
#      contract it actually depends on.
#   2. Real materialization — grant/revoke against a REAL
#      OrganizationMembership flips can?, proving the op reaches the
#      membership's materialized entitlement check end to end.
#
# Run: bundle exec rspec spec/unit/onetime/operations/memberships/entitlement_override_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/memberships/entitlement_override'

RSpec.describe Onetime::Operations::Memberships::EntitlementOverride do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  let(:billing_enabled) { true }

  let(:org) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      billing_enabled?: billing_enabled,
    )
  end

  let(:customer) do
    double('Customer', objid: 'cust-obj-1', extid: 'ur_member')
  end

  # Mutable backing arrays — the membership double reads these live, so an
  # applied mutation is observable in the Result the op builds afterwards.
  let(:plan_members)         { %w[create_secrets api_access] }
  let(:grant_members)        { [] }
  let(:revoke_members)       { [] }
  let(:materialized_members) { (plan_members | grant_members) - revoke_members }

  # Mirror of the model's apply_entitlements reconciliation.
  def reconcile!
    materialized_members.replace((plan_members | grant_members) - revoke_members)
  end

  let(:membership) do
    instance = double('OrganizationMembership', active?: true)

    # Fresh set-doubles per read so they reflect the CURRENT backing arrays.
    allow(instance).to receive(:entitlements_plan)         { double('PlanSet', to_a: plan_members.dup) }
    allow(instance).to receive(:entitlements_grants)       { double('GrantsSet', to_a: grant_members.dup) }
    allow(instance).to receive(:entitlements_revokes)      { double('RevokesSet', to_a: revoke_members.dup) }
    allow(instance).to receive(:materialized_entitlements) { double('MaterializedSet', to_a: materialized_members.dup) }

    # Model semantics: grant/revoke are mutually exclusive, both reconcile.
    allow(instance).to receive(:grant_entitlement) do |ent|
      revoke_members.delete(ent)
      grant_members << ent unless grant_members.include?(ent)
      reconcile!
    end
    allow(instance).to receive(:revoke_entitlement) do |ent|
      grant_members.delete(ent)
      revoke_members << ent unless revoke_members.include?(ent)
      reconcile!
    end
    allow(instance).to receive(:clear_entitlement_overrides) do
      grant_members.clear
      revoke_members.clear
      reconcile!
    end

    instance
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::OrganizationMembership)
      .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(membership)
  end

  def run(action, entitlement: nil, dry_run: false)
    described_class.new(
      org: org, customer: customer, action: action, actor: actor,
      entitlement: entitlement, dry_run: dry_run
    ).call
  end

  describe 'grant' do
    it 'applies via the model and reports the post-mutation sets' do
      result = run('grant', entitlement: 'custom_branding')

      expect(result.status).to eq(:granted)
      expect(result.action).to eq('grant')
      expect(result.entitlement).to eq('custom_branding')
      expect(result.org_id).to eq('on_org_ext')
      expect(result.member_id).to eq('ur_member')
      expect(result.dry_run).to be(false)
      expect(membership).to have_received(:grant_entitlement).with('custom_branding').once
      expect(result.grants).to eq(['custom_branding'])
      expect(result.revokes).to eq([])
      expect(result.effective).to contain_exactly('create_secrets', 'api_access', 'custom_branding')
    end

    it 'records EXACTLY ONE audit event, fully specified (org_id rides in detail)' do
      run('grant', entitlement: 'custom_branding')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.entitlement.grant',
        target: 'ur_member',
        result: :success,
        detail: { org_id: 'on_org_ext', entitlement: 'custom_branding' },
      )
    end

    it 'moves an entitlement out of revokes (grant takes precedence)' do
      revoke_members << 'api_access'

      result = run('grant', entitlement: 'api_access')

      expect(result.status).to eq(:granted)
      expect(result.grants).to eq(['api_access'])
      expect(result.revokes).to eq([])
    end

    it 'normalizes a padded/mixed-case action and a padded entitlement' do
      result = described_class.new(
        org: org, customer: customer, action: ' GRANT ', actor: actor,
        entitlement: '  custom_branding  ', dry_run: false
      ).call

      expect(result.status).to eq(:granted)
      expect(membership).to have_received(:grant_entitlement).with('custom_branding')
    end
  end

  describe 'revoke' do
    it 'applies via the model and drops the entitlement from effective' do
      result = run('revoke', entitlement: 'api_access')

      expect(result.status).to eq(:revoked)
      expect(membership).to have_received(:revoke_entitlement).with('api_access').once
      expect(result.revokes).to eq(['api_access'])
      expect(result.effective).to eq(['create_secrets'])
    end

    it 'records EXACTLY ONE audit event with the revoke verb' do
      run('revoke', entitlement: 'api_access')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'membership.entitlement.revoke',
          target: 'ur_member',
          detail: { org_id: 'on_org_ext', entitlement: 'api_access' },
        )
      )
    end
  end

  describe 'clear' do
    before do
      grant_members << 'custom_branding'
      revoke_members << 'api_access'
      reconcile!
    end

    it 'wipes both override sets and returns the role baseline' do
      result = run('clear')

      expect(result.status).to eq(:cleared)
      expect(result.entitlement).to be_nil
      expect(membership).to have_received(:clear_entitlement_overrides).once
      expect(result.grants).to eq([])
      expect(result.revokes).to eq([])
      expect(result.effective).to contain_exactly('create_secrets', 'api_access')
    end

    it 'records an audit event whose detail carries ONLY org_id (the cleared set is unbounded)' do
      run('clear')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'membership.entitlement.clear', detail: { org_id: 'on_org_ext' })
      )
    end

    it 'ignores an entitlement argument rather than treating it as a filter' do
      result = run('clear', entitlement: 'custom_branding')

      expect(result.entitlement).to be_nil
      expect(result.grants).to eq([])
      expect(result.revokes).to eq([])
    end
  end

  # D15. The asymmetry is the decision, not an oversight — assert BOTH halves so
  # a later "tidy-up" into symmetry fails here first.
  describe 'no-change semantics (D15)' do
    it 'returns :no_change for a grant that is already granted — no mutation, no audit' do
      grant_members << 'custom_branding'
      reconcile!

      result = run('grant', entitlement: 'custom_branding')

      expect(result.status).to eq(:no_change)
      expect(membership).not_to have_received(:grant_entitlement)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      expect(result.grants).to eq(['custom_branding'])
    end

    it 'returns :no_change for a revoke that is already revoked — no mutation, no audit' do
      revoke_members << 'api_access'
      reconcile!

      result = run('revoke', entitlement: 'api_access')

      expect(result.status).to eq(:no_change)
      expect(membership).not_to have_received(:revoke_entitlement)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'still APPLIES a grant when the name also sits in revokes (not a no-change)' do
      grant_members << 'api_access'
      revoke_members << 'api_access'

      result = run('grant', entitlement: 'api_access')

      expect(result.status).to eq(:granted)
      expect(membership).to have_received(:grant_entitlement).with('api_access')
    end

    it 'ALWAYS applies and ALWAYS audits clear, even with no overrides present' do
      result = run('clear')

      expect(result.status).to eq(:cleared)
      expect(membership).to have_received(:clear_entitlement_overrides).once
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'membership.entitlement.clear')
      )
    end
  end

  describe 'dry run' do
    it 'defaults to dry_run: true' do
      result = described_class.new(
        org: org, customer: customer, action: 'grant', actor: actor, entitlement: 'custom_branding'
      ).call

      expect(result.dry_run).to be(true)
      expect(result.status).to eq(:planned)
    end

    %w[grant revoke].each do |action|
      it "previews #{action} without mutating or auditing" do
        result = run(action, entitlement: 'custom_branding', dry_run: true)

        expect(result.status).to eq(:planned)
        expect(membership).not_to have_received(:"#{action}_entitlement")
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    it 'previews clear without mutating or auditing' do
      grant_members << 'custom_branding'
      reconcile!

      result = run('clear', dry_run: true)

      expect(result.status).to eq(:planned)
      expect(membership).not_to have_received(:clear_entitlement_overrides)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      expect(result.grants).to eq([])
      expect(result.revokes).to eq([])
      expect(result.effective).to contain_exactly('create_secrets', 'api_access')
    end

    it 'projects the effective set the way apply_entitlements would compute it' do
      revoke_members << 'api_access'
      reconcile!

      result = run('grant', entitlement: 'custom_branding', dry_run: true)

      expect(result.grants).to contain_exactly('custom_branding')
      expect(result.revokes).to contain_exactly('api_access')
      expect(result.effective).to eq(%w[create_secrets custom_branding])
    end
  end

  # A refusal is an ATTEMPTED privileged mutation, so it lands in the trail with
  # the same verb/target as a success — differing only in result:/detail.
  describe 'input refusals (statuses, never raises)' do
    it 'returns :invalid_action and records ONE result: :failure event' do
      result = run('promote', entitlement: 'custom_branding')

      expect(result.status).to eq(:invalid_action)
      expect(membership).not_to have_received(:grant_entitlement)
      # An unknown action has NO success-path verb to match, so the event lands
      # on the bare prefix rather than interpolating operator input into `verb`.
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.entitlement',
        target: 'ur_member',
        result: :failure,
        detail: {
          reason: 'invalid_action', org_id: 'on_org_ext', action: 'promote',
          entitlement: 'custom_branding', dry_run: false
        },
      )
    end

    it 'returns :missing_entitlement and records ONE result: :failure event' do
      result = run('grant', entitlement: '   ')

      expect(result.status).to eq(:missing_entitlement)
      expect(membership).not_to have_received(:grant_entitlement)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.entitlement.grant',
        target: 'ur_member',
        result: :failure,
        detail: {
          reason: 'missing_entitlement', org_id: 'on_org_ext', action: 'grant',
          entitlement: '', dry_run: false
        },
      )
    end

    # The Onetime::AuditedFailure mechanism. apply! runs BEFORE the success-path
    # record call, so a raise there leaves the member's effective permissions
    # unknown with no trail unless the macro fires. Message expectation, not a
    # store read: ColonelAuditEvent.record swallows its own errors.
    it 'records ONE result: :failure event when apply! raises, and re-raises' do
      allow(membership).to receive(:grant_entitlement).and_raise(Onetime::Problem, 'redis down')

      expect do
        run('grant', entitlement: 'custom_branding')
      end.to raise_error(Onetime::Problem, /redis down/)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'membership.entitlement.grant',
          target: 'ur_member', # literal: a broken target lambda silently lands as 'unknown'
          result: :failure,
          detail: hash_including(
            error: 'Onetime::Problem', message: 'redis down',
            dry_run: false, org_id: 'on_org_ext', action: 'grant',
          ),
        ),
      )
    end

    it 'returns :missing_entitlement for a revoke with no entitlement at all' do
      expect(run('revoke').status).to eq(:missing_entitlement)
    end

    it 'does NOT require an entitlement for clear' do
      expect(run('clear').status).to eq(:cleared)
    end
  end

  # Membership-specific: org + customer both resolve, but no active membership
  # joins them. Only the op can see this — both adapters map it to a failure.
  describe 'membership resolution (:not_found)' do
    it 'returns :not_found (no mutation) and records ONE failure event when no membership exists' do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-1').and_return(nil)

      result = run('grant', entitlement: 'custom_branding')

      expect(result.status).to eq(:not_found)
      expect(result.org_id).to eq('on_org_ext')
      expect(result.member_id).to eq('ur_member')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.entitlement.grant',
        target: 'ur_member',
        result: :failure,
        detail: {
          reason: 'not_found', org_id: 'on_org_ext', action: 'grant',
          entitlement: 'custom_branding', dry_run: false
        },
      )
    end

    it 'returns :not_found when the membership exists but is not active' do
      allow(membership).to receive(:active?).and_return(false)

      result = run('clear')

      expect(result.status).to eq(:not_found)
      expect(membership).not_to have_received(:clear_entitlement_overrides)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'membership.entitlement.clear',
          target: 'ur_member',
          result: :failure,
          detail: hash_including(reason: 'not_found'),
        ),
      )
    end

    it 'classifies :not_found as a failure, not an OK status' do
      expect(described_class::OK_STATUSES).not_to include(:not_found)
    end
  end

  # Membership scope inverts the org-level dead-letter story (the membership
  # read path has no billing short-circuit) — but the flag still surfaces so
  # adapters can explain the standalone baseline.
  describe 'standalone install (billing disabled)' do
    let(:billing_enabled) { false }

    it 'still applies and still audits, flagging standalone: true' do
      result = run('grant', entitlement: 'custom_branding')

      expect(result.standalone).to be(true)
      expect(result.status).to eq(:granted)
      expect(membership).to have_received(:grant_entitlement).with('custom_branding')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
    end

    it 'reports standalone: false when billing is enabled' do
      allow(org).to receive(:billing_enabled?).and_return(true)

      expect(run('grant', entitlement: 'custom_branding').standalone).to be(false)
    end
  end

  describe '.known_entitlement?' do
    it 'delegates to the org op (one catalog, one predicate)' do
      allow(Onetime::Operations::Org::EntitlementOverride)
        .to receive(:known_entitlement?).with('custom_domains').and_return(false)

      expect(described_class.known_entitlement?('custom_domains')).to be(false)
      expect(Onetime::Operations::Org::EntitlementOverride)
        .to have_received(:known_entitlement?).with('custom_domains')
    end

    it 'does not gate #call — an unknown entitlement is granted anyway' do
      stub_const('Billing::Config', double('Billing::Config'))
      allow(Billing::Config).to receive(:load_entitlements).and_return({})

      result = run('grant', entitlement: 'future_feature_xyz')

      expect(described_class.known_entitlement?('future_feature_xyz')).to be(false)
      expect(result.status).to eq(:granted)
      expect(membership).to have_received(:grant_entitlement).with('future_feature_xyz')
    end
  end

  describe 'contract constants' do
    it 'emits membership-scoped audit verbs, sibling of the org prefix' do
      expect(described_class::AUDIT_VERB_PREFIX).to eq('membership.entitlement')
      expect(described_class::ACTIONS).to eq(%w[grant revoke clear])
    end

    it 'shares the adapter-facing status/action maps with the org op' do
      expect(described_class::OK_STATUSES)
        .to contain_exactly(:granted, :revoked, :cleared, :no_change, :planned)
      expect(described_class::ACTION_PAST_TENSE)
        .to eq('grant' => 'granted', 'revoke' => 'revoked', 'clear' => 'cleared')
    end
  end

  # --- Real materialization: proves grant/revoke flip can? on the membership ---
  describe 'entitlement materialization (real membership)' do
    let(:org_objid) { 'org-entoverride-mat-1' }

    let(:org_side) do
      instance_double(
        Onetime::Organization,
        objid: org_objid,
        extid: 'on_mat_ext',
        billing_enabled?: true,
      )
    end

    let(:real_membership) do
      m = Onetime::OrganizationMembership.new
      m.organization_objid = org_objid
      m.customer_objid = 'cust-obj-mat'
      m.role = 'member'
      m.status = 'active'
      # Seed a materialized baseline the way materialize_for_role! would.
      # Scalars save BEFORE collection writes (the model's own ordering).
      m.materialized_entitlements_at = "#{Familia.now.to_i}:seed"
      m.save
      m.entitlements_plan.add('create_secrets')
      m.entitlements_plan.add('api_access')
      m.apply_entitlements
      m
    end

    let(:real_customer) do
      double('Customer', objid: 'cust-obj-mat', extid: 'ur_mat_member')
    end

    before do
      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer).with(org_objid, 'cust-obj-mat').and_return(real_membership)
    end

    def run_real(action, entitlement:)
      described_class.new(
        org: org_side, customer: real_customer, action: action, actor: actor,
        entitlement: entitlement, dry_run: false
      ).call
    end

    it 'flips can?(custom_branding) false -> true on grant, back on revoke' do
      expect(real_membership.can?('custom_branding')).to be false

      expect(run_real('grant', entitlement: 'custom_branding').status).to eq(:granted)
      expect(real_membership.can?('custom_branding')).to be true

      expect(run_real('revoke', entitlement: 'custom_branding').status).to eq(:revoked)
      expect(real_membership.can?('custom_branding')).to be false
    end

    it 'flips can?(api_access) true -> false on revoke of a baseline entitlement' do
      expect(real_membership.can?('api_access')).to be true

      expect(run_real('revoke', entitlement: 'api_access').status).to eq(:revoked)
      expect(real_membership.can?('api_access')).to be false
    end

    it 'restores the baseline on clear' do
      run_real('revoke', entitlement: 'api_access')
      run_real('grant', entitlement: 'custom_branding')

      result = described_class.new(
        org: org_side, customer: real_customer, action: 'clear', actor: actor, dry_run: false
      ).call

      expect(result.status).to eq(:cleared)
      expect(real_membership.can?('api_access')).to be true
      expect(real_membership.can?('custom_branding')).to be false
    end
  end
end
