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
# not matter. Audit writes are spied on for the summary and per-removal trail.
#
# Run: tests/lanes/run --only spec/unit/onetime/operations/domains/collision_resolution_spec.rb

require 'spec_helper'
require 'securerandom'
require 'stripe'
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

  def collision_group(**over)
    op_class::Group.new(
      ascii_name: 'pair.example',
      decision: :auto,
      rule: :ownership_verified,
      keep: 'cda',
      remove: ['cdb'],
      notes: [],
      records: [record('a', ownership_verified: true), record('b')],
      approved: false,
      skip: false,
      **over,
    )
  end

  describe 'Record billing evidence' do
    {
      live_or_recoverable: %w[active trialing past_due unpaid],
      not_live: %w[canceled incomplete incomplete_expired paused],
      unknown: %w[future_status],
    }.each do |label, statuses|
      statuses.each do |status|
        it "labels #{status.inspect} as #{label}, even without Stripe identifiers" do
          snapshot = record('a', subscription_status: status)

          expect(snapshot.billing_label.to_s).to eq(label.to_s)
          expect(snapshot.billing_protected?).to eq([:live_or_recoverable, :unknown].include?(label))
        end

        it "labels #{status.inspect} as #{label} with Stripe identifiers" do
          snapshot = record('a', subscription_status: status, stripe_customer_id: 'cus_a', stripe_subscription_id: 'sub_a')

          expect(snapshot.billing_label.to_s).to eq(label.to_s)
          expect(snapshot.billing_protected?).to eq([:live_or_recoverable, :unknown].include?(label))
        end
      end
    end

    [nil, '', '  '].each do |status|
      it "labels blank status #{status.inspect} without Stripe references as no local subscription" do
        snapshot = record('a', planid: 'paid_plan', subscription_status: status)

        expect(snapshot.billing_label.to_s).to eq('no_local_subscription')
        expect(snapshot).not_to be_billing_protected
      end

      [:stripe_customer_id, :stripe_subscription_id].each do |field|
        it "protects blank status #{status.inspect} when #{field} is present" do
          snapshot = record('a', subscription_status: status, **{ field => 'stripe_ref' })

          expect(snapshot.billing_label.to_s).to eq('unknown')
          expect(snapshot).to be_billing_protected
        end
      end
    end

    it 'defaults all four optional billing fields to nil' do
      snapshot = record('a')

      expect([snapshot.planid, snapshot.stripe_customer_id, snapshot.stripe_subscription_id, snapshot.subscription_status]).to eq([nil] * 4)
      expect(snapshot.billing_fingerprint).to eq([''] * 4)
    end

    it 'treats whitespace-only Stripe references as blank' do
      snapshot = record('a', stripe_customer_id: '  ', stripe_subscription_id: "\t", subscription_status: '')

      expect(snapshot.billing_label.to_s).to eq('no_local_subscription')
      expect(snapshot).not_to be_billing_protected
    end

    it 'normalizes the billing fingerprint to strings in field order' do
      snapshot = record('a', planid: 123, stripe_customer_id: 'cus_a', stripe_subscription_id: 'sub_a', subscription_status: :active)

      expect(snapshot.billing_fingerprint).to eq(%w[123 cus_a sub_a active])
    end

    it 'round-trips complete billing snapshots with string and symbol keys' do
      snapshot = record('a', planid: 'identity_plus', stripe_customer_id: 'cus_a', stripe_subscription_id: 'sub_a', subscription_status: 'past_due')

      [snapshot.to_h, JSON.parse(JSON.generate(snapshot.to_h))].each do |hash|
        parsed = op_class::Record.from_h(hash)
        expect(parsed.billing_fingerprint).to eq(snapshot.billing_fingerprint)
        expect(parsed.to_h).to eq(snapshot.to_h)
      end
      expect(op_class::Record.from_h(record('b').to_h).billing_fingerprint).to eq([''] * 4)
    end

    [:planid, :stripe_customer_id, :stripe_subscription_id, :subscription_status].each do |field|
      it "refuses a saved record missing #{field}, rather than treating it as nil" do
        hash = JSON.parse(JSON.generate(record('a').to_h))
        hash.delete(field.to_s)

        expect { op_class::Record.from_h(hash) }.to raise_error(op_class::InvalidPlan)
      end
    end
  end

  describe 'Group approval' do
    it 'requires approval for protected removals without changing the automatic proposal' do
      group = collision_group(records: [record('a'), record('b', subscription_status: 'active')])

      expect(group.protected_removals.map(&:ref)).to eq(['cdb'])
      expect(group).to be_approval_required
      expect(group).to be_approval_pending
      expect(group.decision).to eq(:auto)
      expect(group.rule).to eq(:ownership_verified)
      expect(group.with(approved: true)).not_to be_approval_pending
    end

    it 'derives protected removals from the keeper even when remove is empty' do
      group = collision_group(remove: [], records: [record('a'), record('b', stripe_subscription_id: 'sub_b')])

      expect(group.protected_removals.map(&:ref)).to eq(['cdb'])
      expect(group).to be_approval_pending
    end

    it 'does not require approval when only the keeper is protected, using either identifier' do
      group = collision_group(records: [record('a', subscription_status: 'active'), record('b')])

      %w[a cda].each do |keep|
        kept = group.with(keep: keep)
        expect(kept.protected_removals).to be_empty
        expect(kept).not_to be_approval_required
        expect(kept).not_to be_approval_pending
      end
    end

    it 'requires manual approval without any protected billing and after a keeper is chosen' do
      group = collision_group(decision: :manual, keep: nil, remove: [])

      expect(group).to be_approval_pending
      expect(group.with(keep: 'cda')).to be_approval_pending
      expect(group.with(keep: 'cda', approved: true)).not_to be_approval_pending
    end

    it 'protects both live records until the manual keeper is selected, then only the loser' do
      group = collision_group(decision: :manual, keep: nil, remove: [], records: [record('a', subscription_status: 'active'), record('b', subscription_status: 'trialing')])

      expect(group.protected_removals.map(&:ref)).to contain_exactly('cda', 'cdb')
      expect(group.with(keep: 'cdb').protected_removals.map(&:ref)).to eq(['cda'])
      expect(group.with(keep: 'cdb')).to be_approval_pending
    end
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

    it 'does not let a paid loser displace the record with historical DNS proof' do
      paid     = record('a', served: true, receipts: 5, subscription_status: 'active', stripe_subscription_id: 'sub_a')
      proof    = record('b', verified_confirmed_at: 1_700_000_100)
      baseline = rule.decide([paid.with(subscription_status: nil, stripe_subscription_id: nil), proof])
      decision = rule.decide([paid, proof])

      expect(decision.decision).to eq(:auto)
      expect(decision.rule).to eq(:dns_proof)
      expect(decision.keep).to eq('b')
      expect(decision.remove).to eq(['a'])
      expect([decision.decision, decision.rule, decision.keep, decision.remove])
        .to eq([baseline.decision, baseline.rule, baseline.keep, baseline.remove])
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

    it 'round-trips billing evidence and approval counts without changing the auto decision' do
      protected_group = collision_group(records: [record('a'), record('b', planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'active')])
      saved           = plan.with(groups: [protected_group])
      parsed          = plan_class.parse(saved.to_json)

      expect(parsed.groups.first.records.last.billing_fingerprint).to eq(%w[paid cus_b sub_b active])
      expect(parsed.groups.first.decision).to eq(:auto)
      expect(parsed.counts).to include(auto: 1, manual: 0, approval_required: 1, approval_pending: 1)
      expect(parsed).to be_attention
      approved = parsed.with(groups: [protected_group.with(approved: true)])
      expect(approved).not_to be_attention
      expect(approved.counts).to include(approval_required: 1, approval_pending: 0)
      expect(parsed.with(groups: [protected_group.with(skip: true)])).not_to be_attention
    end

    it 'still needs a keeper for an approved manual group' do
      manual = plan.groups.last.with(approved: true, keep: nil)

      expect(plan.with(groups: [manual])).to be_attention
      expect(plan.with(groups: [manual.with(skip: true)])).not_to be_attention
    end

    it 'rejects old version plans and version-edited old records without billing evidence' do
      expect(op_class::Rule::VERSION).to eq(2)
      old                 = JSON.parse(plan.to_json)
      old['rule_version'] = 1
      old['groups'].each do |group|
        group['records'].each do |snapshot|
          %w[planid stripe_customer_id stripe_subscription_id subscription_status].each { |field| snapshot.delete(field) }
        end
      end

      expect { plan_class.from_h(old) }.to raise_error(op_class::InvalidPlan, /rule_version/)
      old['rule_version'] = op_class::Rule::VERSION
      expect { plan_class.from_h(old) }.to raise_error(op_class::InvalidPlan)
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

  describe 'Outcome' do
    it 'defaults context to an empty hash for callers without saved evidence' do
      outcome = op_class::Outcome.new(
        ascii_name: 'pair.example',
        status: :skipped,
        reason: 'skipped in the plan',
        keep: nil,
        removals: [],
        index_claim: nil,
        verify_state: nil,
        errors: [],
      )

      expect(outcome.context).to eq({})
      expect(outcome.to_h[:context]).to eq({})
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
    let(:audit_events) { [] }
    # Written first, so the second write of the exact index entry (B) wins
    # and A is the shadow.
    let!(:id_a) { legacy!(:a, org: org_a, fields: { 'ownership_verified' => true }) }
    let!(:id_b) { legacy!(:b, org: org_b) }

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record) { |**event| audit_events << event }
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)
      expect_any_instance_of(Onetime::Organization).not_to receive(:stripe_customer)
      expect_any_instance_of(Onetime::Organization).not_to receive(:stripe_subscription)
      expect(Stripe::Customer).not_to receive(:retrieve)
      expect(Stripe::Subscription).not_to receive(:retrieve)
    end

    after do
      legacy.each_value { |(id, stored)| remove_legacy_custom_domain(id, stored) }
      [org_a, org_b].each do |org|
        Onetime::Organization.load(org.objid)&.destroy! if org.exists?
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

    def set_billing(org, **fields)
      fields.each do |key, value|
        # Billing IDs participate in unique indexes, including when another
        # instance updates them after the fixture's original instance loaded.
        value = "#{value}_#{sfx}" if [:stripe_customer_id, :stripe_subscription_id].include?(key) && !value.to_s.empty?
        org.public_send("#{key}=", value)
      end
      org.save
    end

    def approve(plan)
      plan.with(groups: plan.groups.map { |group| group.ascii_name == name ? group.with(approved: true) : group })
    end

    def summary_events
      audit_events.select { |event| event[:verb] == 'domain.resolve_collision' && event[:target] == name }
    end

    def json_value(value)
      JSON.parse(JSON.generate(value))
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

    it 'snapshots cached billing without changing the keeper or rule' do
      set_billing(org_b, planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'past_due')
      group = group_of(op_class.new.plan)
      loser = group.records.find { |snapshot| snapshot.domain_id == id_b }

      expect(loser.billing_fingerprint).to eq(['paid', "cus_b_#{sfx}", "sub_b_#{sfx}", 'past_due'])
      expect(group.keep_record.domain_id).to eq(id_a)
      expect(group.decision).to eq(:auto)
      expect(group.rule).to eq(:ownership_verified)
      expect(group).to be_approval_pending
    end

    describe '#apply' do
      let(:plan) { op_class.new.plan }

      it 'rejects incomplete audits before planning or removing anything' do
        saved = plan
        audit = Onetime::Operations::Domains::AsciiIndexAudit.new.call
        incomplete = audit.with(errors: [Onetime::Operations::Domains::AsciiIndexAudit::Unreadable.new(domain_id: 'unreadable', message: 'broken')])
        allow_any_instance_of(Onetime::Operations::Domains::AsciiIndexAudit).to receive(:call).and_return(incomplete)
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)

        expect { op_class.new.plan(audit: incomplete) }.to raise_error(op_class::InvalidPlan, /incomplete audit/i)
        expect { op_class.new.apply(saved, actor: 'cli', dry_run: false) }.to raise_error(op_class::InvalidPlan, /incomplete audit/i)
      end

      it 'refuses an empty keeper for owned records even with an edited all-orphans rule' do
        saved = plan
        edited = saved.with(groups: [group_of(saved).with(keep: nil, remove: [], rule: :all_orphans, approved: true)])
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        outcome = op_class.new.apply(edited, actor: 'cli', dry_run: false).outcomes.first
        expect(outcome).to have_attributes(status: :skipped, reason: /orphan/)
      end

      it 'skips mixed valid and unknown removal references without sorting nil' do
        saved = plan
        edited = saved.with(groups: [group_of(saved).with(remove: [group_of(saved).remove.first, 'unknown'])])
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        outcome = op_class.new.apply(edited, actor: 'cli', dry_run: false).outcomes.first
        expect(outcome).to have_attributes(status: :skipped, reason: /outside the group/)
      end

      it 'reports a failed preview as partial and requiring attention' do
        saved = plan
        allow(Onetime::Operations::Domains::Remove).to receive(:new).and_raise('preview failed')
        result = op_class.new.apply(saved, actor: 'cli', dry_run: true, only: name)
        expect(result.outcomes.first.status).to eq(:partial)
        expect(result).to be_attention
        expect(summary_events).to be_empty
      end

      %i[extid verification_state ownership_verified verified_by_override verified_confirmed_at served receipts configs all_configs brand vhost].each do |field|
        it "refuses changed #{field} evidence" do
          saved = plan
          group = group_of(saved)
          original = group.records.find { |r| r.domain_id == id_b }
          changed = { extid: 'changed', verification_state: :verified, ownership_verified: true,
                      verified_by_override: true, verified_confirmed_at: 123, served: !original.served,
                      receipts: 1, configs: ['mailer'], all_configs: ['mailer'], brand: true, vhost: true }.fetch(field)
          edited = saved.with(groups: [group.with(records: group.records.map { |r| r == original ? r.with(**{ field => changed }) : r }, remove: [])])
          expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
          outcome = op_class.new.apply(edited, actor: 'cli', dry_run: false).outcomes.first
          expect(outcome).to have_attributes(status: :skipped, reason: /changed since the plan/)
        end
      end

      it 'refreshes served evidence on successive plan calls' do
        operation = op_class.new
        operation.plan
        model.display_domain_index.put(name, id_a)
        refreshed = group_of(operation.plan)
        expect(refreshed.records.find { |r| r.domain_id == id_a }.served).to be true
        expect(refreshed.records.find { |r| r.domain_id == id_b }.served).to be false
      end

      it 'detects newly persisted DNS proof before any removal' do
        saved = plan
        domain = model.find_by_identifier(id_b)
        domain.verified_confirmed_at = Time.now.to_i
        domain.save
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(outcome).to have_attributes(status: :skipped, reason: /changed since the plan/)
      end

      it 'refreshes served evidence when reusing the planner for apply' do
        operation = op_class.new
        saved = operation.plan
        model.display_domain_index.put(name, id_a)
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        outcome = operation.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(outcome).to have_attributes(status: :skipped, reason: /changed since the plan/)
      end

      it 'preserves committed removals and writes a partial summary when keeper reload raises' do
        saved = plan
        allow(model).to receive(:find_by_identifier).and_call_original
        allow(Onetime::Operations::Domains::Remove).to receive(:new).and_wrap_original do |original, **args|
          removal = original.call(**args)
          allow(removal).to receive(:call).and_wrap_original do |call|
            result = call.call
            allow(model).to receive(:find_by_identifier).with(id_a).and_raise('keeper reload failed')
            result
          end
          removal
        end
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(outcome.status).to eq(:partial)
        expect(outcome.removals.map(&:status)).to eq([:removed])
        expect(outcome.errors.join).to include('keeper reload failed')
        expect(summary_events.last[:detail][:totals][:removed]).to eq(1)
      end

      [{ error: 'provider failed', persisted: true }, { error: nil, persisted: false }].each do |failure|
        it "reports verification failure #{failure.inspect} as partial" do
          saved = plan
          operation = op_class.new
          allow(operation).to receive(:strategy_name).and_return('approximated')
          verification = double(current_state: :pending, **failure)
          allow(Onetime::Operations::AdminVerifyDomain).to receive(:new).and_return(double(call: verification))
          outcome = operation.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
          expect(outcome.status).to eq(:partial)
          expect(outcome.verify_state).to eq(:pending)
          expect(outcome.errors).not_to be_empty
          expect(summary_events.last[:detail][:totals][:removed]).to eq(1)
        end
      end

      it 'skips sender detection errors before any removal' do
        saved = plan
        allow_any_instance_of(Onetime::Operations::Domains::CollisionSenderPreservation).to receive(:call).and_raise('unknown sender identity')
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(outcome).to have_attributes(status: :skipped, reason: /unknown sender identity/)
      end

      it 'checks live evidence before invoking sender detection' do
        saved = plan
        org_b.archive!
        expect(Onetime::Operations::Domains::CollisionSenderPreservation).not_to receive(:new)
        expect(Onetime::Operations::Domains::Remove).not_to receive(:new)
        expect(op_class.new.apply(saved, actor: 'cli', only: name).outcomes.first.status).to eq(:skipped)
      end

      it 'captures sender preservation during preflight and passes true only for a shared sender' do
        saved = plan
        detector = instance_double(Onetime::Operations::Domains::CollisionSenderPreservation, call: { id_b => true })
        expect(Onetime::Operations::Domains::CollisionSenderPreservation).to receive(:new)
                  .with(group: group_of(saved), records: kind_of(Array), identity_cache: {}).once.and_return(detector)
        expect(Onetime::Operations::Domains::Remove).to receive(:new).with(hash_including(keep_sender_identity: true))
          .and_return(double(call: double(reasserts_survivor: false)))
        expect(op_class.new.apply(saved, actor: 'cli', only: name).outcomes.first.status).to eq(:dry_run)
      end

      it 'uses a fresh sender identity cache on each apply of the same operation' do
        saved = plan
        operation = op_class.new
        caches = []
        allow(Onetime::Operations::Domains::CollisionSenderPreservation).to receive(:new) do |group:, records:, identity_cache:|
          expect(identity_cache).to be_empty
          expect(records.map(&:domain_id)).to include(id_a, id_b)
          caches << identity_cache
          identity_cache[id_b] = ['ses', 'previous.example']
          double(call: { id_b => false })
        end

        2.times do
          expect(operation.apply(saved, actor: 'cli', only: name).outcomes.first.status).to eq(:dry_run)
        end
        expect(caches.size).to eq(2)
        expect(caches.last).not_to equal(caches.first)
      end

      it 'preflights all selected groups before removing and retains skipped outcomes' do
        other_name = "other-#{sfx}.example"
        legacy[:o1] = [write_legacy_custom_domain(other_name, org_id: nil), other_name]
        legacy[:o2] = [write_legacy_custom_domain(other_name, org_id: nil), other_name]
        saved = op_class.new.plan
        selected = saved.with(groups: [group_of(saved), saved.group(other_name)])
        checked = []
        caches = []
        allow(Onetime::Operations::Domains::CollisionSenderPreservation).to receive(:new) do |group:, records:, identity_cache:|
          expect(records.map(&:domain_id)).to include(id_a, id_b, legacy[:o1].first, legacy[:o2].first)
          caches << identity_cache
          expect(caches.last).to equal(caches.first)
          checked << group.ascii_name
          raise 'unsafe other sender' if group.ascii_name == other_name

          double(call: { id_b => false })
        end
        allow(Onetime::Operations::Domains::Remove).to receive(:new).and_wrap_original do |original, **args|
          expect(checked).to eq([name, other_name])
          expect(args).not_to have_key(:keep_sender_identity)
          original.call(**args)
        end
        result = op_class.new.apply(selected, actor: 'cli', dry_run: false)
        expect(result.outcomes.map(&:status)).to eq([:applied, :skipped])
        expect(result.outcomes.last.reason).to include('unsafe other sender')
      end

      context 'with persisted SES sender identities' do
        let(:sender_configs) { [] }
        let(:sender_name) { "sender-#{sfx}.example.com" }
        let(:mailer_model) { Onetime::CustomDomain::MailerConfig }

        after do
          sender_configs.each { |config| config.destroy! if config.exists? }
        end

        def ses_config(domain_id)
          mailer_model.create!(domain_id: domain_id, provider: 'ses',
            from_address: "notify@#{sender_name}").tap { |config| sender_configs << config }
        end

        def other_sender_record(label, fqdn, verified: false)
          legacy[label] = [write_legacy_custom_domain(fqdn, org_id: org_b.objid,
            fields: { 'ownership_verified' => verified }), fqdn]
          legacy[label].first
        end

        it 'preserves the keeper sender while deleting the loser and its local config' do
          ses_config(id_a)
          ses_config(id_b)
          saved = plan
          expect(Onetime::Operations::DeleteSenderDomain).not_to receive(:new)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(outcome.status).to eq(:applied)
          expect(model.find_by_identifier(id_b)).to be_nil
          expect(mailer_model.exists_for_domain?(id_b)).to be false
          expect(mailer_model.exists_for_domain?(id_a)).to be true
        end

        [false, true].each do |only_selected|
          it "preserves a sender shared across collision groups (only: #{only_selected})" do
            other_name = "other-#{sfx}.example"
            other_keeper = other_sender_record(:other_keeper, other_name, verified: true)
            other_loser = other_sender_record(:other_loser, other_name)
            ses_config(id_b)
            ses_config(other_keeper)
            saved = plan
            # A nil-config deletion in the other group is harmless; no SES
            # identity may reach the remote cleanup operation.
            allow(Onetime::Operations::DeleteSenderDomain).to receive(:new).and_wrap_original do |original, **args|
              expect(args[:mailer_config]).to be_nil
              original.call(**args)
            end

            result = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: only_selected ? name : nil)

            expect(result.outcomes.map(&:status)).to all(eq(:applied))
            expect(model.find_by_identifier(id_b)).to be_nil
            expect(mailer_model.exists_for_domain?(id_b)).to be false
            expect(model.find_by_identifier(other_keeper)).not_to be_nil
            expect(mailer_model.exists_for_domain?(other_keeper)).to be true
            expect(model.find_by_identifier(other_loser).nil?).to eq(!only_selected)
          end
        end

        it 'preserves a sender shared with a noncollision survivor outside --only' do
          survivor = other_sender_record(:survivor, "single-#{sfx}.example")
          ses_config(survivor)
          ses_config(id_b)
          saved = plan
          expect(saved.groups.map(&:ascii_name)).not_to include("single-#{sfx}.example")
          expect(Onetime::Operations::DeleteSenderDomain).not_to receive(:new)

          result = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name)

          expect(result.outcomes.first.status).to eq(:applied)
          expect(model.find_by_identifier(id_b)).to be_nil
          expect(mailer_model.exists_for_domain?(id_b)).to be false
          expect(model.find_by_identifier(survivor)).not_to be_nil
          expect(mailer_model.exists_for_domain?(survivor)).to be true
        end

        it 'preserves a shared sender when the first planned removal fails and the second commits' do
          id_c = legacy!(:c, org: org_b)
          ses_config(id_b)
          ses_config(id_c)
          saved = plan
          lock = mailer_model.sender_identity_lock(id_b)
          token = lock.acquire(ttl: 60)
          expect(token).to be_truthy
          expect(Onetime::Operations::DeleteSenderDomain).not_to receive(:new)

          result = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name)
          outcome = result.outcomes.first

          expect(outcome.status).to eq(:partial)
          expect(outcome.removals.map(&:status)).to eq([:failed, :removed])
          expect(model.find_by_identifier(id_b)).not_to be_nil
          expect(mailer_model.exists_for_domain?(id_b)).to be true
          expect(model.find_by_identifier(id_c)).to be_nil
          expect(mailer_model.exists_for_domain?(id_c)).to be false
          expect(summary_events.last[:detail][:totals]).to include(removed: 1, failed: 1)
        ensure
          lock.release(token) if token
        end

        it 'still invokes sender cleanup for an unshared SES identity' do
          ses_config(id_b)
          saved = plan
          strategy = Onetime::Mail::SenderStrategies.for_provider('ses')
          allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('ses').and_return(strategy)
          expect(strategy).to receive(:delete_sender_identity)
            .with(have_attributes(domain_id: id_b), credentials: anything)
            .and_return(deleted: true, message: 'test cleanup')

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(outcome.status).to eq(:applied)
          expect(model.find_by_identifier(id_b)).to be_nil
          expect(mailer_model.exists_for_domain?(id_b)).to be false
        end
      end

      it 'previews on a dry run and removes nothing' do
        result  = op_class.new.apply(plan, actor: 'cli', dry_run: true)
        outcome = result.outcomes.find { |o| o.ascii_name == name }

        expect(result.dry_run).to be true
        expect(outcome.status).to eq(:dry_run)
        expect(outcome.removals.map(&:status)).to eq([:planned])
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
        expect(summary_events).to be_empty
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
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

      %w[active trialing past_due unpaid future_status].each do |status|
        it "refuses an unapproved automatic removal with cached status #{status}" do
          set_billing(org_b, subscription_status: status)
          saved = plan
          group = group_of(saved)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(group.decision).to eq(:auto)
          expect(group.rule).to eq(:ownership_verified)
          expect(outcome).to have_attributes(status: :skipped, reason: /approv/i)
          expect(outcome.removals).to be_empty
          expect(model.find_by_identifier(id_b)).not_to be_nil
          expect(model.display_domain_id_for(name)).to eq(id_b)
        end
      end

      it 'previews an unapproved protected removal as skipped without operator audit writes' do
        set_billing(org_b, subscription_status: 'active')

        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: true, only: name).outcomes.first

        expect(outcome).to have_attributes(status: :skipped, reason: /approv/i)
        expect(audit_events).to be_empty
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      it 'removes a canceled subscription record without approval despite its Stripe references' do
        set_billing(org_b, stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'canceled')

        expect(group_of(plan)).not_to be_approval_required
        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:applied)
        expect(model.find_by_identifier(id_b)).to be_nil
      end

      it 'requires approval for unknown billing with only a Stripe reference' do
        set_billing(org_b, stripe_customer_id: 'cus_b', subscription_status: nil)

        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(group_of(plan).records.find { |snapshot| snapshot.domain_id == id_b }.billing_label.to_s).to eq('unknown')
        expect(outcome).to have_attributes(status: :skipped, reason: /approv/i)
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      %w[active future_status].each do |status|
        it "removes a protected #{status} loser once explicitly approved" do
          set_billing(org_b, stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: status)
          saved = approve(plan)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(outcome.status).to eq(:applied)
          expect(outcome.removals.map(&:status)).to eq([:removed])
          expect(model.find_by_identifier(id_b)).to be_nil
          expect(model.find_by_identifier(id_a)).not_to be_nil
        end
      end

      it 'does not require approval when the paid record is kept' do
        set_billing(org_a, subscription_status: 'active')
        saved = plan

        expect(group_of(saved)).not_to be_approval_required
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:applied)
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(model.find_by_identifier(id_b)).to be_nil
      end

      it 'requires explicit approval for a manual group with two live subscriptions' do
        set_billing(org_a, subscription_status: 'active')
        set_billing(org_b, subscription_status: 'trialing')
        domain_b                    = model.find_by_identifier(id_b)
        domain_b.ownership_verified = true
        domain_b.save
        saved                       = plan
        manual                      = group_of(saved)
        expect(manual).to be_manual
        expect(manual).to be_approval_required
        chosen                      = saved.with(groups: [manual.with(keep: manual.records.find { |snapshot| snapshot.domain_id == id_a }.ref, remove: [])])

        pending = op_class.new.apply(chosen, actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(pending).to have_attributes(status: :skipped, reason: /approv/i)
        expect(model.find_by_identifier(id_b)).not_to be_nil

        applied = op_class.new.apply(approve(chosen), actor: 'cli', dry_run: false, only: name).outcomes.first
        expect(applied.status).to eq(:applied)
        expect(model.find_by_identifier(id_b)).to be_nil
      end

      it 'does not bypass billing approval when a manual decision is edited to auto' do
        set_billing(org_b, subscription_status: 'active')
        group                              = group_of(plan).with(decision: :manual)
        edited                             = JSON.parse(plan.with(groups: [group]).to_json)
        edited['groups'].first['decision'] = 'auto'
        edited['groups'].first['remove']   = []

        outcome = op_class.new.apply(op_class::Plan.from_h(edited), actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome).to have_attributes(status: :skipped, reason: /approv/i)
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      it 'refuses tampered billing evidence instead of letting it bypass approval' do
        set_billing(org_b, planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'active')
        edited                                                                                               = JSON.parse(plan.to_json)
        group                                                                                                = edited['groups'].find { |candidate| candidate['ascii_name'] == name }
        loser                                                                                                = group['records'].find { |snapshot| snapshot['domain_id'] == id_b }
        %w[planid stripe_customer_id stripe_subscription_id subscription_status].each { |field| loser[field] = nil }
        tampered                                                                                             = op_class::Plan.from_h(edited)
        expect(group_of(tampered)).not_to be_approval_required

        outcome = op_class.new.apply(tampered, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:skipped)
        expect(outcome.reason).to match(/changed|approv/i)
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
      end

      {
        planid: 'another_plan',
        stripe_customer_id: 'cus_changed',
        stripe_subscription_id: 'sub_changed',
        subscription_status: 'future_status',
      }.each do |field, changed|
        it "skips changed #{field} even when the saved group was approved" do
          set_billing(org_b, planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'active')
          saved     = approve(plan)
          fresh_org = Onetime::Organization.load(org_b.objid)
          set_billing(fresh_org, **{ field => changed })

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(outcome).to have_attributes(status: :skipped, reason: /changed since the plan/)
          expect(model.find_by_identifier(id_b)).not_to be_nil
        end
      end

      [
        { subscription_status: 'active' },
        { stripe_customer_id: 'cus_new', subscription_status: nil },
      ].each do |billing|
        it "skips an initially unprotected loser whose billing becomes #{billing.inspect} before apply" do
          saved     = plan
          expect(group_of(saved)).not_to be_approval_required
          fresh_org = Onetime::Organization.load(org_b.objid)
          set_billing(fresh_org, **billing)
          expect(Onetime::Operations::Domains::Teardown).not_to receive(:new)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

          expect(outcome).to have_attributes(status: :skipped, reason: /billing changed since the plan/)
          expect(outcome.removals).to be_empty
          expect(model.find_by_identifier(id_a)).not_to be_nil
          expect(model.find_by_identifier(id_b)).not_to be_nil
          expect(model.display_domain_id_for(name)).to eq(id_b)
        end
      end

      it 'skips without removals when reloading organization billing raises' do
        saved = plan
        allow(Onetime::Organization).to receive(:load).and_call_original
        allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_raise(StandardError, 'billing reload unavailable')
        expect(Onetime::Operations::Domains::Teardown).not_to receive(:new)

        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome).to have_attributes(status: :skipped, reason: /could not recheck organization billing.*billing reload unavailable/)
        expect(outcome.removals).to be_empty
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
      ensure
        allow(Onetime::Organization).to receive(:load).and_call_original
      end

      it 'skips a changed organization state even when the saved group was approved' do
        saved = approve(plan)
        org_b.archive!

        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome).to have_attributes(status: :skipped, reason: /changed since the plan/)
        expect(model.find_by_identifier(id_b)).not_to be_nil
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

      it 'includes full saved evidence and correlates the summary with each removal audit' do
        saved   = plan
        group   = group_of(saved)
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
        context = json_value(outcome.context)

        expect(context).to include(
          'run_id' => match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/),
          'plan_generated_at' => saved.generated_at,
          'rule_version' => op_class::Rule::VERSION,
          'decision' => 'auto',
          'rule' => 'ownership_verified',
          'approved' => false,
          'approval_required' => false,
          'billing_source' => 'local_cache',
          'records' => json_value(group.records.map(&:to_h)),
          'notes' => group.notes,
        )
        expect(json_value(outcome.to_h)['context']).to eq(context)
        expect(summary_events.size).to eq(1)
        summary = summary_events.first
        expect(summary).to include(actor: 'cli', result: :success, fail_closed: true)
        detail  = json_value(summary[:detail])
        expect(detail).to include(context)
        expect(detail).to include(
          'keep' => outcome.keep,
          'status' => 'applied',
          'reason' => nil,
          'removals' => json_value(outcome.to_h[:removals]),
          'index_claim' => 'created',
          'verify_state' => nil,
          'errors' => [],
          'totals' => a_kind_of(Hash),
        )
        removal = audit_events.find { |event| event[:verb] == 'domain.remove' }
        expect(removal).to include(result: :success, fail_closed: true)
        expect(removal[:detail][:reason]).to include(context['run_id'], outcome.keep, group.rule.to_s)
      end

      it 'uses one run ID for all groups in an apply and a new ID on the next apply' do
        orphan_name = "orph-#{sfx}.example"
        legacy[:o1] = [write_legacy_custom_domain(orphan_name, org_id: nil), orphan_name]
        legacy[:o2] = [write_legacy_custom_domain(orphan_name, org_id: nil), orphan_name]
        saved       = plan.with(groups: plan.groups.select { |group| [name, orphan_name].include?(group.ascii_name) })

        operation = op_class.new
        first     = operation.apply(saved, actor: 'cli', dry_run: true)
        second    = operation.apply(saved, actor: 'cli', dry_run: true)
        ids       = first.outcomes.map { |outcome| json_value(outcome.context)['run_id'] }

        expect(first.outcomes.size).to eq(2)
        expect(ids.uniq.size).to eq(1)
        expect(ids.first).not_to be_nil
        expect(json_value(second.outcomes.first.context)['run_id']).not_to eq(ids.first)
        expect(audit_events).to be_empty
      end

      it 'records a failure summary with context for a skipped group and no removal audit' do
        set_billing(org_b, subscription_status: 'active')
        saved   = plan
        outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:skipped)
        expect(json_value(outcome.context)).to include(
          'approval_required' => true,
          'approved' => false,
          'records' => json_value(group_of(saved).records.map(&:to_h)),
        )
        expect(summary_events.size).to eq(1)
        expect(summary_events.first).to include(actor: 'cli', result: :failure, fail_closed: true)
        expect(json_value(summary_events.first[:detail])).to include(
          'status' => 'skipped', 'reason' => outcome.reason, 'removals' => [], 'totals' => a_kind_of(Hash),
        )
        expect(audit_events.none? { |event| event[:verb] == 'domain.remove' }).to be true
      end

      it 'records a partial failure summary with the actual failed removal' do
        allow(Onetime::Operations::Domains::Teardown).to receive(:new).and_raise(StandardError, 'teardown unavailable')

        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(outcome.status).to eq(:partial)
        expect(outcome.removals.first).to have_attributes(status: :failed, detail: /teardown unavailable/)
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(summary_events.size).to eq(1)
        expect(summary_events.first).to include(result: :failure, fail_closed: true)
        expect(json_value(summary_events.first[:detail])).to include(
          'status' => 'partial',
          'removals' => json_value(outcome.to_h[:removals]),
          'errors' => outcome.errors,
          'totals' => a_kind_of(Hash),
        )
      end

      it 'counts a committed deletion with a failed domain.remove audit as removed, not failed' do
        removed_ref = legacy_custom_domain_extid(id_b)
        allow(Onetime::ColonelAuditEvent).to receive(:record) do |**event|
          audit_events << event
          if event[:verb] == 'domain.remove' && event[:result] == :success && event[:target] == removed_ref
            raise Onetime::AuditWriteFailure.new(verb: event[:verb], target: event[:target])
          end
        end

        result  = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name)
        outcome = result.outcomes.first

        expect(model.find_by_identifier(id_b)).to be_nil
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(outcome.status).to eq(:partial)
        expect(outcome.removals.first).to have_attributes(ref: removed_ref, status: :removed_audit_failed, detail: /domain.remove/)
        expect(result).to be_attention
        expect(summary_events.first).to include(result: :failure)
        expect(json_value(summary_events.first[:detail])['totals']).to include(
          'records' => 2, 'removals' => 1, 'removed' => 1, 'failed' => 0, 'audit_failed' => 1,
        )
      end

      it 'reports mixed successful, uncommitted failed, and removed-audit-failed deletions accurately' do
        id_c        = legacy!(:c, org: org_b)
        id_d        = legacy!(:d, org: org_b)
        removed_ref = legacy_custom_domain_extid(id_b)
        allow(Onetime::ColonelAuditEvent).to receive(:record) do |**event|
          audit_events << event
          if event[:verb] == 'domain.remove' && event[:result] == :success && event[:target] == removed_ref
            raise Onetime::AuditWriteFailure.new(verb: event[:verb], target: event[:target])
          end
        end
        allow(Onetime::Operations::Domains::Teardown).to receive(:new).and_wrap_original do |original, **attributes|
          raise StandardError, 'teardown unavailable for c' if attributes[:domain].objid == id_c

          original.call(**attributes)
        end

        outcome = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name).outcomes.first

        expect(model.find_by_identifier(id_b)).to be_nil
        expect(model.find_by_identifier(id_c)).not_to be_nil
        expect(model.find_by_identifier(id_d)).to be_nil
        expect(outcome.status).to eq(:partial)
        expect(outcome.removals.map { |removal| [removal.ref, removal.status] }).to contain_exactly(
          [removed_ref, :removed_audit_failed],
          [legacy_custom_domain_extid(id_c), :failed],
          [legacy_custom_domain_extid(id_d), :removed],
        )
        expect(summary_events.first).to include(result: :failure)
        expect(json_value(summary_events.first[:detail])['totals']).to include(
          'records' => 4, 'removals' => 3, 'removed' => 2, 'failed' => 1, 'audit_failed' => 1,
        )
      end

      it 'reports summary audit failure as partial without relabeling a committed removal as failed' do
        allow(Onetime::ColonelAuditEvent).to receive(:record) do |**event|
          audit_events << event
          if event[:verb] == 'domain.resolve_collision'
            raise Onetime::AuditWriteFailure.new(verb: event[:verb], target: event[:target])
          end
        end

        result  = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name)
        outcome = result.outcomes.first

        expect(outcome.status).to eq(:partial)
        expect(outcome.removals.map(&:status)).to eq([:removed])
        expect(outcome.errors.join(' ')).to match(/audit/i)
        expect(outcome.errors.join(' ')).to include('domain.resolve_collision')
        expect(result).to be_attention
        expect(model.find_by_identifier(id_b)).to be_nil
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(audit_events.count { |event| event[:verb] == 'domain.remove' }).to eq(1)
      end

      it 'also surfaces summary audit failure for a skipped group, without removing anything' do
        set_billing(org_b, subscription_status: 'active')
        allow(Onetime::ColonelAuditEvent).to receive(:record) do |**event|
          audit_events << event
          raise Onetime::AuditWriteFailure.new(verb: event[:verb], target: event[:target])
        end

        result  = op_class.new.apply(plan, actor: 'cli', dry_run: false, only: name)
        outcome = result.outcomes.first

        expect(outcome.status).to eq(:partial)
        expect(outcome.reason).to match(/approv/i)
        expect(outcome.errors.join(' ')).to include('domain.resolve_collision')
        expect(outcome.removals).to be_empty
        expect(result).to be_attention
        expect(model.find_by_identifier(id_a)).not_to be_nil
        expect(model.find_by_identifier(id_b)).not_to be_nil
      end

      describe 'persisted summary evidence' do
        let(:audit_class) { Onetime::ColonelAuditEvent }

        before do
          allow(audit_class).to receive(:record).and_call_original
        end

        after do
          targets = [name, *legacy.values.map { |(id, _)| legacy_custom_domain_extid(id) }]
          audit_class.dbclient.zrange(audit_class.events.dbkey, 0, -1).each do |member|
            audit_class.dbclient.zrem(audit_class.events.dbkey, member) if targets.include?(JSON.parse(member)['target'])
          end
        end

        it 'retains every billing field through the real audit serializer with run ID, checksum, and totals' do
          set_billing(org_b, planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'past_due')
          saved = approve(plan)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
          stored  = audit_class.recent(1).first

          expect(outcome.status).to eq(:applied)
          expect(stored).to include('verb' => 'domain.resolve_collision', 'target' => name, 'result' => 'success')
          detail = stored.fetch('detail')
          expect(detail).to include(
            'run_id' => outcome.context.fetch(:run_id),
            'plan_sha256' => Digest::SHA256.hexdigest(saved.to_json),
          )
          expect(detail.fetch('records')).to eq(json_value(group_of(saved).records.map(&:to_h)))
          loser  = detail.fetch('records').find { |snapshot| snapshot['domain_id'] == id_b }
          expect(loser).to include(
            'planid' => 'paid',
            'stripe_customer_id' => "cus_b_#{sfx}",
            'stripe_subscription_id' => "sub_b_#{sfx}",
            'subscription_status' => 'past_due',
          )
          expect(detail.fetch('removals')).to eq(json_value(outcome.to_h.fetch(:removals)))
          expect(detail.fetch('totals')).to include('records' => 2, 'removals' => 1, 'removed' => 1, 'failed' => 0, 'audit_failed' => 0)
        end

        it 'caps large summary arrays while totals and returned evidence retain the complete counts' do
          cap   = audit_class::MAX_DETAIL_KEYS
          cap.times { |index| legacy!("extra-#{index}", org: org_b) }
          set_billing(org_b, planid: 'paid', stripe_customer_id: 'cus_b', stripe_subscription_id: 'sub_b', subscription_status: 'active')
          saved = approve(plan)

          outcome = op_class.new.apply(saved, actor: 'cli', dry_run: false, only: name).outcomes.first
          stored  = audit_class.recent(1).first

          expect(outcome.status).to eq(:applied)
          expect(stored).to include('verb' => 'domain.resolve_collision', 'target' => name, 'result' => 'success')
          detail = stored.fetch('detail')
          expect(detail).to include(
            'run_id' => outcome.context.fetch(:run_id),
            'plan_sha256' => Digest::SHA256.hexdigest(saved.to_json),
          )
          expect(outcome.context.fetch(:records).size).to eq(cap + 2)
          expect(outcome.removals.size).to eq(cap + 1)
          expect(detail.fetch('records')).to eq(json_value(outcome.context.fetch(:records).first(cap)))
          expect(detail.fetch('removals')).to eq(json_value(outcome.to_h.fetch(:removals).first(cap)))
          expect(detail.fetch('records').select { |snapshot| snapshot['org_id'] == org_b.objid }).to all(
            include(
              'stripe_subscription_id' => "sub_b_#{sfx}", 'subscription_status' => 'active',
            ),
          )
          expect(detail.fetch('totals')).to include(
            'records' => cap + 2, 'removals' => cap + 1, 'removed' => cap + 1, 'failed' => 0, 'audit_failed' => 0,
          )
        end
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
