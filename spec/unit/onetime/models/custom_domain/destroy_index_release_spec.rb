# spec/unit/onetime/models/custom_domain/destroy_index_release_spec.rb
#
# frozen_string_literal: true

# CustomDomain#destroy! releases the display_domain_index and
# ascii_display_domain_index entries under the name as stored, whatever
# the copy being destroyed holds in memory, and only entries that name the
# record (ownership-checked).
#
# Real datastore: the releases are server-side compare-and-delete.

require 'spec_helper'
require 'securerandom'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, '#destroy! index release', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:name) { "bücher-#{suffix}.example.com" } # the exact and ASCII keys differ
  let(:ascii_name) { described_class.ascii_display_domain(name) }
  let(:exact_index) { described_class.display_domain_index }
  let(:ascii_index) { described_class.ascii_display_domain_index }
  let(:records) { [] }
  let(:org) { Onetime::Organization.new(display_name: "Destroy #{suffix}").tap(&:save) }

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[destroy_index_release_spec cleanup] #{ex.class}: #{ex.message}"
    end
    exact_index.remove(name)
    ascii_index.remove_field(ascii_name)
    org.destroy! if org.exists?
  end

  def create(name)
    described_class.create!(name, org.objid).tap { |rec| records << rec }
  end

  def entries
    [exact_index.get(name), ascii_index.get(ascii_name)]
  end

  it 'releases the entries under the stored name when the copy holds another name in memory' do
    rec                 = create(name)
    copy                = described_class.find_by_identifier(rec.identifier)
    copy.display_domain = "other-#{suffix}.example.com"

    copy.destroy!

    expect([rec.exists?, entries]).to eq([false, [nil, nil]])
  end

  it 'releases the entries under the stored name when the copy has no name in memory' do
    rec = create(name)

    described_class.new(objid: rec.identifier).destroy!

    expect([rec.exists?, entries]).to eq([false, [nil, nil]])
  end

  it 'leaves the entries of the record they name when a shadow under the same name is destroyed' do
    survivor = create(name)
    exact_index.remove(name)
    ascii_index.remove_field(ascii_name)
    shadow   = described_class.new(display_domain: name, org_id: org.objid).tap { |rec| records << rec }
    shadow.save
    exact_index.put(name, survivor.identifier)
    ascii_index.put(ascii_name, survivor.identifier)

    shadow.destroy!

    expect([shadow.exists?, entries]).to eq([false, [survivor.identifier] * 2])
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
