# spec/unit/onetime/models/custom_domain/claim_orphan_ascii_spec.rb
#
# frozen_string_literal: true

# CustomDomain.claim_orphaned_domain and ascii_display_domain_index.
#
# create!(adopt_orphan: true) hands an existing record with no organization
# (an orphan) to the registering organization through claim_orphaned_domain.
# Before its
# WATCH/MULTI, that claim enters the record's name into the ASCII index
# for the record, the way create! claims a new record's name:
#
# - an orphan registered before the index existed gains an entry;
# - an orphan that already holds its entry keeps it;
# - an orphan whose name another record holds is refused, and stays an orphan;
# - a claim taken here stays when adoption fails but the record still exists,
#   even if still orphaned; it is released only if the record is gone and the
#   entry still names it, checked atomically against deletion/recreation.
#
# Verification fields are not part of this and are not asserted on.
#
# Real datastore: the claim is a server-side compare-and-set and the orphan
# claim is a WATCH/MULTI.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, '.claim_orphaned_domain ASCII claim', :datastore do
  include LegacyCustomDomainRecords

  let(:suffix) { SecureRandom.hex(4) }
  let(:orphan_name) { "orphan-ü-#{suffix}.com" }
  let(:ascii_name) { described_class.ascii_display_domain(orphan_name) }
  let(:index) { described_class.ascii_display_domain_index }
  let(:org_a) { Onetime::Organization.new(display_name: "Orphan A #{suffix}").tap(&:save) }
  let(:org_b) { Onetime::Organization.new(display_name: "Orphan B #{suffix}").tap(&:save) }
  let(:legacy) { [] }
  let(:created) { [] }

  # The unit lane boots without the connection pool claim_orphaned_domain
  # pins its WATCH to; hand it a plain client instead (as create_failures_spec
  # does). A block, not and_yield: and_yield refuses callers whose block takes
  # no argument (GuardedConfigWrites, reached from destroy! in the cleanup
  # when an earlier example left a pool installed).
  before do
    allow(Onetime).to receive(:with_pinned_dbclient) { |&block| block.call(Familia.dbclient) }
  end

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[claim_orphan_ascii_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy.each do |id, display|
      # A claimed orphan belongs to an organization now; destroy! removes it
      # from that organization too.
      reload(id)&.destroy!
    rescue StandardError => ex
      warn "[claim_orphan_ascii_spec cleanup] #{ex.class}: #{ex.message}"
    ensure
      remove_legacy_custom_domain(id, display)
    end
    [org_a, org_b].each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[claim_orphan_ascii_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  # An orphan written before the ASCII index existed: no org_id, no entry.
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

  it 'enters an orphan with no entry into the ASCII index when an organization claims it' do
    id = legacy_orphan

    claimed = register(ascii_name, org_b)

    expect([claimed.identifier, reload(id).org_id, index.get(ascii_name)]).to eq([id, org_b.objid, id])
  end

  it 'keeps the entry of an orphan that already holds it' do
    id = legacy_orphan
    index.put(ascii_name, id)

    register(orphan_name, org_b)

    expect([reload(id).org_id, index.get(ascii_name)]).to eq([org_b.objid, id])
  end

  it 'refuses the orphan when another organization record holds its name, and leaves it an orphan' do
    id     = legacy_orphan
    holder = register("holder-#{suffix}.com", org_a)
    index.put(ascii_name, holder.identifier)

    expect { register(orphan_name, org_b) }.to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    expect([reload(id).org_id.to_s, index.get(ascii_name)]).to eq(['', holder.identifier])
  ensure
    index.release_field(ascii_name, holder.identifier) if holder
  end

  it 'refuses the orphan as already registered when a record of the same organization holds its name' do
    legacy_orphan
    holder = register("holder-#{suffix}.com", org_b)
    index.put(ascii_name, holder.identifier)

    expect { register(orphan_name, org_b) }.to raise_error(Onetime::Problem, 'Domain already registered in your organization')
  ensure
    index.release_field(ascii_name, holder.identifier) if holder
  end

  it 'keeps the claim for the live orphan when the organization is gone by the time it assigns it' do
    id       = legacy_orphan
    existing = reload(id)
    allow(Onetime::Organization).to receive(:load).and_call_original
    allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_return(nil)

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }.to raise_error(Onetime::RecordNotFound)
    expect([reload(id).org_id.to_s, index.get(ascii_name)]).to eq(['', id])
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
    expect(index.get(ascii_name)).to be_nil
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
    expect([reload(id).org_id, index.get(ascii_name)]).to eq([org_a.objid, id])
  end

  describe 'an orphan still listed in an organization' do
    it 'refuses the adoption while another organization lists it, and leaves it an orphan' do
      id = legacy_orphan
      reload(id).add_to_organization_domains(org_a)

      expect { register(orphan_name, org_b) }
        .to raise_error(Onetime::Problem, /still listed in the domains of organization #{org_a.extid}.*domains doctor --org #{org_a.extid}`.*--repair/)
      expect([reload(id).org_id.to_s, index.get(ascii_name), org_b.domains.member?(reload(id))]).to eq(['', nil, false])
    end

    it 'adopts it once that listing is removed' do
      id = legacy_orphan
      reload(id).add_to_organization_domains(org_a)
      org_a.remove_domain(reload(id))

      register(orphan_name, org_b)

      expect([reload(id).org_id, org_a.domains.member?(reload(id))]).to eq([org_b.objid, false])
    end

    it 'adopts it when the listing is in the adopting organization' do
      id = legacy_orphan
      reload(id).add_to_organization_domains(org_b)

      register(orphan_name, org_b)

      expect([reload(id).org_id, org_b.domains.member?(reload(id))]).to eq([org_b.objid, true])
    end
  end

  # The claim reads the stored org_id raw (hget) inside its WATCH, and before
  # it in refuse_orphan_listed_elsewhere!.
  # A JSON null or a JSON empty string is no organization, the same as an
  # absent field.
  describe 'an orphan whose stored org_id is an empty JSON value' do
    { 'JSON null' => 'null', 'a JSON empty string' => '""' }.each do |label, raw|
      context "when org_id is stored as #{label}" do
        def raw_orphan(raw)
          id = legacy_orphan
          described_class.dbclient.hset(described_class.dbkey(id), 'org_id', raw)
          id
        end

        it 'adopts it' do
          id = raw_orphan(raw)

          register(orphan_name, org_b)

          expect([reload(id).org_id, index.get(ascii_name)]).to eq([org_b.objid, id])
        end

        it 'refuses the adoption while another organization lists it' do
          id = raw_orphan(raw)
          reload(id).add_to_organization_domains(org_a)

          expect { register(orphan_name, org_b) }
            .to raise_error(Onetime::Problem, /still listed in the domains of organization #{org_a.extid}/)
          expect(described_class.dbclient.hget(described_class.dbkey(id), 'org_id')).to eq(raw)
        end

        it 'keeps the claim for the live orphan when the organization is gone by the time it assigns it' do
          id       = raw_orphan(raw)
          existing = reload(id)
          allow(Onetime::Organization).to receive(:load).and_call_original
          allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_return(nil)

          expect { described_class.claim_orphaned_domain(existing, org_b.objid) }.to raise_error(Onetime::RecordNotFound)
          expect([described_class.dbclient.hget(described_class.dbkey(id), 'org_id'), index.get(ascii_name)]).to eq([raw, id])
        end
      end
    end
  end

  [
    ['decomposed Unicode', "orphan-u\u0308"],
    ['fullwidth Unicode', 'ｏｒｐｈａｎ'],
  ].each do |spelling, prefix|
    context "with a legacy #{spelling} name" do
      let(:orphan_name) { "#{prefix}-#{suffix}.com" }

      it 'keeps the ASCII claim after successful adoption despite a stale cleanup org_id read' do
        id       = legacy_orphan
        existing = reload(id)
        allow(existing).to receive(:atomic_write).and_return(false)
        allow(described_class).to receive(:release_orphan_ascii_claim).and_wrap_original do |cleanup, record, key|
          # Deterministically model the baseline's split check/release: its
          # org_id read is empty, then a real adoption commits with the same ID.
          # Only the losing request's cleanup sees that stale org_id snapshot.
          stale_org_id = record.hget(:org_id)
          winner = register(orphan_name, org_a)
          expect(winner.identifier).to eq(id)
          allow(record).to receive(:hget).with(:org_id).and_return(stale_org_id)
          cleanup.call(record, key)
        end

        expect { described_class.claim_orphaned_domain(existing, org_b.objid) }
          .to raise_error(Onetime::TemporarilyUnavailable)
        expect([reload(id).org_id, index.get(ascii_name)]).to eq([org_a.objid, id])
        expect { register(ascii_name, org_b) }
          .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
      end
    end
  end

  it 'keeps the claim for a record recreated with the same ID after a stale absence observation' do
    id       = legacy_orphan
    existing = reload(id)
    index.put(ascii_name, id)
    client = described_class.dbclient
    fields = client.hgetall(existing.dbkey)
    client.del(existing.dbkey)
    absent = existing.exists?
    expect(absent).to be(false)

    # Recreate before cleanup; a separate EXISTS followed by release_field
    # would trust the stale absence and remove this live record's claim.
    client.hset(existing.dbkey, fields)
    allow(existing).to receive(:exists?).and_return(absent)
    described_class.send(:release_orphan_ascii_claim, existing, ascii_name)

    expect([reload(id).identifier, index.get(ascii_name)]).to eq([id, id])
  end

  it 'keeps the replacement claim when deletion and registration precede failed adoption cleanup' do
    id          = legacy_orphan
    existing    = reload(id)
    replacement = nil
    allow(existing).to receive(:atomic_write) do
      existing.destroy!
      replacement = register(ascii_name, org_a)
      false # EXEC discarded: the WATCHed record was deleted
    end

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }
      .to raise_error(Onetime::TemporarilyUnavailable)
    expect(replacement.identifier).not_to eq(id)
    expect([reload(id), index.get(ascii_name)]).to eq([nil, replacement.identifier])
  end

  it 'leaves an entry it did not create when the orphan claim fails' do
    id       = legacy_orphan
    index.put(ascii_name, id)
    existing = reload(id)
    allow(Onetime::Organization).to receive(:load).and_call_original
    allow(Onetime::Organization).to receive(:load).with(org_b.objid).and_return(nil)

    expect { described_class.claim_orphaned_domain(existing, org_b.objid) }.to raise_error(Onetime::RecordNotFound)
    expect(index.get(ascii_name)).to eq(id)
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
