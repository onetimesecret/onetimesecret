# spec/unit/onetime/models/custom_domain/legacy_canonical_backfill_spec.rb
#
# frozen_string_literal: true

# Records registered before canonical_display_domain_index existed, and what
# the canonical index backfill changes for them.
#
# create! refuses a name when its pre-check (load_by_display_domain) finds an
# existing record. That lookup tries the name as given, its A-label, and its
# NFC Unicode form against display_domain_index, then the canonical index. A
# record written before the canonical index existed is only in
# display_domain_index, under its stored spelling, so the pre-check finds it
# when that spelling is one of the derived keys: the A-label, the NFC form, or
# plain ASCII. Stored in any other spelling of the same DNS name (decomposed,
# fullwidth, mixed A-label and Unicode labels), it is found only once the
# backfill has entered it into the canonical index.
#
# Each fixture is written with raw commands, the way such a record sits in the
# datastore: a JSON-encoded hash, its display_domain_index entry, an instances
# member, and no canonical entry.
#
# Real datastore: the lookups and the claim are index reads and a server-side
# compare-and-set.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, 'legacy records and the canonical index backfill', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:nfc_name) { "bücher-#{suffix}.com" }
  let(:a_label) { described_class.canonical_display_domain(nfc_name) }
  let(:index) { described_class.canonical_display_domain_index }
  let(:holder_org) { Onetime::Organization.new(display_name: "Legacy holder #{suffix}").tap(&:save) }
  let(:other_org) { Onetime::Organization.new(display_name: "Second org #{suffix}").tap(&:save) }
  let(:legacy_ids) { [] }
  let(:created) { [] }
  let(:claimed_names) { [] }

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[legacy_canonical_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy_ids.each { |id, name| remove_legacy_record(id, name) }
    claimed_names.each { |name| index.remove_field(name) }
    [holder_org, other_org].each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[legacy_canonical_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  def client
    described_class.dbclient
  end

  # A record as written before the canonical index existed.
  def write_legacy_record(display_domain, org_id:)
    id     = SecureRandom.uuid_v7
    now    = Familia.now.to_i
    fields = {
      'objid' => id,
      'display_domain' => display_domain,
      'org_id' => org_id,
      'created' => now,
      'updated' => now,
    }.transform_values { |value| Familia::JsonSerializer.dump(value) }

    client.hset(described_class.dbkey(id), fields)
    client.hset(described_class.display_domain_index.dbkey, display_domain, id)
    client.zadd(described_class.instances.dbkey, now, id)
    legacy_ids << [id, display_domain]
    claimed_names << described_class.canonical_display_domain(display_domain)
    id
  end

  def remove_legacy_record(id, display_domain)
    client.del(described_class.dbkey(id))
    described_class.display_domain_index.release_field(display_domain, id)
    client.zrem(described_class.instances.dbkey, id)
  end

  def run_backfill
    require 'onetime/operations/domains/canonical_index_backfill'
    Onetime::Operations::Domains::CanonicalIndexBackfill.new(dry_run: false).call
  end

  def register(name, org)
    described_class.create!(name, org.objid).tap { |rec| created << rec }
  end

  # The same DNS name as nfc_name, in spellings the pre-check does not derive.
  def spellings
    {
      'decomposed (NFD)' => "bücher-#{suffix}.com",
      'fullwidth' => "ｂüｃｈｅｒ-#{suffix}.com",
    }
  end

  describe 'a legacy record in a spelling the pre-check does not derive' do
    it 'shares the A-label of the NFC spelling (fixture sanity)' do
      keys = spellings.values.map { |name| described_class.canonical_display_domain(name) }

      expect(keys.uniq).to eq([a_label])
    end

    it 'is still found by its own stored spelling' do
      nfd    = spellings.fetch('decomposed (NFD)')
      legacy = write_legacy_record(nfd, org_id: holder_org.objid)

      expect(described_class.load_by_display_domain(nfd)&.identifier).to eq(legacy)
    end

    [
      'decomposed (NFD)',
      'fullwidth',
    ].each do |label|
      context "when stored #{label}" do
        it 'admits a second record for the A-label from another organization while no backfill has run' do
          stored = spellings.fetch(label)
          legacy = write_legacy_record(stored, org_id: holder_org.objid)

          second = register(a_label, other_org)
          claimed_names << a_label

          observed = [
            second.identifier == legacy,
            described_class.from_display_domain(a_label)&.identifier == second.identifier,
            described_class.load_by_display_domain(stored)&.identifier == legacy,
          ]
          expect(observed).to eq([false, true, true])
        end

        it 'refuses the A-label from another organization after the backfill' do
          legacy = write_legacy_record(spellings.fetch(label), org_id: holder_org.objid)

          run_backfill

          expect { register(a_label, other_org) }
            .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
          expect(index.get(a_label)).to eq(legacy)
        end

        it 'refuses the NFC spelling from another organization after the backfill' do
          write_legacy_record(spellings.fetch(label), org_id: holder_org.objid)

          run_backfill

          expect { register(nfc_name, other_org) }
            .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
        end
      end
    end

    context 'when stored with mixed A-label and Unicode labels' do
      let(:mixed) { "xn--bcher-kva.bücher-#{suffix}.com" }
      let(:full_a_label) { described_class.canonical_display_domain(mixed) }

      it 'admits a second record for the full A-label from another organization while no backfill has run' do
        legacy = write_legacy_record(mixed, org_id: holder_org.objid)

        second = register(full_a_label, other_org)
        claimed_names << full_a_label

        expect([full_a_label.ascii_only?, second.identifier == legacy]).to eq([true, false])
      end

      it 'refuses the full A-label from another organization after the backfill' do
        legacy = write_legacy_record(mixed, org_id: holder_org.objid)

        run_backfill

        expect { register(full_a_label, other_org) }
          .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
        expect(index.get(full_a_label)).to eq(legacy)
      end
    end
  end

  # Controls: these spellings are among the pre-check's derived keys, so the
  # existing record is found without a canonical entry.
  describe 'a legacy record stored in a spelling the pre-check derives' do
    it 'refuses the A-label against a legacy NFC record without the backfill' do
      write_legacy_record(nfc_name, org_id: holder_org.objid)

      expect { register(a_label, other_org) }
        .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    end

    it 'refuses the NFC spelling against a legacy A-label record without the backfill' do
      write_legacy_record(a_label, org_id: holder_org.objid)

      expect { register(nfc_name, other_org) }
        .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    end

    it 'refuses the A-label against a legacy A-label record without the backfill' do
      write_legacy_record(a_label, org_id: holder_org.objid)

      expect { register(a_label, other_org) }
        .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
