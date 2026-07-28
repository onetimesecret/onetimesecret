# spec/unit/onetime/operations/unban_ip_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::UnbanIP (idempotency contract).
#
# Symmetric sibling of the BanIP spec, fully mocked — NO datastore.
# Onetime::BannedIP and Onetime::AdminAuditEvent are stubbed/spied.
#
#   - Banned IP (unban! -> true)  -> status: :success + EXACTLY ONE
#     AdminAuditEvent (verb 'ip.unban', PUBLIC actor identity).
#   - Not-banned IP (unban! -> false) -> status: :not_found, no-op, records
#     NO audit event (negative expectation).
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/unban_ip_spec.rb

require 'spec_helper'
require 'colonel/models/banned_ip'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/unban_ip'

RSpec.describe Onetime::Operations::UnbanIP do
  let(:ip)    { '203.0.113.7' }
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
  end

  context 'when a record was removed (unban! returns true)' do
    before { allow(Onetime::BannedIP).to receive(:unban!).with(ip).and_return(true) }

    it 'returns status: :success with unbanned: true' do
      result = described_class.new(ip_address: ip, actor: actor).call

      expect(result.status).to eq(:success)
      expect(result.ip_address).to eq(ip)
      expect(result.unbanned).to be(true)
    end

    it 'calls BannedIP.unban! exactly once' do
      described_class.new(ip_address: ip, actor: actor).call

      expect(Onetime::BannedIP).to have_received(:unban!).once.with(ip)
    end

    it 'records EXACTLY ONE audit event with verb ip.unban and the PUBLIC actor identity' do
      described_class.new(ip_address: ip, actor: actor).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'ip.unban',
        target: ip,
        result: :success,
      )
    end
  end

  context 'when nothing was removed (unban! returns false)' do
    before { allow(Onetime::BannedIP).to receive(:unban!).with(ip).and_return(false) }

    it 'returns status: :not_found with unbanned: false' do
      result = described_class.new(ip_address: ip, actor: actor).call

      expect(result.status).to eq(:not_found)
      expect(result.ip_address).to eq(ip)
      expect(result.unbanned).to be(false)
    end

    # A refusal, not an idempotent no-op: the colonel adapter renders
    # :not_found as a 404, so it is an operator-visible refusal of an attempted
    # privileged mutation and belongs in the trail.
    it 'records ONE result: :failure event with the unchanged verb' do
      described_class.new(ip_address: ip, actor: actor).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'ip.unban',
        target: ip,
        result: :failure,
        detail: { reason: 'not_found' },
      )
    end
  end

  # The Onetime::AuditedFailure mechanism. unban! destroys the record and its
  # index entry BEFORE the success-path record call. Message expectation, not a
  # store read: AdminAuditEvent.record swallows its own errors.
  it 'records ONE result: :failure event when unban! raises, and re-raises' do
    allow(Onetime::BannedIP).to receive(:unban!).and_raise(Onetime::Problem, 'index delete failed')

    expect do
      described_class.new(ip_address: ip, actor: actor).call
    end.to raise_error(Onetime::Problem, /index delete failed/)

    expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: actor,
        verb: 'ip.unban',
        target: ip, # literal: a broken target lambda silently lands as 'unknown'
        result: :failure,
        detail: hash_including(error: 'Onetime::Problem', message: 'index delete failed'),
      ),
    )
  end
end
