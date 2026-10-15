# spec/unit/onetime/operations/verify_domain_orphan_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::VerifyDomain and a record with no organization.
#
# Such a record is never served, so verifying it has nothing to give. It is
# skipped: no ownership check, no status check, nothing written, and the
# result says so. This also covers a copy loaded while the record had no
# organization and used after an operator adopted it: the adoption reset the
# record's verification, and a write from the old copy would undo that reset.
#
# Real datastore: the adoption is a WATCH/MULTI, and the examples compare
# what is stored before and after.

require 'spec_helper'
require 'securerandom'
require 'onetime/operations/verify_domain'

RSpec.describe Onetime::Operations::VerifyDomain, 'and a record with no organization', :datastore do
  include LegacyCustomDomainRecords

  let(:model) { Onetime::CustomDomain }
  let(:suffix) { SecureRandom.hex(4) }
  let(:org) { Onetime::Organization.new(display_name: "Verify orphan #{suffix}").tap(&:save) }
  let(:legacy) { [] }
  let(:created) { [] }

  # A strategy that would verify and mark resolving any domain it is asked
  # about, so a write that should not happen shows in the stored record.
  let(:strategy) do
    instance_double(
      Onetime::DomainValidation::BaseStrategy,
      validate_ownership: { validated: true, message: 'TXT record matches', data: { 'txt' => 'match' } },
      check_status: { ready: true, has_ssl: true, is_resolving: true, data: { 'status' => 'ACTIVE_SSL' } },
      proves_ownership?: true,
      bulk_rate_limit: 0,
    )
  end

  # The unit lane boots without the connection pool claim_orphaned_domain
  # pins its WATCH to; hand it a plain client instead. A block, not and_yield
  # (see claim_orphan_canonical_spec).
  before do
    allow(Onetime).to receive(:with_pinned_dbclient) { |&block| block.call(Familia.dbclient) }
  end

  after do
    created.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[verify_domain_orphan_spec cleanup] #{ex.class}: #{ex.message}"
    end
    legacy.each do |id, display|
      reload(id)&.destroy!
    rescue StandardError => ex
      warn "[verify_domain_orphan_spec cleanup] #{ex.class}: #{ex.message}"
    ensure
      remove_legacy_custom_domain(id, display)
    end
    begin
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[verify_domain_orphan_spec cleanup] #{ex.class}: #{ex.message}"
    end
  end

  def orphan(display = "orphan-verify-#{suffix}.com")
    id = write_legacy_custom_domain(
      display, org_id: nil,
               fields: { 'txt_validation_host' => '_onetime-challenge-x', 'txt_validation_value' => 'old-value' }
    )
    legacy << [id, display]
    id
  end

  def reload(id)
    model.find_by_identifier(id)
  end

  def stored(id)
    model.dbclient.hgetall(model.dbkey(id))
  end

  it 'skips it: no check, nothing written, reported as skipped' do
    id     = orphan
    before = stored(id)

    result = described_class.new(domain: reload(id), strategy: strategy, persist: true).call

    expect(strategy).not_to have_received(:validate_ownership)
    expect(strategy).not_to have_received(:check_status)
    expect(stored(id)).to eq(before)
    expect([result.skipped, result.persisted, result.dns_validated, result.success?, result.dns_outcome])
      .to eq([true, false, false, true, :skipped])
  end

  it 'counts it as skipped in a bulk run, and verifies the owned domain beside it' do
    id    = orphan
    owned = model.create!("owned-verify-#{suffix}.com", org.objid).tap { |rec| created << rec }

    result = described_class.new(domains: [reload(id), owned], strategy: strategy, persist: true, rate_limit: 0).call

    expect([result.total, result.skipped_count, result.verified_count]).to eq([2, 1, 1])
    expect(result.results.map(&:skipped)).to eq([true, false])
    expect(reload(owned.identifier).ownership_verified).to be(true)
  end

  it 'does not undo the adoption reset from a copy loaded before the adoption' do
    id    = orphan
    stale = reload(id)
    model.claim_orphaned_domain(reload(id), org.objid)
    adopted = stored(id)

    result = described_class.new(domain: stale, strategy: strategy, persist: true).call

    record = reload(id)
    expect([record.org_id, record.ownership_verified, record.resolving]).to eq([org.objid, false, false])
    expect(record.txt_validation_value).not_to eq('old-value')
    expect(stored(id)).to eq(adopted)
    expect(result.respond_to?(:skipped) && result.skipped).to be(true)
  end
end
