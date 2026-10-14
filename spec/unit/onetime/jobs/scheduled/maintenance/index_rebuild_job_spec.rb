# spec/unit/onetime/jobs/scheduled/maintenance/index_rebuild_job_spec.rb
#
# frozen_string_literal: true

# IndexRebuildJob against records written the normal way.
#
# Familia v2 stores a Horreum string field JSON-encoded ("\"a@b.example\"")
# but keys its unique indexes by the decoded value (field_value.to_s) and
# stores the identifier raw. The job must compare in those same terms, or it
# reports every healthy entry as broken and, with auto_repair on, moves each
# one to a key no lookup ever reads.
#
# Real datastore (the unit lane's Valkey). The job walks the whole index and
# every record of the class, so other examples' records can be present: the
# audit assertions compare against a baseline taken before seeding, and the
# repair assertions look only at this example's own entries. Every record is
# destroyed and every index field this spec could have written is deleted in
# `after`; nothing is flushed.
#
# Run with: tests/lanes/run unit --only spec/unit/onetime/jobs/scheduled/maintenance/index_rebuild_job_spec.rb

require 'spec_helper'
require 'json'
require 'securerandom'
require 'onetime/jobs/scheduled/maintenance/index_rebuild_job'

RSpec.describe Onetime::Jobs::Scheduled::Maintenance::IndexRebuildJob do
  let(:redis) { Familia.dbclient }
  let(:suffix) { SecureRandom.hex(4) }
  let(:records) { [] }

  # label => [model, index accessor, indexed field]
  let(:index_models) do
    {
      'customer_email' => [Onetime::Customer, :email_index, :email],
      'org_contact_email' => [Onetime::Organization, :contact_email_index, :contact_email],
      'domain_display' => [Onetime::CustomDomain, :display_domain_index, :display_domain],
    }
  end

  # Index fields this example may have written, deleted in `after` in raw and
  # JSON-quoted form whatever the job did with them.
  let(:touched_fields) { Hash.new { |hash, key| hash[key] = [] } }

  def index_key(label)
    described_class::INDEXES.find { |row| row.first == label }[1]
  end

  def track(record)
    records << record
    record
  end

  def touch(label, field)
    touched_fields[label] << field
    field
  end

  def create_customer(tag)
    email = touch('customer_email', "idx-#{tag}-#{suffix}@example.com")
    track(Onetime::Customer.create!(email: email))
  end

  def create_org(owner, tag)
    email = touch('org_contact_email', "idx-org-#{tag}-#{suffix}@example.com")
    track(Onetime::Organization.create!("Index #{tag} #{suffix}", owner, email))
  end

  def create_domain(org, tag)
    name = touch('domain_display', "idx-#{tag}-#{suffix}.example.com")
    track(Onetime::CustomDomain.create!(name, org.objid))
  end

  # The job's own entry point, with auto_repair forced for the run.
  def run_job(repair:)
    allow(described_class).to receive(:auto_repair?).with(described_class::JOB_KEY).and_return(repair)
    report = {}
    described_class.send(:reconcile_indexes, report)
    report[:indexes]
  end

  def counts(report, key)
    report.transform_values { |stats| stats[key] }
  end

  def delta(before, after, key)
    after.to_h { |label, stats| [label, stats[key] - before[label][key]] }
  end

  def zero_for_every_index
    index_models.keys.to_h { |label| [label, 0] }
  end

  after do
    records.reverse_each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[index_rebuild_job_spec cleanup] #{ex.class}: #{ex.message}"
    end
    touched_fields.each do |label, fields|
      keys = fields.flat_map { |field| [field, JSON.generate(field)] }
      redis.hdel(index_key(label), keys) unless keys.empty?
    end
    # destroy! releases the domain's other claim; this covers a failed destroy.
    touched_fields['domain_display'].each do |name|
      Onetime::CustomDomain.canonical_display_domain_index.remove_field(Onetime::CustomDomain.canonical_display_domain(name))
    end
  end

  it 'names the index each model declares, under the prefix its records use' do
    index_models.each do |label, (model, accessor, field)|
      _, key, prefix, field_name = described_class::INDEXES.find { |row| row.first == label }
      expect([key, prefix, field_name]).to eq([model.public_send(accessor).dbkey, model.prefix.to_s, field.to_s])
    end
  end

  context 'with records written through the model API' do
    let(:baseline) { run_job(repair: false) }
    let(:owner) { create_customer('owner') }
    let(:member) { create_customer('member') }
    let(:org) { create_org(owner, 'acme') }
    let(:domains) { [create_domain(org, 'a'), create_domain(org, 'b')] }

    # [label, raw index field, identifier] for every seeded entry
    let(:seeded) do
      [
        ['customer_email', owner.email, owner.objid],
        ['customer_email', member.email, member.objid],
        ['org_contact_email', org.contact_email, org.objid],
        *domains.map { |dom| ['domain_display', dom.display_domain, dom.identifier] },
      ]
    end

    before do
      baseline
      seeded
    end

    it 'stores what the job reads: JSON-encoded record fields, raw index keys and identifiers' do
      expect(redis.hget(owner.dbkey, 'email')).to eq(JSON.generate(owner.email))
      expect(redis.hget(index_key('customer_email'), owner.email)).to eq(owner.objid)
    end

    it 'reports no stale, mismatched or missing entries in audit mode' do
      after_seed = run_job(repair: false)

      expect(delta(baseline, after_seed, :entries_checked).values_at('customer_email', 'org_contact_email', 'domain_display'))
        .to eq([2, 1, 2])
      expect(delta(baseline, after_seed, :mismatched_entries)).to eq(zero_for_every_index)
      expect(delta(baseline, after_seed, :stale_entries)).to eq(zero_for_every_index)
      expect(delta(baseline, after_seed, :missing_entries)).to eq(zero_for_every_index)
      expect(delta(baseline, after_seed, :conflicting_entries)).to eq(zero_for_every_index)
    end

    it 'leaves every entry under its raw key with its identifier when repairing' do
      run_job(repair: true)

      seeded.each do |label, field, identifier|
        key = index_key(label)
        expect([label, field, redis.hget(key, field)]).to eq([label, field, identifier])
        expect([label, field, redis.hexists(key, JSON.generate(field))]).to eq([label, field, false])
      end
    end

    it 'keeps the finders working after a repair run' do
      run_job(repair: true)

      expect(Onetime::Customer.find_by_email(owner.email)&.objid).to eq(owner.objid)
      expect(Onetime::Customer.find_by_email(member.email)&.objid).to eq(member.objid)
      expect(Onetime::Customer.email_exists?(member.email)).to be(true)
      expect(Onetime::Organization.find_by_contact_email(org.contact_email)&.objid).to eq(org.objid)
      domains.each do |dom|
        expect(Onetime::CustomDomain.find_by_display_domain(dom.display_domain)&.identifier).to eq(dom.identifier)
      end
    end

    it 'repairs nothing on a second repair run' do
      run_job(repair: true)
      second = run_job(repair: true)

      expect(counts(second, :repaired_mismatched)).to eq(zero_for_every_index)
      expect(counts(second, :repaired_missing)).to eq(zero_for_every_index)
    end
  end

  context 'with an index value still in the pre-20260606_01 JSON-quoted form' do
    let(:customer) { create_customer('legacy') }
    let(:key) { index_key('customer_email') }
    let(:baseline) { run_job(repair: false) }

    before do
      customer
      baseline
      redis.hset(key, customer.email, JSON.generate(customer.objid))
    end

    it 'treats the quoted value as the identifier in audit mode' do
      after_quote = run_job(repair: false)

      expect(delta(baseline, after_quote, :stale_entries)['customer_email']).to eq(0)
      expect(delta(baseline, after_quote, :mismatched_entries)['customer_email']).to eq(0)
      expect(delta(baseline, after_quote, :missing_entries)['customer_email']).to eq(0)
    end

    it 'keeps the entry when repairing' do
      run_job(repair: true)

      expect(redis.hget(key, customer.email)).to eq(customer.objid).or eq(JSON.generate(customer.objid))
      expect(Onetime::Customer.find_by_email(customer.email)&.objid).to eq(customer.objid)
    end
  end

  context 'with an entry whose record no longer exists' do
    let(:key) { index_key('customer_email') }
    let(:gone_email) { touch('customer_email', "idx-gone-#{suffix}@example.com") }
    let(:baseline) { run_job(repair: false) }

    before do
      baseline
      redis.hset(key, gone_email, "gone#{suffix}")
    end

    it 'reports it as stale in audit mode' do
      expect(delta(baseline, run_job(repair: false), :stale_entries)['customer_email']).to eq(1)
      expect(redis.hget(key, gone_email)).to eq("gone#{suffix}")
    end

    it 'removes it when repairing' do
      run_job(repair: true)

      expect(redis.hexists(key, gone_email)).to be(false)
    end
  end

  context 'with a record that has no index entry' do
    let(:key) { index_key('customer_email') }
    let(:customer) { create_customer('unindexed') }
    let(:baseline) { run_job(repair: false) }

    before do
      customer
      baseline
      redis.hdel(key, customer.email)
    end

    it 'reports it as missing in audit mode' do
      expect(delta(baseline, run_job(repair: false), :missing_entries)['customer_email']).to eq(1)
    end

    it 'adds it under the raw key with the raw identifier when repairing' do
      run_job(repair: true)

      expect(redis.hget(key, customer.email)).to eq(customer.objid)
      expect(redis.hexists(key, JSON.generate(customer.email))).to be(false)
      expect(Onetime::Customer.find_by_email(customer.email)&.objid).to eq(customer.objid)
    end
  end

  context 'with an entry left at a value the record no longer holds' do
    let(:key) { index_key('customer_email') }
    let(:customer) { create_customer('renamed') }
    let(:old_email) { touch('customer_email', "idx-old-#{suffix}@example.com") }
    let(:baseline) { run_job(repair: false) }

    before do
      customer
      baseline
      redis.hset(key, old_email, customer.objid)
    end

    it 'reports it as mismatched in audit mode' do
      expect(delta(baseline, run_job(repair: false), :mismatched_entries)['customer_email']).to eq(1)
    end

    it 'removes the old key and keeps the current one raw when repairing' do
      run_job(repair: true)

      expect(redis.hexists(key, old_email)).to be(false)
      expect(redis.hget(key, customer.email)).to eq(customer.objid)
      expect(redis.hexists(key, JSON.generate(customer.email))).to be(false)
    end
  end

  context 'with a record whose value the index assigns to another record' do
    let(:key) { index_key('customer_email') }
    let(:holder) { create_customer('holder') }
    let(:other) { create_customer('other') }
    let(:baseline) { run_job(repair: false) }

    before do
      holder
      other
      baseline
      redis.hdel(key, other.email)
      redis.hset(other.dbkey, 'email', JSON.generate(holder.email))
    end

    it 'reports it as a conflict, not as missing, in audit mode' do
      after_edit = run_job(repair: false)

      expect(delta(baseline, after_edit, :conflicting_entries)['customer_email']).to eq(1)
      expect(delta(baseline, after_edit, :missing_entries)['customer_email']).to eq(0)
    end

    it 'leaves the entry with the record that holds it when repairing' do
      report = run_job(repair: true)

      expect(redis.hget(key, holder.email)).to eq(holder.objid)
      expect(report['customer_email'][:conflicting_entries] - baseline['customer_email'][:conflicting_entries]).to eq(1)
    end
  end

  context 'after a repair run that moved entries to JSON-quoted keys' do
    let(:key) { index_key('customer_email') }
    let(:customer) { create_customer('requoted') }

    before do
      customer
      redis.hdel(key, customer.email)
      redis.hset(key, JSON.generate(customer.email), customer.objid)
    end

    it 'restores the raw key and drops the quoted one when repairing' do
      run_job(repair: true)

      expect(redis.hget(key, customer.email)).to eq(customer.objid)
      expect(redis.hexists(key, JSON.generate(customer.email))).to be(false)
      expect(Onetime::Customer.find_by_email(customer.email)&.objid).to eq(customer.objid)
    end
  end
end
