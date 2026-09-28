# spec/unit/onetime/custom_domain_create_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::CustomDomain, '.create!' do
  let(:unicode_name) { 'bücher.example.com' }
  let(:ascii_name) { 'xn--bcher-kva.example.com' }
  let(:org_id) { 'org-test-001' }
  let(:harness) { build_harness }

  before { stub_creation_dependencies }

  # The preflight lookups are stubbed to miss (stub_creation_dependencies), so
  # the second create never sees the first record: the deterministic stand-in
  # for two requests racing past the preflight. Only the canonical claim can
  # then refuse the duplicate; a check-then-write regression would admit both.
  it 'admits only one Unicode/A-label request after simulated concurrent preflight misses' do
    results = attempt_both_creates

    expect(race_summary(results)).to eq(expected_race_summary)
  end

  context 'with legacy Unicode and A-label records' do
    let(:display_index) { instance_double(Familia::HashKey) }

    before do
      allow(described_class).to receive(:display_domain_index).and_return(display_index)
      allow(display_index).to receive(:get) do |key|
        {
          unicode_name => 'legacy-unicode-id',
          ascii_name => 'legacy-ascii-id',
        }[key]
      end
    end

    it 'returns the exact Unicode record before its A-label alias' do
      expect(described_class.display_domain_id_for(unicode_name)).to eq('legacy-unicode-id')
    end

    it 'returns the exact A-label record before its Unicode alias' do
      expect(described_class.display_domain_id_for(ascii_name)).to eq('legacy-ascii-id')
    end
  end

  context 'with a decomposed Unicode registration' do
    let(:unicode_name) { "bu\u0308cher.example.com" }
    let(:display_index) { instance_double(Familia::HashKey) }

    before do
      allow(described_class).to receive(:display_domain_index).and_return(display_index)
      allow(display_index).to receive(:get).and_return(nil)
      allow(harness.fetch(:canonical_index)).to receive(:get) do |key|
        harness.fetch(:claims)[key]
      end
    end

    it 'resolves the created record by its A-label and NFC spelling' do
      domain = described_class.create!(unicode_name, org_id)

      expect(described_class.display_domain_id_for(ascii_name)).to eq(domain.identifier)
      expect(described_class.display_domain_id_for('bücher.example.com')).to eq(domain.identifier)
    end

    it 'does not resolve a crafted A-label through the normalized Unicode spelling' do
      described_class.create!(unicode_name, org_id)

      expect(described_class.display_domain_id_for('xn--bucher-xyd.example.com')).to be_nil
    end

    it 'does not swallow canonical index failures' do
      allow(harness.fetch(:canonical_index)).to receive(:get).and_raise(Redis::BaseError)

      expect { described_class.display_domain_id_for(ascii_name) }.to raise_error(Redis::BaseError)
    end
  end

  def build_harness
    save_ids = []
    {
      canonical_index: instance_double(Familia::HashKey, release_field: 1),
      instances: instance_double(Familia::SortedSet, add: true),
      claims: {},
      claim_fields: [],
      save_ids: save_ids,
      unicode_domain: domain_double(unicode_name, 'domain-unicode', save_ids),
      ascii_domain: domain_double(ascii_name, 'domain-ascii', save_ids),
    }
  end

  def domain_double(display_domain, identifier, save_ids)
    domain = instance_double(
      described_class,
      display_domain: display_domain,
      identifier: identifier,
      org_id: org_id,
      generate_txt_validation_record: true,
      save: true,
      to_s: identifier,
    )
    allow(domain).to receive(:save) do
      save_ids << identifier
      true
    end
    domain
  end

  def stub_creation_dependencies
    stub_canonical_claim
    allow(described_class).to receive(:parse) do |input, _org_id|
      input == unicode_name ? harness.fetch(:unicode_domain) : harness.fetch(:ascii_domain)
    end
    allow(described_class).to receive_messages(
      overlaps_canonical_domain?: false,
      load_by_display_domain: nil,
      find_by_identifier: nil,
      canonical_display_domain_index: harness.fetch(:canonical_index),
      instances: harness.fetch(:instances),
      record_owner: nil,
      bootstrap_per_domain_configs: nil,
    )
    allow(Onetime::Organization).to receive(:load).and_return(nil)
  end

  def stub_canonical_claim
    allow(harness.fetch(:canonical_index)).to receive(:claim_field) do |field, identifier|
      harness.fetch(:claim_fields) << field
      claims = harness.fetch(:claims)
      next claims.fetch(field) if claims.key?(field)

      claims[field] = identifier
      :created
    end
  end

  def attempt_both_creates
    [unicode_name, ascii_name].map do |name|
      described_class.create!(name, org_id)
    rescue StandardError => ex
      ex
    end
  end

  def race_summary(results)
    {
      claim_fields: harness.fetch(:claim_fields),
      successful_creates: results.count { |result| !result.is_a?(StandardError) },
      duplicate_refusals: results.count { |result| result.is_a?(Onetime::Problem) },
      saved_records: harness.fetch(:save_ids),
    }
  end

  def expected_race_summary
    {
      claim_fields: [ascii_name, ascii_name],
      successful_creates: 1,
      duplicate_refusals: 1,
      saved_records: [harness.fetch(:claims).fetch(ascii_name)],
    }
  end
end
