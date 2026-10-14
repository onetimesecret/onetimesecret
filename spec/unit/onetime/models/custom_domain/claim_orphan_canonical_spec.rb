# spec/unit/onetime/models/custom_domain/claim_orphan_canonical_spec.rb
#
# frozen_string_literal: true

# CustomDomain.claim_orphaned_domain and canonical_display_domain_index.
#
# create!(adopt_orphan: true) hands an existing record with no organization
# (an orphan) to the registering organization through claim_orphaned_domain.
# Before its
# WATCH/MULTI, that claim enters the record's name into the canonical index
# for the record, the way create! claims a new record's name:
#
# - an orphan registered before the index existed gains an entry;
# - an orphan that already holds its entry keeps it;
# - an orphan whose name another record holds is refused, and stays an orphan;
# - a claim taken here is released when the orphan claim fails, unless an
#   organization holds the record by then.
#
# Verification fields are not part of this and are not asserted on.
#
# Real datastore: the claim is a server-side compare-and-set and the orphan
# claim is a WATCH/MULTI.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, '.claim_orphaned_domain canonical claim', :datastore do
  include LegacyCustomDomainRecords

  let(:suffix) { SecureRandom.hex(4) }
  let(:orphan_name) { "orphan-ü-#{suffix}.com" }
  let(:canonical) { described_class.canonical_display_domain(orphan_name) }
  let(:index) { described_class.canonical_display_domain_index }
  let(:org_a) { Onetime::Organization.new(display_name: "Orphan A #{suffix}").tap(&:save) }
  let(:org_b) { Onetime::Organization.new(display_name: "Orphan B #{suffix}").tap(&:save) }
  let(:legacy) { [] }
  let(:created) { [] }

  # The unit lane boots without the connection pool claim_orphaned_domain
  # pins its WATCH to; hand it a plain client instead (as create_failures_spec
  # does).
  before do
    allow(Onetime).to receive(:with_pinned_dbclient).and_yield(Familia.dbclient)
  end

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[claim_orphan_canonical_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy.each do |id, display|
      # A claimed orphan belongs to an organization now; destroy! removes it
      # from that organization too.
      reload(id)&.destroy!
    rescue StandardError => ex
      warn "[claim_orphan_canonical_spec cleanup] #{ex.class}: #{ex.message}"
    ensure
      remove_legacy_custom_domain(id, display)
    end
    [org_a, org_b].each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[claim_orphan_canonical_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  # An orphan written before the canonical index existed: no org_id, no entry.
  def legacy_orphan(display = orphan_name)
    id = write_legacy_custom_domain(display, org_id: nil)
    legacy << [id, display]
    id
  end

  def reload(id)
    described_class.find_by_identifier(id)
  end

  def register(input, org)
    described_class.create!(input, org.objid, adopt_orphan: true).tap do |rec|
      created << rec unless legacy.any? { |id, _| id == rec.identifier }
    end
  end

  it 'enters an orphan with no entry into the canonical index when an organization claims it' do
    id = legacy_orphan

    claimed = register(canonical, org_b)

    expect([claimed.identifier, reload(id).org_id, index.get(canonical)]).to eq([id, org_b.objid, id])
  end

  it 'keeps the entry of an orphan that already holds it' do
    id = legacy_orphan
    index.put(canonical, id)

    register(orphan_name, org_b)

    expect([reload(id).org_id, index.get(canonical)]).to eq([org_b.objid, id])
  end

  it 'refuses the orphan when another organization record holds its name, and leaves it an orphan' do
    id     = legacy_orphan
    holder = register("holder-#{suffix}.com", org_a)
    index.put(canonical, holder.identifier)

    expect { register(orphan_name, org_b) }.to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    expect([reload(id).org_id.to_s, index.get(canonical)]).to eq(['', holder.identifier])
  ensure
    index.release_field(canonical, holder.identifier) if holder
  end

  it 'refuses the orphan as already registered when a record of the same organization holds its name' do
    legacy_orphan
    holder = register("holder-#{suffix}.com", org_b)
    index.put(canonical, holder.identifier)

    expect { register(orphan_name, org_b) }.to raise_error(Onetime::Problem, 'Domain already registered in your organization')
  ensure
    index.release_field(canonical, holder.identifier) if holder
  end

  it 'releases the claim it took when the organization is gone by the time it assigns it' do
    id       = legacy_orphan
    existing = reload(id)
    allow(Onetime::Organization).to receive(:load).and_call_original
    allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_return(nil)

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }.to raise_error(Onetime::RecordNotFound)
    expect([reload(id).org_id.to_s, index.get(canonical)]).to eq(['', nil])
  end

  it 'releases the claim it took when the record is deleted before its transaction lands' do
    id       = legacy_orphan
    existing = reload(id)
    allow(existing).to receive(:atomic_write) do
      described_class.dbclient.del(existing.dbkey)
      false # EXEC discarded: the WATCHed record changed
    end

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }
      .to raise_error(Onetime::TemporarilyUnavailable)
    expect(index.get(canonical)).to be_nil
  end

  it 'keeps the claim when another organization takes the record first' do
    id       = legacy_orphan
    existing = reload(id)
    allow(existing).to receive(:atomic_write) do
      # The concurrent winner lands between the WATCH and the EXEC.
      described_class.dbclient.hset(existing.dbkey, 'org_id', Familia::JsonSerializer.dump(org_a.objid))
      false # EXEC discarded: the WATCHed record changed
    end

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }
      .to raise_error(Onetime::TemporarilyUnavailable)
    expect([reload(id).org_id, index.get(canonical)]).to eq([org_a.objid, id])
  end

  it 'leaves an entry it did not create when the orphan claim fails' do
    id       = legacy_orphan
    index.put(canonical, id)
    existing = reload(id)
    allow(Onetime::Organization).to receive(:load).and_call_original
    allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_return(nil)

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }.to raise_error(Onetime::RecordNotFound)
    expect(index.get(canonical)).to eq(id)
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
