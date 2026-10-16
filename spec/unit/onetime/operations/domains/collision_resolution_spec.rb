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

      it 'previews on a dry run and removes nothing' do
        result  = op_class.new.apply(plan, actor: 'cli', dry_run: true)
        outcome = result.outcomes.find { |o| o.ascii_name == name }

        expect(result.dry_run).to be true
        expect(outcome.status).to eq(:dry_run)
        expect(outcome.removals.map(&:status)).to eq([:planned])
        expect(model.find_by_identifier(id_b)).not_to be_nil
        expect(model.display_domain_id_for(name)).to eq(id_b)
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
