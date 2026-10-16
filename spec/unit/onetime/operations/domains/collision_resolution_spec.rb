# spec/unit/onetime/operations/domains/collision_resolution_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Domains::CollisionResolution: the rule that picks the
# record to keep in a collision group, the plan file, and the apply that
# removes the others.
#
# The rule and the plan file are pure and tested without the datastore. The
# facts (#plan) and the removals (#apply) run against the real datastore with
# legacy records (written raw, as pre-ascii-index records sit) that share
# one name; every name carries a random suffix so the audit's other rows do
# not matter. Audit events are stubbed: Remove and AdminVerifyDomain own them.
#
# Run: tests/lanes/run --only spec/unit/onetime/operations/domains/collision_resolution_spec.rb

require 'spec_helper'
require 'securerandom'
require 'onetime/operations/domains/collision_resolution'

RSpec.describe Onetime::Operations::Domains::CollisionResolution do
  let(:op_class) { described_class }

  def record(id, **over)
    defaults = {
      domain_id: id,
      extid: "cd#{id}",
      display_domain: 'pair.example',
      org_id: "org-#{id}",
      org_extid: nil,
      org_name: nil,
      org_state: :active,
      served: false,
      verification_state: :pending,
      ownership_verified: false,
      verified_by_override: false,
      verified_confirmed_at: nil,
      receipts: 0,
      configs: [],
      all_configs: [],
      brand: false,
      vhost: false,
      created: 1_700_000_000,
    }
    op_class::Record.new(**defaults, **over)
  end

  describe 'Rule.decide' do
    let(:rule) { op_class::Rule }

    it 'removes orphans and keeps the one owned record' do
      decision = rule.decide([record('a', org_state: :missing), record('b')])

      expect(decision.decision).to eq(:auto)
      expect(decision.rule).to eq(:only_owned)
      expect(decision.keep).to eq('b')
      expect(decision.remove).to eq(['a'])
      expect(decision.notes).to include('cda has no organization; it is removed')
    end

    it 'removes a group of orphans outright' do
      decision = rule.decide([record('a', org_state: :missing), record('b', org_state: :missing)])

      expect(decision.rule).to eq(:all_orphans)
      expect(decision.keep).to be_nil
      expect(decision.remove).to contain_exactly('a', 'b')
    end

    it 'keeps the one record with DNS proof over a used, served, verified one' do
      used     = record('a', served: true, ownership_verified: true, receipts: 5, brand: true)
      decision = rule.decide([used, record('b', verified_confirmed_at: 1_700_000_100)])

      expect(decision.rule).to eq(:dns_proof)
      expect(decision.keep).to eq('b')
      expect(decision.remove).to eq(['a'])
      expect(decision.notes).to include(
        'cda answers for the name today; after the removal cdb does',
        'cda has 5 receipts; the receipts keep their share_domain',
        'cda has brand settings; they are deleted with the record',
      )
    end

    it 'sends several DNS proofs to the operator' do
      decision = rule.decide([record('a', verified_confirmed_at: 1), record('b', verified_confirmed_at: 2)])

      expect(decision.decision).to eq(:manual)
      expect(decision.rule).to eq(:manual_several_dns_proofs)
      expect(decision.keep).to be_nil
      expect(decision.remove).to be_empty
    end

    it 'keeps the one record with ownership verified' do
      decision = rule.decide([record('a', served: true), record('b', ownership_verified: true, verified_by_override: true)])

      expect(decision.rule).to eq(:ownership_verified)
      expect(decision.keep).to eq('b')
    end

    it 'keeps the one record in use when none is verified' do
      decision = rule.decide([record('a', served: true), record('b', configs: ['sso'])])

      expect(decision.rule).to eq(:in_use)
      expect(decision.keep).to eq('b')
      expect(decision.notes).to include('cda answers for the name today; after the removal cdb does')
    end

    it 'does not count the materializable configs as use' do
      decision = rule.decide([record('a', served: true, all_configs: %w[signin homepage]), record('b', all_configs: ['api'])])

      expect(decision.rule).to eq(:served_tiebreak)
      expect(decision.keep).to eq('a')
    end

    it 'sends several records in use to the operator' do
      decision = rule.decide([record('a', receipts: 1), record('b', brand: true)])

      expect(decision.rule).to eq(:manual_several_in_use)
      expect(decision.decision).to eq(:manual)
    end

    it 'keeps the oldest when nothing distinguishes the records' do
      decision = rule.decide([record('a', created: 200), record('b', created: 100)])

      expect(decision.rule).to eq(:oldest_tiebreak)
      expect(decision.keep).to eq('b')
    end

    it 'notes a kept record in an archived organization' do
      decision = rule.decide([record('a', org_state: :archived, ownership_verified: true), record('b')])

      expect(decision.notes).to include('kept record cda belongs to an archived organization')
    end
  end

  describe 'Plan' do
    let(:plan_class) { op_class::Plan }
    let(:plan) do
      plan_class.new(
        generated_at: '2026-10-16T00:00:00Z',
        rule_version: op_class::Rule::VERSION,
        strategy: 'passthrough',
        groups: [
          op_class::Group.new(
            ascii_name: 'pair.example',
            decision: :auto,
            rule: :dns_proof,
            keep: 'cdb',
            remove: ['cda'],
            notes: ['n'],
            records: [record('a'), record('b', verified_confirmed_at: 5)],
            approved: false,
            skip: false,
          ),
          op_class::Group.new(
            ascii_name: 'two.example',
            decision: :manual,
            rule: :manual_several_in_use,
            keep: nil,
            remove: [],
            notes: [],
            records: [record('c', display_domain: 'two.example'), record('d', display_domain: 'two.example')],
            approved: false,
            skip: false,
          ),
        ],
      )
    end

    it 'round-trips through JSON' do
      parsed = plan_class.parse(plan.to_json)

      expect(parsed.groups.map(&:ascii_name)).to eq(['pair.example', 'two.example'])
      expect(parsed.group('pair.example').keep).to eq('cdb')
      expect(parsed.group('pair.example').records.map(&:domain_id)).to eq(%w[a b])
      expect(parsed.group('pair.example').records.last.verified_confirmed_at).to eq(5)
      expect(parsed.group('two.example')).to be_manual
      expect(parsed.strategy).to eq('passthrough')
      expect(parsed.counts).to include(groups: 2, auto: 1, manual: 1, records: 4, removals: 1)
    end

    it 'needs an operator while a manual group is undecided, not once approved or skipped' do
      expect(plan).to be_attention

      edited                          = JSON.parse(plan.to_json)
      edited['groups'][1]['keep']     = 'cdc'
      edited['groups'][1]['approved'] = true
      expect(plan_class.from_h(edited)).not_to be_attention

      edited['groups'][1]['approved'] = false
      edited['groups'][1]['skip']     = true
      expect(plan_class.from_h(edited)).not_to be_attention
    end

    it 'refuses another rule version, malformed JSON, and a repeated group' do
      expect { plan_class.from_h(JSON.parse(plan.to_json).merge('rule_version' => 99)) }
        .to raise_error(op_class::InvalidPlan, /rule_version/)
      expect { plan_class.parse('{') }.to raise_error(op_class::InvalidPlan, /valid JSON/)

      doubled = JSON.parse(plan.to_json)
      doubled['groups'] << doubled['groups'].first
      expect { plan_class.from_h(doubled) }.to raise_error(op_class::InvalidPlan, /more than once/)
    end
  end

  describe 'against the datastore', :datastore do
    include LegacyCustomDomainRecords

    let(:model) { Onetime::CustomDomain }
    let(:sfx) { SecureRandom.hex(4) }
    let(:name) { "coll-#{sfx}.example" }
    let(:org_a) { Onetime::Organization.new(display_name: "Collision A #{sfx}").tap(&:save) }
    let(:org_b) { Onetime::Organization.new(display_name: "Collision B #{sfx}").tap(&:save) }
    let(:legacy) { {} }
    # Written first, so the second write of the exact index entry (B) wins
    # and A is the shadow.
    let!(:id_a) { legacy!(:a, org: org_a, fields: { 'ownership_verified' => true }) }
    let!(:id_b) { legacy!(:b, org: org_b) }

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    end

    after do
      legacy.each_value { |(id, stored)| remove_legacy_custom_domain(id, stored) }
      [org_a, org_b].each do |org|
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[collision_resolution_spec cleanup] #{ex.class}: #{ex.message}"
      end
    end

    def legacy!(label, org:, fields: {})
      legacy[label] = [write_legacy_custom_domain(name, org_id: org&.objid, fields: fields), name]
      legacy[label].first
    end

    def group_of(plan)
      plan.group(name) || raise("no group for #{name} in #{plan.groups.map(&:ascii_name)}")
    end

    it 'plans the group from the records\' facts' do
      group = group_of(op_class.new.plan)

      expect(group.decision).to eq(:auto)
      expect(group.rule).to eq(:ownership_verified)
      a = group.records.find { |r| r.domain_id == id_a }
      b = group.records.find { |r| r.domain_id == id_b }
      expect(group.keep).to eq(a.ref)
      expect(group.remove).to eq([b.ref])
      expect(a.served).to be false
      expect(b.served).to be true
      expect(a.ownership_verified).to be true
      expect(a.org_state).to eq(:active)
      expect(a.org_extid).to eq(org_a.extid)
      expect(b.receipts).to eq(0)
      expect(b.configs).to eq([])
      expect(b.brand).to be false
      expect(group.notes).to include("#{b.ref} answers for the name today; after the removal #{a.ref} does")
    end

    it 'marks a record whose organization is gone as an orphan' do
      legacy!(:c, org: nil)

      group = group_of(op_class.new.plan)
      c     = group.records.find { |r| r.domain_id == legacy[:c].first }

      expect(c.org_state).to eq(:missing)
      expect(group.remove).to include(c.ref)
      expect(group.keep).to eq(group.records.find { |r| r.domain_id == id_a }.ref)
    end

    describe '#apply' do
      let(:plan) { op_class.new.plan }

      it 'previews on a dry run and removes nothing' do
        result  = op_class.new.apply(plan, actor: 'cli', dry_run: true)
        outcome = result.outcomes.find { |o| o.ascii_name == name }

        expect(result.dry_run).to be true
        expect(outcome.status).to eq(:dry_run)
        expect(outcome.removals.map(&:status)).to eq([:planned])
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
      end

      it 'removes the other record and makes the name resolve to the kept one' do
        result  = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name)
        outcome = result.outcomes.find { |o| o.ascii_name == name }

        expect(result.outcomes.size).to eq(1)
        expect(outcome.status).to eq(:applied)
        expect(outcome.removals.map { |r| [r.ref, r.status] }).to eq([[plan.group(name).remove.first, :removed]])
        expect(outcome.index_claim).to eq(:created)
        expect(outcome.verify_state).to be_nil # passthrough: no provider vhost
        expect(outcome.errors).to be_empty
        expect(model.find_by_identifier(id_b)).to be_nil
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_a)
        expect(result).not_to be_attention
      end

      it 'keeps the vhost for the kept record and deletes it only when no record is kept' do
        orphan_name = "orph-#{sfx}.example"
        legacy[:o1] = [write_legacy_custom_domain(orphan_name, org_id: nil), orphan_name]
        legacy[:o2] = [write_legacy_custom_domain(orphan_name, org_id: nil), orphan_name]
        allow(Onetime::Operations::Domains::Teardown).to receive(:new).and_call_original

        both = op_class.new.plan
        op_class.new.apply(both, actor: 'cli', dry_run: false, only: name)
        op_class.new.apply(both, actor: 'cli', dry_run: false, only: orphan_name)

        expect(Onetime::Operations::Domains::Teardown).to have_received(:new).with(hash_including(keep_vhost: true)).once
        expect(Onetime::Operations::Domains::Teardown).to have_received(:new).with(hash_including(keep_vhost: false)).twice
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(legacy.values_at(:o1, :o2).map { |(id, _)| model.find_by_identifier(id) }).to eq([nil, nil])
      end

      it 'skips a group whose records changed since the plan' do
        plan # made before the change
        legacy!(:late, org: org_b)

        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:skipped)
        expect(outcome.reason).to include('changed since the plan')
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      it 'skips an undecided manual group, a skipped group, and an inconsistent edit' do
        edited = JSON.parse(plan.to_json)
        group  = edited['groups'].find { |g| g['ascii_name'] == name }

        group['decision'] = 'manual'
        group['keep']     = nil
        group['remove']   = []
        manual            = op_class::Plan.from_h(edited)
        expect(op_class.new.apply(manual, actor: 'cli', dry_run: false, only: name).outcomes.first)
          .to have_attributes(status: :skipped, reason: /manual group/)

        group['keep']     = group['records'].first['extid']
        group['approved'] = true
        group['remove']   = [group['keep']]
        expect(op_class.new.apply(op_class::Plan.from_h(edited), actor: 'cli', dry_run: false, only: name).outcomes.first)
          .to have_attributes(status: :skipped, reason: /remove does not match keep/)

        group['remove']   = []
        group['skip']     = true
        expect(op_class.new.apply(op_class::Plan.from_h(edited), actor: 'cli', dry_run: false, only: name).outcomes.first)
          .to have_attributes(status: :skipped, reason: 'skipped in the plan')

        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      it 'applies an approved manual group with the operator\'s keep' do
        edited            = JSON.parse(plan.to_json)
        group             = edited['groups'].find { |g| g['ascii_name'] == name }
        b_ref             = group['records'].find { |r| r['domain_id'] == id_b }['extid']
        group['decision'] = 'manual'
        group['keep']     = b_ref
        group['remove']   = []
        group['approved'] = true

        outcome = op_class.new.apply(op_class::Plan.from_h(edited), actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:applied)
        expect(outcome.keep).to eq(b_ref)
        expect(model.find_by_identifier(id_a)).to be_nil
        expect(model.find_by_identifier(id_b)).not_to be_nil
        # B already answered for the name: the shadow's removal re-asserted it.
        expect(outcome.index_claim).to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
      end
    end
  end
end
