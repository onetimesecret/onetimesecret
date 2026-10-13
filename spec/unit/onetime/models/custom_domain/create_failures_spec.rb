# spec/unit/onetime/models/custom_domain/create_failures_spec.rb
#
# frozen_string_literal: true

# CustomDomain.create! failures that are not the caller's input, so they
# must not read as a form error:
#
# - a datastore error is Onetime::TemporarilyUnavailable (503, retry);
# - claiming an orphaned record for an organization that no longer exists
#   is Onetime::RecordNotFound, without the organization's internal id;
# - an orphan claim discarded by a concurrent write (WATCH) is
#   Onetime::TemporarilyUnavailable.
#
# Real datastore; the failures are injected through a delegator on the class
# accessor or a stub on one record, both scoped to the example.

require 'spec_helper'
require 'delegate'
require 'securerandom'

RSpec.describe Onetime::CustomDomain, '.create! failures', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:name) { "failure-#{suffix}.example.com" }
  let(:org) { Onetime::Organization.new(display_name: "Failures #{suffix}").tap(&:save) }
  let(:records) { [] }

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[create_failures_spec cleanup] #{ex.class}: #{ex.message}"
    end
    described_class.canonical_display_domain_index.remove_field(described_class.canonical_display_domain(name))
    org.destroy! if org.exists?
  end

  # A record with no org_id, no owners entry and no organization membership.
  def orphan
    rec = described_class.create!(name, org.objid).tap { |created| records << created }
    rec.remove_from_organization_domains(org)
    Familia.dbclient.hdel(rec.dbkey, 'org_id')
    described_class.owners.remove(rec.to_s)
    described_class.find_by_identifier(rec.identifier)
  end

  it 'reports a datastore error as TemporarilyUnavailable and stores nothing' do
    failing = Class.new(SimpleDelegator) do
      define_method(:claim_field) { |*| raise Redis::CannotConnectError, 'datastore unreachable' }
    end
    allow(described_class).to receive(:canonical_display_domain_index)
      .and_return(failing.new(described_class.canonical_display_domain_index))

    expect { described_class.create!(name, org.objid) }
      .to raise_error(Onetime::TemporarilyUnavailable) { |ex| expect(ex.reason).to eq(:datastore) }
    expect(described_class.display_domain_index.get(name)).to be_nil
  end

  context 'when claiming an orphaned record' do
    # The unit lane boots without the connection pool claim_orphaned_domain
    # pins its WATCH to; hand it a plain client for this example instead.
    before do
      allow(Onetime).to receive(:with_pinned_dbclient) { |&block| block.call(Familia.dbclient) }
    end

    it 'reports an orphan claim for an organization that no longer exists as RecordNotFound, without its id' do
      orphaned   = orphan
      missing_id = "missing-#{suffix}"

      expect { described_class.create!(name, missing_id) }.to raise_error(Onetime::RecordNotFound) { |ex|
        expect([ex.message, ex.message.include?(missing_id)]).to eq(['Organization not found', false])
      }
      expect(described_class.find_by_identifier(orphaned.identifier).org_id.to_s).to eq('')
    end

    it 'reports an orphan claim discarded by a concurrent write as TemporarilyUnavailable' do
      orphaned = orphan
      allow(orphaned).to receive(:atomic_write).and_return(false)

      expect { described_class.claim_orphaned_domain(orphaned, org.objid) }
        .to raise_error(Onetime::TemporarilyUnavailable) { |ex| expect(ex.reason).to eq(:concurrent_write) }
    end
  end
end
