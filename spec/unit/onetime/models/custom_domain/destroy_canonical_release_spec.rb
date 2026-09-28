# spec/unit/onetime/models/custom_domain/destroy_canonical_release_spec.rb
#
# frozen_string_literal: true

# CustomDomain#destroy! releases the canonical display-domain claim from inside
# Familia's destroy transaction.
#
# The canonical gate (canonical_display_domain_index) folds the Unicode and
# A-label spellings of a name onto one field. It is app-managed, not a declared
# Familia index, so destroy! has to release it itself. Releasing after the
# MULTI would let a Redis failure in between leave a claim naming a record that
# no longer exists; create! reads such a claim as another organization's
# in-flight registration and refuses both spellings. The release is queued in
# the same MULTI as the record delete (CustomDomain#remove_from_class_indexes!)
# and stays ownership-checked: a claim held by a different identifier is left
# alone.
#
# Real datastore: the release is an EVAL queued by Familia's transaction, so
# there is nothing to prove against doubles. The class accessor for the index
# is stubbed to return a delegator that records each release together with
# whether a Familia transaction was open at the time; RSpec restores the
# accessor after each example.

require 'spec_helper'
require 'delegate'
require 'securerandom'

RSpec.describe Onetime::CustomDomain, '#destroy! canonical release', :datastore do
  let(:index) { described_class.canonical_display_domain_index }
  let(:releases) { [] }
  let(:records) { [] }
  let(:suffix) { SecureRandom.hex(4) }
  # The Unicode label has to be in the registrable domain: a Unicode subdomain
  # label is refused at creation (it would end up in the TXT record host).
  let(:unicode_name) { "bücher-#{suffix}.com" }

  before do
    allow(described_class).to receive(:canonical_display_domain_index).and_return(recording_index)
  end

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[destroy_canonical_release_spec cleanup] #{ex.class}: #{ex.message}"
    end
    index.remove_field(canonical)
  end

  def canonical
    described_class.canonical_display_domain(unicode_name)
  end

  # Delegates to the real index and records each release with whether a
  # Familia transaction was open when it ran.
  def recording_index
    calls = releases
    Class.new(SimpleDelegator) do
      define_method(:release_field) do |field, val|
        ret = super(field, val)
        calls << { field: field, val: val, in_transaction: !Fiber[:familia_transaction].nil?, ret: ret }
        ret
      end
    end.new(index)
  end

  def create_domain
    rec = described_class.create!(unicode_name, "org-#{suffix}")
    records << rec
    rec
  end

  it 'claims the A-label form on create! (sanity)' do
    domain = create_domain

    expect([canonical.start_with?('xn--'), index.get(canonical)]).to eq([true, domain.identifier])
  end

  it 'releases the claim inside the destroy transaction' do
    domain = create_domain
    releases.clear

    domain.destroy!

    expect([index.get(canonical), described_class.find_by_identifier(domain.identifier)]).to eq([nil, nil])
    expect(releases.map { |c| c.values_at(:field, :val, :in_transaction) })
      .to eq([[canonical, domain.identifier, true]])
    # Queued in the MULTI, so the release returns a future rather than a count.
    expect(releases.first[:ret].class.name).to eq('Redis::Future')
  end

  it 'lets both spellings be registered again after destroy!' do
    create_domain.destroy!

    again = create_domain

    expect(index.get(canonical)).to eq(again.identifier)
  end

  it 'leaves a claim held by a different identifier alone' do
    domain           = create_domain
    index[canonical] = "other-#{suffix}"

    domain.destroy!

    expect([index.get(canonical), described_class.find_by_identifier(domain.identifier)])
      .to eq(["other-#{suffix}", nil])
  end
end
