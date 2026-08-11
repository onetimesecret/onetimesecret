# spec/unit/onetime/operations/org/entitlement_override_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::EntitlementOverride (#3731).
#
# Mocked contract, no datastore: action validation, the DELIBERATELY asymmetric
# no-change rule (grant/revoke short-circuit, clear never does — D15), the
# dry-run projection, the exactly-once audit event with the byte-identical verb,
# the standalone dead-letter advisory (D17: warn, never refuse), and the
# warn-don't-block stance on unknown entitlement names.
#
# The org double reproduces the MODEL's override semantics (grant removes from
# revokes and vice versa; every mutation recomputes plan ∪ grants − revokes) so
# the op is tested against the contract it actually depends on. The model
# methods themselves — and their real MULTI/EXEC — are covered end-to-end by
# try/integration/api/colonel/manage_entitlement_override_try.rb.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/entitlement_override_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/org/entitlement_override'

RSpec.describe Onetime::Operations::Org::EntitlementOverride do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  # Mutable backing arrays — the org double reads these live, so an applied
  # mutation is observable in the Result the op builds afterwards.
  let(:plan_members)         { %w[create_secrets api_access] }
  let(:grant_members)        { [] }
  let(:revoke_members)       { [] }
  let(:materialized_members) { (plan_members | grant_members) - revoke_members }
  let(:billing_enabled)      { true }

  # Mirror of the model's apply_entitlements reconciliation.
  def reconcile!
    materialized_members.replace((plan_members | grant_members) - revoke_members)
  end

  let(:org) do
    instance = double('Organization', extid: 'on_org_ext', billing_enabled?: billing_enabled)

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
  end

  def run(action, entitlement: nil, dry_run: false)
    described_class.new(
      org: org, action: action, actor: actor, entitlement: entitlement, dry_run: dry_run
    ).call
  end

  describe 'grant' do
    it 'applies via the model and reports the post-mutation sets' do
      result = run('grant', entitlement: 'custom_branding')

      expect(result.status).to eq(:granted)
      expect(result.action).to eq('grant')
      expect(result.entitlement).to eq('custom_branding')
      expect(result.org_id).to eq('on_org_ext')
      expect(result.dry_run).to be(false)
      expect(org).to have_received(:grant_entitlement).with('custom_branding').once
      expect(result.grants).to eq(['custom_branding'])
      expect(result.revokes).to eq([])
      expect(result.effective).to contain_exactly('create_secrets', 'api_access', 'custom_branding')
    end

    it 'records EXACTLY ONE audit event, fully specified' do
      run('grant', entitlement: 'custom_branding')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'organization.entitlement.grant',
        target: 'on_org_ext',
        result: :success,
        detail: { entitlement: 'custom_branding' },
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
        org: org, action: ' GRANT ', actor: actor, entitlement: '  custom_branding  ', dry_run: false
      ).call

      expect(result.status).to eq(:granted)
      expect(org).to have_received(:grant_entitlement).with('custom_branding')
    end
  end

  describe 'revoke' do
    it 'applies via the model and drops the entitlement from effective' do
      result = run('revoke', entitlement: 'api_access')

      expect(result.status).to eq(:revoked)
      expect(org).to have_received(:revoke_entitlement).with('api_access').once
      expect(result.revokes).to eq(['api_access'])
      expect(result.effective).to eq(['create_secrets'])
    end

    it 'records EXACTLY ONE audit event with the revoke verb' do
      run('revoke', entitlement: 'api_access')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'organization.entitlement.revoke',
          target: 'on_org_ext',
          detail: { entitlement: 'api_access' },
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

    it 'wipes both override sets and returns the plan baseline' do
      result = run('clear')

      expect(result.status).to eq(:cleared)
      expect(result.entitlement).to be_nil
      expect(org).to have_received(:clear_entitlement_overrides).once
      expect(result.grants).to eq([])
      expect(result.revokes).to eq([])
      expect(result.effective).to contain_exactly('create_secrets', 'api_access')
    end

    it 'records an audit event with an EMPTY detail (the cleared set is unbounded)' do
      run('clear')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'organization.entitlement.clear', detail: {})
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
      expect(org).not_to have_received(:grant_entitlement)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      expect(result.grants).to eq(['custom_branding'])
    end

    it 'returns :no_change for a revoke that is already revoked — no mutation, no audit' do
      revoke_members << 'api_access'
      reconcile!

      result = run('revoke', entitlement: 'api_access')

      expect(result.status).to eq(:no_change)
      expect(org).not_to have_received(:revoke_entitlement)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'still APPLIES a grant when the name also sits in revokes (not a no-change)' do
      grant_members << 'api_access'
      revoke_members << 'api_access'

      result = run('grant', entitlement: 'api_access')

      expect(result.status).to eq(:granted)
      expect(org).to have_received(:grant_entitlement).with('api_access')
    end

    it 'ALWAYS applies and ALWAYS audits clear, even with no overrides present' do
      result = run('clear')

      expect(result.status).to eq(:cleared)
      expect(org).to have_received(:clear_entitlement_overrides).once
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'organization.entitlement.clear')
      )
    end
  end

  describe 'dry run' do
    it 'defaults to dry_run: true' do
      result = described_class.new(
        org: org, action: 'grant', actor: actor, entitlement: 'custom_branding'
      ).call

      expect(result.dry_run).to be(true)
      expect(result.status).to eq(:planned)
    end

    %w[grant revoke].each do |action|
      it "previews #{action} without mutating or auditing" do
        result = run(action, entitlement: 'custom_branding', dry_run: true)

        expect(result.status).to eq(:planned)
        expect(org).not_to have_received(:"#{action}_entitlement")
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    it 'previews clear without mutating or auditing' do
      grant_members << 'custom_branding'
      reconcile!

      result = run('clear', dry_run: true)

      expect(result.status).to eq(:planned)
      expect(org).not_to have_received(:clear_entitlement_overrides)
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
      expect(org).not_to have_received(:grant_entitlement)
      # An unknown action has NO success-path verb to match, so the event lands
      # on the bare prefix rather than interpolating operator input into `verb`.
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'organization.entitlement',
        target: 'on_org_ext',
        result: :failure,
        detail: {
          reason: 'invalid_action', action: 'promote',
          entitlement: 'custom_branding', dry_run: false
        },
      )
    end

    it 'returns :missing_entitlement and records ONE result: :failure event' do
      result = run('grant', entitlement: '   ')

      expect(result.status).to eq(:missing_entitlement)
      expect(org).not_to have_received(:grant_entitlement)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'organization.entitlement.grant',
        target: 'on_org_ext',
        result: :failure,
        detail: {
          reason: 'missing_entitlement', action: 'grant',
          entitlement: '', dry_run: false
        },
      )
    end

    it 'returns :missing_entitlement for a revoke with no entitlement at all' do
      expect(run('revoke').status).to eq(:missing_entitlement)
    end

    it 'does NOT require an entitlement for clear' do
      expect(run('clear').status).to eq(:cleared)
    end

    # The Onetime::AuditedFailure mechanism. apply! runs BEFORE the success-path
    # record call, so a raise there leaves the org's effective permissions
    # unknown with no trail unless the macro fires. Message expectation, not a
    # store read: ColonelAuditEvent.record swallows its own errors.
    it 'records ONE result: :failure event when apply! raises, and re-raises' do
      allow(org).to receive(:grant_entitlement).and_raise(Onetime::Problem, 'redis down')

      expect do
        run('grant', entitlement: 'custom_branding')
      end.to raise_error(Onetime::Problem, /redis down/)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'organization.entitlement.grant',
          target: 'on_org_ext', # literal: a broken target lambda silently lands as 'unknown'
          result: :failure,
          detail: hash_including(
            error: 'Onetime::Problem', message: 'redis down',
            dry_run: false, action: 'grant',
          ),
        ),
      )
    end
  end

  # D17: the write is a dead letter on a billing-disabled install, but refusing
  # would break pre-seeding an install that enables billing later.
  describe 'standalone install (billing disabled)' do
    let(:billing_enabled) { false }

    it 'still applies and still audits, flagging standalone: true' do
      result = run('grant', entitlement: 'custom_branding')

      expect(result.standalone).to be(true)
      expect(result.status).to eq(:granted)
      expect(org).to have_received(:grant_entitlement).with('custom_branding')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
    end

    it 'reports standalone: false when billing is enabled' do
      allow(org).to receive(:billing_enabled?).and_return(true)

      expect(run('grant', entitlement: 'custom_branding').standalone).to be(false)
    end
  end

  # The endpoint documented warn-don't-block explicitly; the op keeps the
  # predicate available for adapters but never consults it in #call.
  describe '.known_entitlement?' do
    it 'reports false for a name absent from the catalog' do
      stub_const('Billing::Config', double('Billing::Config'))
      allow(Billing::Config).to receive(:load_entitlements).and_return({ 'custom_domains' => {} })

      expect(described_class.known_entitlement?('future_feature_xyz')).to be(false)
      expect(described_class.known_entitlement?('custom_domains')).to be(true)
    end

    it 'fails OPEN when the catalog cannot be read (never a spurious warning)' do
      stub_const('Billing::Config', double('Billing::Config'))
      allow(Billing::Config).to receive(:load_entitlements).and_raise(StandardError, 'no config')

      expect(described_class.known_entitlement?('anything')).to be(true)
    end

    it 'does not gate #call — an unknown entitlement is granted anyway' do
      stub_const('Billing::Config', double('Billing::Config'))
      allow(Billing::Config).to receive(:load_entitlements).and_return({})

      result = run('grant', entitlement: 'future_feature_xyz')

      expect(described_class.known_entitlement?('future_feature_xyz')).to be(false)
      expect(result.status).to eq(:granted)
      expect(org).to have_received(:grant_entitlement).with('future_feature_xyz')
    end
  end

  describe 'contract constants' do
    it 'emits the byte-identical audit verbs the pre-extraction colonel used' do
      expect(described_class::AUDIT_VERB_PREFIX).to eq('organization.entitlement')
      expect(described_class::ACTIONS).to eq(%w[grant revoke clear])
    end

    it 'classifies the statuses an adapter should treat as success' do
      expect(described_class::OK_STATUSES)
        .to contain_exactly(:granted, :revoked, :cleared, :no_change, :planned)
    end

    it 'keeps the past-tense map the HTTP response renders' do
      expect(described_class::ACTION_PAST_TENSE)
        .to eq('grant' => 'granted', 'revoke' => 'revoked', 'clear' => 'cleared')
    end
  end
end
