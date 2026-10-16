# spec/unit/onetime/models/custom_domain/legacy_ascii_backfill_spec.rb
#
# frozen_string_literal: true

# Legacy custom domain records without a ASCII entry, in several stored
# spellings, and what the ASCII index backfill changes for them.
#
# Each fixture is written with raw commands, the way such a record sits in the
# datastore: a JSON-encoded hash, its display_domain_index entry, an instances
# member, and no ASCII entry.
#
# Real datastore: the lookups and the claim are index reads and a server-side
# compare-and-set.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, 'legacy records and the ASCII index backfill', :datastore do
  include LegacyCustomDomainRecords

  let(:suffix) { SecureRandom.hex(4) }
  let(:nfc_name) { "bücher-#{suffix}.com" }
  let(:a_label) { described_class.ascii_display_domain(nfc_name) }
  let(:index) { described_class.ascii_display_domain_index }
  let(:holder_org) { Onetime::Organization.new(display_name: "Legacy holder #{suffix}").tap(&:save) }
  let(:other_org) { Onetime::Organization.new(display_name: "Second org #{suffix}").tap(&:save) }
  let(:legacy_ids) { [] }
  let(:created) { [] }

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[legacy_ascii_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy_ids.each { |id, name| remove_legacy_custom_domain(id, name) }
    [holder_org, other_org].each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[legacy_ascii_backfill_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  # A record as written before the ASCII index existed.
  def write_legacy_record(display_domain, org_id:)
    id = write_legacy_custom_domain(display_domain, org_id: org_id)
    legacy_ids << [id, display_domain]
    id
  end

  def run_backfill
    require 'onetime/operations/domains/ascii_index_backfill'
    Onetime::Operations::Domains::AsciiIndexBackfill.new(dry_run: false).call
  end

  def register(name, org)
    described_class.create!(name, org.objid).tap { |rec| created << rec }
  end

  # The same DNS name as nfc_name, in other stored spellings.
  def spellings
    {
      'decomposed (NFD)' => "bu\u0308cher-#{suffix}.com",
      'fullwidth' => "ｂüｃｈｅｒ-#{suffix}.com",
    }
  end

  describe 'a legacy record without a ASCII entry' do
    it 'shares the A-label of the NFC spelling (fixture sanity)' do
      keys = spellings.values.map { |name| described_class.ascii_display_domain(name) }

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
        it 'has no ASCII entry before the backfill, and is found by its stored name' do
          stored = spellings.fetch(label)
          legacy = write_legacy_record(stored, org_id: holder_org.objid)

          expect(index.get(a_label)).to be_nil
          expect(described_class.load_by_display_domain(stored)&.identifier).to eq(legacy)
        end

        it 'is refused for the A-label after the backfill' do
          legacy = write_legacy_record(spellings.fetch(label), org_id: holder_org.objid)

          run_backfill

          expect { register(a_label, other_org) }
            .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
          expect(index.get(a_label)).to eq(legacy)
        end

        it 'is refused for the NFC spelling after the backfill' do
          write_legacy_record(spellings.fetch(label), org_id: holder_org.objid)

          run_backfill

          expect { register(nfc_name, other_org) }
            .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
        end
      end
    end

    context 'when stored with mixed A-label and Unicode labels' do
      let(:mixed) { "xn--bcher-kva.bücher-#{suffix}.com" }
      let(:full_a_label) { described_class.ascii_display_domain(mixed) }

      it 'has no ASCII entry before the backfill, and is found by its stored name' do
        legacy = write_legacy_record(mixed, org_id: holder_org.objid)

        expect(index.get(full_a_label)).to be_nil
        expect(described_class.load_by_display_domain(mixed)&.identifier).to eq(legacy)
      end

      it 'is refused for the full A-label after the backfill' do
        legacy = write_legacy_record(mixed, org_id: holder_org.objid)

        run_backfill

        expect { register(full_a_label, other_org) }
          .to raise_error(Onetime::Problem, 'Domain is registered to another organization')
        expect(index.get(full_a_label)).to eq(legacy)
      end
    end
  end

  describe 'a legacy record stored as its NFC or A-label spelling' do
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
