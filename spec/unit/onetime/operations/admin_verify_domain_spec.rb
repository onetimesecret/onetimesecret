# spec/unit/onetime/operations/admin_verify_domain_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::AdminVerifyDomain.
#
# Covers: it reuses (delegates to) the incumbent VerifyDomain op, passes the
# result through unchanged, and records EXACTLY ONE AdminAuditEvent per call —
# with result: :success on a clean run and :failure when the op reports an error
# (epic #31 / CONTRACT 4). The bare VerifyDomain op is never audited by
# non-admin callers, so the admin trail only sees admin-initiated verifies.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/admin_verify_domain_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/admin_verify_domain'

RSpec.describe Onetime::Operations::AdminVerifyDomain do
  let(:domain) { double('CustomDomain', extid: 'cd_abc123', display_domain: 'secrets.example.com') }
  let(:inner)  { instance_double(Onetime::Operations::VerifyDomain) }

  # A stand-in for VerifyDomain::Result with the fields the wrapper reads.
  def result_double(success:, previous: :pending, current: :verified)
    double(
      'VerifyDomain::Result',
      success?: success,
      previous_state: previous,
      current_state: current,
      dns_validated: success,
      is_resolving: success,
      ssl_ready: success,
      persisted: true,
      error: success ? nil : 'DNS lookup failed',
    )
  end

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(Onetime::Operations::VerifyDomain).to receive(:new).and_return(inner)
  end

  it 'delegates to the incumbent VerifyDomain op with the domain and persist flag' do
    allow(inner).to receive(:call).and_return(result_double(success: true))

    described_class.new(domain: domain, actor: 'ur_col').call

    expect(Onetime::Operations::VerifyDomain).to have_received(:new).with(
      domain: domain, persist: true
    )
  end

  it 'records exactly one audit event with result: :success on a clean verify' do
    op_result = result_double(success: true, previous: :pending, current: :verified)
    allow(inner).to receive(:call).and_return(op_result)

    returned = described_class.new(domain: domain, actor: 'ur_col').call

    # Returns the underlying Result unchanged.
    expect(returned).to be(op_result)
    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      actor: 'ur_col',
      verb: 'domain.verify',
      target: 'cd_abc123',
      result: :success,
      detail: hash_including(
        previous_state: 'pending',
        current_state: 'verified',
        dns_validated: true,
        is_resolving: true,
        ssl_ready: true,
      ),
    )
  end

  it 'records result: :failure (still exactly one event) when the op reports an error' do
    allow(inner).to receive(:call).and_return(
      result_double(success: false, previous: :pending, current: :pending)
    )

    described_class.new(domain: domain, actor: 'ur_col').call

    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      hash_including(verb: 'domain.verify', target: 'cd_abc123', result: :failure)
    )
  end

  it 'forwards persist: false for a read-only health check (still audited)' do
    allow(inner).to receive(:call).and_return(result_double(success: true))

    described_class.new(domain: domain, actor: 'ur_col', persist: false).call

    expect(Onetime::Operations::VerifyDomain).to have_received(:new).with(
      domain: domain, persist: false
    )
    expect(Onetime::AdminAuditEvent).to have_received(:record).once
  end
end
