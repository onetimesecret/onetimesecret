# spec/unit/onetime/models/custom_domain/record_for_display_domain_spec.rb
#
# frozen_string_literal: true

# CustomDomain.record_for_display_domain: a lookup by name returns the record
# its index entry names only when that record is stored under the name looked
# up. An entry that names a record stored under another name is refused by
# every lookup (load_by_display_domain, from_display_domain,
# resolve_domain_id), and that record stays reachable under its own name.
#
# Real datastore: the index entries are written and read for real.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, '.record_for_display_domain', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:name_a) { "a-#{suffix}.example.com" }
  let(:name_b) { "b-#{suffix}.example.com" }
  let(:exact_index) { described_class.display_domain_index }
  let(:ascii_index) { described_class.ascii_display_domain_index }
  let(:records) { [] }
  let(:org) { Onetime::Organization.new(display_name: "Lookup #{suffix}").tap(&:save) }

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[record_for_display_domain_spec cleanup] #{ex.class}: #{ex.message}"
    end
    org.destroy! if org.exists?
  end

  def create(name)
    described_class.create!(name, org.objid).tap { |rec| records << rec }
  end

  # Every lookup by name, as identifiers.
  def lookups(name)
    [
      described_class.load_by_display_domain(name)&.identifier,
      described_class.from_display_domain(name)&.identifier,
      described_class.resolve_domain_id(name),
    ]
  end

  it 'returns the record stored under the name' do
    rec = create(name_a)

    expect(lookups(name_a)).to eq([rec.identifier] * 3)
  end

  it 'returns a record stored in Unicode when looked up by its A-label' do
    unicode = "bücher-#{suffix}.example.com"
    rec     = create(unicode)

    expect(lookups(described_class.ascii_display_domain(unicode))).to eq([rec.identifier] * 3)
  end

  it 'refuses an exact index entry that names a record stored under another name' do
    rec_a = create(name_a)
    rec_b = create(name_b)
    exact_index.put(name_a, rec_b.identifier)

    expect([lookups(name_a), lookups(name_b)]).to eq([[nil, nil, nil], [rec_b.identifier] * 3])
  ensure
    exact_index.put(name_a, rec_a.identifier) if rec_a
  end

  it 'refuses an ASCII index entry that names a record stored under another name' do
    rec_a      = create(name_a)
    ascii_name = described_class.ascii_display_domain(name_a)
    exact_index.remove(name_a) # the lookup falls through to the ASCII index
    ascii_index.put(ascii_name, create(name_b).identifier)

    expect(lookups(name_a)).to eq([nil, nil, nil])
  ensure
    exact_index.put(name_a, rec_a.identifier) if rec_a
    ascii_index.put(ascii_name, rec_a.identifier) if rec_a && ascii_name
  end

  it 'returns nil for an entry whose record is gone' do
    exact_index.put(name_a, "gone-#{suffix}")

    expect(lookups(name_a)).to eq([nil, nil, nil])
  ensure
    exact_index.remove(name_a)
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
