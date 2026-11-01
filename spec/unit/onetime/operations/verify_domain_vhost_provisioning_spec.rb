# spec/unit/onetime/operations/verify_domain_vhost_provisioning_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::VerifyDomain and the virtual host at the certificate
# provider (the approximated strategy).
#
# The virtual host is created by verification, once ownership is verified,
# and never when the domain is added. Until then a provider that has no
# virtual host for the name is a known state: nothing is stored for it and
# the check is not recorded as failed.
#
# Real datastore: the examples read back what the check stored.

require 'spec_helper'
require 'securerandom'
require 'onetime/operations/verify_domain'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::Operations::VerifyDomain, 'and the virtual host', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:org) { Onetime::Organization.new(display_name: "Verify vhost #{suffix}").tap(&:save) }
  let(:records) { [] }
  # The client raises on a 404 and the strategy reports the message.
  let(:not_found) { { ready: false, message: "Error: Could not find Virtual Host: vhost-#{suffix}.example.com" } }
  let(:found) { { ready: true, has_ssl: true, is_resolving: true, data: { 'status' => 'ACTIVE_SSL' } } }
  let(:strategy) do
    instance_double(
      Onetime::DomainValidation::BaseStrategy,
      request_certificate: { status: 'requested', message: 'Virtual host created', data: { 'status' => 'PENDING' } },
      proves_ownership?: true,
      bulk_rate_limit: 0,
    )
  end

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[verify_domain_vhost_provisioning_spec cleanup] #{ex.class}: #{ex.message}"
    end
    org.destroy! if org.exists?
  end

  def create
    Onetime::CustomDomain.create!("vhost-#{suffix}.example.com", org.objid).tap { |rec| records << rec }
  end

  def reload(rec)
    Onetime::CustomDomain.find_by_identifier(rec.identifier)
  end

  def verify(rec, txt_validated:)
    allow(strategy).to receive(:validate_ownership)
      .and_return({ validated: txt_validated, message: 'TXT check', data: [{ 'match' => txt_validated }] })
    allow(strategy).to receive(:check_status).and_return(not_found, found)
    described_class.new(domain: rec, strategy: strategy, persist: true).call
  end

  it 'does not create it while ownership is not verified, and records no failed check' do
    rec    = create
    result = verify(rec, txt_validated: false)
    stored = reload(rec)

    expect(strategy).not_to have_received(:request_certificate)
    expect([result.ssl_ready, result.is_resolving, stored.vhost, stored.vhost_fetch_failed_at])
      .to eq([nil, nil, nil, nil])
  end

  it 'creates it when the TXT check passes in this run, and stores the status read after' do
    rec    = create
    result = verify(rec, txt_validated: true)

    expect(strategy).to have_received(:request_certificate).with(rec).once
    expect([result.current_state, result.ssl_ready, reload(rec).parse_vhost['status']])
      .to eq([:verified, true, 'ACTIVE_SSL'])
  end

  it 'creates it for a domain an operator override keeps verified' do
    rec                      = create
    rec.ownership_verified   = true
    rec.verified_by_override = true
    rec.resolving            = true
    rec.save

    result = verify(rec, txt_validated: false)

    expect(strategy).to have_received(:request_certificate).with(rec).once
    expect([result.override_held, result.ssl_ready]).to eq([true, true])
  end

  it 'does not create it for a domain this run demotes' do
    rec                    = create
    rec.ownership_verified = true
    rec.resolving          = true
    rec.save

    result = verify(rec, txt_validated: false)

    expect(strategy).not_to have_received(:request_certificate)
    expect([result.demoted?, reload(rec).vhost]).to eq([true, nil])
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
