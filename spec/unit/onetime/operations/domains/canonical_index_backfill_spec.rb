# spec/unit/onetime/operations/domains/canonical_index_backfill_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Domains::CanonicalIndexAudit and CanonicalIndexBackfill.
#
# The audit compares every custom domain record with
# canonical_display_domain_index and puts each in one category; the backfill
# claims missing entries, re-claims entries left naming deleted records, and
# releases entries no record accounts for. Collisions and conflicts are left
# for an operator.
#
# Real datastore: the audit scans the keyspace and the backfill's writes are
# server-side compare-and-set scripts. Both look at every record in the lane's
# database, so assertions are narrowed to this file's fixtures (each name
# carries a random suffix). The no-op properties (a dry run writes nothing, a
# second apply changes nothing) are asserted over the whole index.

require 'spec_helper'
require 'delegate'
require 'securerandom'
require 'simpleidn'
require 'onetime/operations/domains/canonical_index_backfill'

RSpec.describe Onetime::Operations::Domains::CanonicalIndexBackfill, :datastore do
  include LegacyCustomDomainRecords

  let(:model) { Onetime::CustomDomain }
  let(:index) { model.canonical_display_domain_index }
  let(:sfx) { SecureRandom.hex(4) }
  let(:org_a) { Onetime::Organization.new(display_name: "Backfill A #{sfx}").tap(&:save) }
  let(:org_b) { Onetime::Organization.new(display_name: "Backfill B #{sfx}").tap(&:save) }
  let(:legacy) { {} }
  let(:created) { [] }
  let(:entries_written) { [] }

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[canonical_index_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy.each_value { |(id, name)| remove_legacy_custom_domain(id, name) }
    entries_written.each { |key, holder| index.release_field(key, holder) }
    [org_a, org_b].each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[canonical_index_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  def legacy!(label, display_domain, org: org_a)
    legacy[label] = [write_legacy_custom_domain(display_domain, org_id: org&.objid), display_domain]
    legacy[label].first
  end

  def id_of(label)
    legacy.fetch(label).first
  end

  def put_entry(key, holder)
    index.put(key, holder)
    entries_written << [key, holder]
  end

  def canonical(name)
    model.canonical_display_domain(name)
  end

  def audit
    Onetime::Operations::Domains::CanonicalIndexAudit.new.call
  end

  def categories(result, ids)
    result.rows.select { |row| ids.include?(row.domain_id) }.to_h { |row| [row.domain_id, row.category] }
  end

  def entry_categories(result, keys)
    result.entries.select { |entry| keys.include?(entry.canonical) }.to_h { |entry| [entry.canonical, entry.category] }
  end

  # Stands in for the canonical index, overriding the given methods; the
  # rest reach the real index.
  def with_index(overrides)
    real    = index
    wrapper = Class.new(SimpleDelegator) do
      overrides.each { |method, body| define_method(method) { |*args| body.call(__getobj__, *args) } }
    end.new(real)
    allow(model).to receive(:canonical_display_domain_index).and_return(wrapper)
  end

  def outcome_for(result, id)
    result.actions.find { |a| a.domain_id == id }&.outcome
  end

  # A crafted A-label whose decoded Unicode NFC-normalises to the same name as
  # bücher-#{sfx}: punycode of the decomposed spelling. It is a different DNS
  # name and must stay keyed under itself.
  def crafted_a_label
    "xn--#{SimpleIDN::Punycode.encode("bu\u0308cher-#{sfx}")}.com"
  end

  # One fixture per category, all with this example's suffix.
  def build_world
    legacy!(:nfd, "bu\u0308cher-#{sfx}.com")
    legacy!(:fullwidth, "ｆｕｌｌ-#{sfx}.com") # fullwidth letters: maps to full-#{sfx}.com
    legacy!(:mixed, "xn--bcher-kva.mixed-ü-#{sfx}.com")
    legacy!(:nfc, "nfc-ä-#{sfx}.com")
    legacy!(:a_label, canonical("alabel-ö-#{sfx}.com"))
    legacy!(:crafted, crafted_a_label)
    legacy!(:orphan, "orphan-é-#{sfx}.com", org: nil)
    # Two records for one DNS name in two organizations: one stored as NFC
    # Unicode, one as the A-label.
    legacy!(:pair_unicode, "pair-ü-#{sfx}.com")
    legacy!(:pair_a_label, canonical("pair-ü-#{sfx}.com"), org: org_b)
    # The entry for its own name names a record that no longer exists.
    legacy!(:stale, "stale-ü-#{sfx}.com")
    put_entry(canonical("stale-ü-#{sfx}.com"), "gone-#{sfx}")
    # The entry for its own name names another, live record.
    @other   = model.create!("other-#{sfx}.com", org_b.objid).tap { |rec| created << rec }
    legacy!(:conflict, "conflict-ü-#{sfx}.com")
    put_entry(canonical("conflict-ü-#{sfx}.com"), @other.identifier)
    # No A-label form: a 64-octet label.
    legacy!(:unconvertible, "#{'a' * 64}-#{sfx}.com")
    # Registered after the index existed.
    @current = model.create!("current-ü-#{sfx}.com", org_a.objid).tap { |rec| created << rec }
    # Entries keyed by names no record has.
    put_entry("nobody-gone-#{sfx}.com", "gone2-#{sfx}")
    put_entry("nobody-live-#{sfx}.com", @other.identifier)
  end

  def fixture_ids
    legacy.values.map(&:first) + [@current.identifier]
  end

  def unmatched_keys
    ["nobody-gone-#{sfx}.com", "nobody-live-#{sfx}.com"]
  end

  def expected_categories
    {
      id_of(:nfd) => :missing,
      id_of(:fullwidth) => :missing,
      id_of(:mixed) => :missing,
      id_of(:nfc) => :missing,
      id_of(:a_label) => :missing,
      id_of(:crafted) => :missing,
      id_of(:orphan) => :missing,
      id_of(:pair_unicode) => :collision,
      id_of(:pair_a_label) => :collision,
      id_of(:stale) => :stale,
      id_of(:conflict) => :conflict,
      id_of(:unconvertible) => :unconvertible,
      @current.identifier => :ok,
    }
  end

  describe 'the audit' do
    before { build_world }

    it 'puts each record in its category' do
      expect(categories(audit, fixture_ids)).to eq(expected_categories)
    end

    it 'reports entries keyed by names no record has' do
      expect(entry_categories(audit, unmatched_keys))
        .to eq("nobody-gone-#{sfx}.com" => :stale, "nobody-live-#{sfx}.com" => :conflict)
    end

    it 'groups the records that share an A-label' do
      group = audit.collision_groups.fetch(canonical("pair-ü-#{sfx}.com"))

      expect(group.map(&:domain_id)).to contain_exactly(id_of(:pair_unicode), id_of(:pair_a_label))
    end

    # The runbook removes collision records with `bin/ots domains remove <extid>`.
    it 'names each collision record by an extid that resolves to it' do
      group = audit.collision_groups.fetch(canonical("pair-ü-#{sfx}.com"))

      expect(group.to_h { |row| [row.domain_id, model.find_by_extid(row.extid)&.identifier] })
        .to eq(group.to_h { |row| [row.domain_id, row.domain_id] })
    end

    it 'keys the crafted A-label under itself, apart from the name it decodes to' do
      row = audit.rows.find { |r| r.domain_id == id_of(:crafted) }

      expect([row.canonical, row.canonical == canonical("bücher-#{sfx}.com")]).to eq([crafted_a_label, false])
    end

    it 'asks for an operator while collisions or conflicts exist' do
      expect(audit.attention?).to be(true)
    end

    it 'writes nothing' do
      before_index = index.hgetall

      audit

      expect(index.hgetall).to eq(before_index)
    end
  end

  describe 'a dry run' do
    before { build_world }

    it 'writes nothing' do
      before_index = index.hgetall

      described_class.new.call

      expect(index.hgetall).to eq(before_index)
    end

    it 'plans a claim per missing record, a re-claim per stale record and a release per unmatched stale entry' do
      result  = described_class.new.call
      planned = result.actions.select { |a| fixture_ids.include?(a.domain_id) || unmatched_keys.include?(a.canonical) }

      summary = planned.to_h { |a| [a.domain_id || a.canonical, [a.kind, a.outcome]] }
      missing = expected_categories.select { |_id, category| category == :missing }.keys
      expect(summary).to eq(
        missing.to_h { |id| [id, [:claim, :planned]] }.merge(
          id_of(:stale) => [:reclaim, :planned],
          "nobody-gone-#{sfx}.com" => [:release, :planned],
        ),
      )
    end
  end

  describe 'an incomplete audit' do
    let(:unreadable_id) { id_of(:pair_a_label) }

    before do
      build_world
      allow(model).to receive(:load_multi).and_wrap_original do |original, identifiers|
        raise StandardError, 'simulated unreadable legacy record' if identifiers.include?(unreadable_id)

        original.call(identifiers)
      end
      allow(model).to receive(:find_by_identifier).and_call_original
      allow(model).to receive(:find_by_identifier).with(unreadable_id)
        .and_raise(StandardError, 'simulated unreadable legacy record')
    end

    it 'refuses the apply and leaves every claim, reclaim and release planned' do
      before_index = index.hgetall
      operation    = described_class.new(dry_run: false)
      expect(operation).not_to receive(:apply)

      result = operation.call

      # The unreadable duplicate is absent from grouping, so the readable
      # member looks missing rather than colliding. It must not win the name.
      expect(categories(result.audit, [id_of(:pair_unicode)])).to eq(id_of(:pair_unicode) => :missing)
      expect(result.audit.errors.map(&:to_h)).to include(
        domain_id: unreadable_id, message: 'StandardError: simulated unreadable legacy record',
      )
      expect(result.actions.map(&:kind).uniq).to contain_exactly(:claim, :reclaim, :release)
      expect(result.actions).to all(have_attributes(outcome: :planned, detail: nil))
      expect([result.refusal, result.applied?]).to eq([:unreadable_records, false])
      expect([result.changes, result.failures, result.attention?]).to eq([[], [], true])
      expect(index.hgetall).to eq(before_index)
      expect(index.get(canonical("pair-ü-#{sfx}.com"))).to be_nil
      expect(index.get(canonical("stale-ü-#{sfx}.com"))).to eq("gone-#{sfx}")
      expect(index.get("nobody-gone-#{sfx}.com")).to eq("gone2-#{sfx}")
    end

    it 'keeps a dry run read-only and retains its provisional plan and errors' do
      before_index = index.hgetall
      operation    = described_class.new
      expect(operation).not_to receive(:apply)

      result = operation.call

      expect(result.actions.map(&:kind).uniq).to contain_exactly(:claim, :reclaim, :release)
      expect(result.actions).to all(have_attributes(outcome: :planned))
      expect([result.refusal, result.changes]).to eq([nil, result.actions])
      expect(result.audit.errors.map(&:domain_id)).to include(unreadable_id)
      expect(result.attention?).to be(true)
      expect(index.hgetall).to eq(before_index)
    end

    it 'allows claims, reclaims and releases once the full inventory can be read' do
      allow(model).to receive(:load_multi).and_call_original
      allow(model).to receive(:find_by_identifier).with(unreadable_id).and_call_original

      result = described_class.new(dry_run: false).call

      expect(result.audit.errors).to be_empty
      expect(categories(result.audit, [id_of(:pair_unicode), unreadable_id])).to eq(
        id_of(:pair_unicode) => :collision, unreadable_id => :collision,
      )
      expect(result.changes.map(&:kind).uniq).to contain_exactly(:claim, :reclaim, :release)
      expect(index.get(canonical("pair-ü-#{sfx}.com"))).to be_nil
      expect(index.get(canonical("bu\u0308cher-#{sfx}.com"))).to eq(id_of(:nfd))
      expect(index.get(canonical("stale-ü-#{sfx}.com"))).to eq(id_of(:stale))
      expect(index.get("nobody-gone-#{sfx}.com")).to be_nil
    end
  end

  describe 'an apply' do
    before { build_world }

    let!(:result) { described_class.new(dry_run: false).call }

    it 'enters each missing record under its A-label' do
      missing = expected_categories.select { |_id, category| category == :missing }.keys
      names   = legacy.values.to_h { |id, name| [id, name] }

      expect(missing.to_h { |id| [id, index.get(canonical(names.fetch(id)))] }).to eq(missing.to_h { |id| [id, id] })
    end

    it 're-claims the stale entry for the record that has the name' do
      expect(index.get(canonical("stale-ü-#{sfx}.com"))).to eq(id_of(:stale))
    end

    it 'releases the stale entry no record accounts for' do
      expect(index.get("nobody-gone-#{sfx}.com")).to be_nil
    end

    it 'leaves collisions, conflicts and the record that has no A-label untouched' do
      observed = [
        index.get(canonical("pair-ü-#{sfx}.com")),
        index.get(canonical("conflict-ü-#{sfx}.com")),
        index.get("nobody-live-#{sfx}.com"),
      ]

      expect(observed).to eq([nil, @other.identifier, @other.identifier])
    end

    it 'leaves the records themselves alone' do
      expect(model.find_by_identifier(id_of(:nfd)).display_domain).to eq("bu\u0308cher-#{sfx}.com")
    end

    it 'reports the state after the writes' do
      after = expected_categories.transform_values { |category| [:missing, :stale].include?(category) ? :ok : category }

      expect(categories(result.final_audit, fixture_ids)).to eq(after)
    end

    it 'reports the writes it made and still asks for an operator' do
      mine = result.changes.select { |a| fixture_ids.include?(a.domain_id) || unmatched_keys.include?(a.canonical) }

      expect([mine.map(&:outcome).tally, result.failures, result.attention?])
        .to eq([{ claimed: 8, released: 1 }, [], true])
    end

    it 'changes nothing when run again' do
      before_index = index.hgetall

      again = described_class.new(dry_run: false).call

      expect([again.changes, index.hgetall]).to eq([[], before_index])
    end

    it 'finds the name for another organization afterwards' do
      expect { model.create!("bücher-#{sfx}.com", org_b.objid) }
        .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    end
  end

  describe 'claim outcomes it does not expect' do
    let(:race_name) { "race-ü-#{sfx}.com" }

    before { legacy!(:race, race_name) }

    it 'reports :refused when another record holds the name by the time it claims' do
      with_index(claim_field: ->(_real, _field, _val) { "someone-#{sfx}" })

      result = described_class.new(dry_run: false).call

      expect([outcome_for(result, id_of(:race)), result.attention?]).to eq([:refused, true])
    end

    it 'reports :unverified and releases its claim when the entry reads back differently' do
      with_index(get: ->(real, field) { field == canonical(race_name) ? "someone-#{sfx}" : real.get(field) })

      result = described_class.new(dry_run: false).call

      expect([outcome_for(result, id_of(:race)), index.get(canonical(race_name))]).to eq([:unverified, nil])
    end

    # The audit after the writes decides, whatever the action reported.
    it 'asks for an operator when a skipped claim leaves the record missing' do
      op = described_class.new(dry_run: false)
      allow(op).to receive(:record_exists?).and_wrap_original { |original, id| id == id_of(:race) ? false : original.call(id) }

      result = op.call
      row    = result.final_audit.rows.find { |r| r.domain_id == id_of(:race) }

      expect([outcome_for(result, id_of(:race)), row.category, result.attention?]).to eq([:skipped, :missing, true])
    end
  end

  describe 'an apply where a write raises' do
    let(:failing_name) { "raise-ü-#{sfx}.com" }
    let(:other_name) { "after-ü-#{sfx}.com" }

    before do
      legacy!(:failing, failing_name)
      legacy!(:other, other_name)
    end

    it 'records the error as that action outcome and applies the other actions' do
      failing = canonical(failing_name)
      with_index(
        claim_field: lambda { |real, field, val|
          raise Redis::TimeoutError, 'timed out' if field == failing

          real.claim_field(field, val)
        },
      )

      result = described_class.new(dry_run: false).call
      error  = result.actions.find { |a| a.domain_id == id_of(:failing) }

      expect([error.outcome, error.detail, outcome_for(result, id_of(:other)), index.get(canonical(other_name)), result.attention?])
        .to eq([:error, 'Redis::TimeoutError: timed out', :claimed, id_of(:other), true])
    end
  end

  # A Familia 2.9.x index entry: the identifier stored JSON-quoted.
  describe 'an entry holding a JSON-quoted identifier' do
    let(:name) { "quoted-ü-#{sfx}.com" }

    def put_quoted_entry(key, holder)
      model.dbclient.hset(index.dbkey, key, Familia::JsonSerializer.dump(holder))
      entries_written << [key, holder]
    end

    it 'counts an entry naming the record itself as ok' do
      put_quoted_entry(canonical(name), legacy!(:quoted_own, name))

      expect(categories(audit, [id_of(:quoted_own)])).to eq(id_of(:quoted_own) => :ok)
    end

    it 're-claims an entry naming a deleted record and stores the identifier unquoted' do
      legacy!(:quoted_stale, name)
      put_quoted_entry(canonical(name), "gone-quoted-#{sfx}")

      result = described_class.new(dry_run: false).call

      expect([outcome_for(result, id_of(:quoted_stale)), model.dbclient.hget(index.dbkey, canonical(name))])
        .to eq([:claimed, id_of(:quoted_stale)])
    end
  end
end
