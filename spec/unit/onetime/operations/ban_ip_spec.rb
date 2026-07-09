# spec/unit/onetime/operations/ban_ip_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::BanIP (idempotency contract).
#
# Covers the ban verb's documented contract (epic #33 / CONTRACT 4), fully
# mocked — NO datastore. Onetime::BannedIP and Onetime::AdminAuditEvent are
# stubbed/spied so we assert call-count and arguments without touching Redis.
#
#   - Fresh IP  -> status: :success + EXACTLY ONE AdminAuditEvent (verb
#     'ip.ban', PUBLIC actor identity, never an internal objid).
#   - Already-banned IP -> status: :already_banned, no-op, records NO audit
#     event (negative expectation).
#   - `banned_by` (stored on the record) and `actor` (audit identity) are
#     DISTINCT and each threaded to the right sink.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/ban_ip_spec.rb

require 'spec_helper'
require 'colonel/models/banned_ip'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/ban_ip'

RSpec.describe Onetime::Operations::BanIP do
  let(:ip)         { '203.0.113.7' }
  let(:actor)      { 'ur_col_public_extid' }   # PUBLIC identity (extid/email)
  let(:banned_by)  { 'obj_internal_colonel_objid' } # stored objid, DISTINCT from actor

  # Stand-in for the persisted BannedIP record BanIP#call reads back.
  let(:banned_record) do
    double(
      'BannedIP',
      objid: 'banip_abc123',
      ip_address: ip,
      reason: 'abuse',
      banned_by: banned_by,
      banned_at: 1_700_000_000,
    )
  end

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(Onetime::BannedIP).to receive(:ban!).and_return(banned_record)
  end

  context 'when the IP is not already banned (fresh ban)' do
    before { allow(Onetime::BannedIP).to receive(:banned?).with(ip).and_return(false) }

    it 'returns status: :success with the persisted record fields' do
      result = described_class.new(
        ip_address: ip, actor: actor, reason: 'abuse', banned_by: banned_by
      ).call

      expect(result.status).to eq(:success)
      expect(result.id).to eq('banip_abc123')
      expect(result.ip_address).to eq(ip)
      expect(result.reason).to eq('abuse')
      expect(result.banned_by).to eq(banned_by)
      expect(result.banned_at).to eq(1_700_000_000)
    end

    it 'calls BannedIP.ban! once, threading banned_by (the stored objid) through' do
      described_class.new(
        ip_address: ip, actor: actor, reason: 'abuse', banned_by: banned_by, expiration: 3600
      ).call

      expect(Onetime::BannedIP).to have_received(:ban!).once.with(
        ip, reason: 'abuse', banned_by: banned_by, expiration: 3600
      )
    end

    it 'records EXACTLY ONE audit event with verb ip.ban and the PUBLIC actor identity' do
      described_class.new(
        ip_address: ip, actor: actor, reason: 'abuse', banned_by: banned_by, expiration: 3600
      ).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'ip.ban',
        target: ip,
        result: :success,
        detail: { reason: 'abuse', expiration: 3600 },
      )
    end

    it 'keeps actor (audit identity) and banned_by (stored) DISTINCT' do
      described_class.new(
        ip_address: ip, actor: actor, reason: 'abuse', banned_by: banned_by
      ).call

      # actor goes to the audit trail (public id)...
      expect(Onetime::AdminAuditEvent).to have_received(:record).with(
        hash_including(actor: actor)
      )
      # ...banned_by goes to the record (internal objid); never crossed over.
      expect(Onetime::BannedIP).to have_received(:ban!).with(
        ip, hash_including(banned_by: banned_by)
      )
      expect(actor).not_to eq(banned_by)
    end
  end

  context 'when the IP is already banned (idempotent no-op)' do
    before { allow(Onetime::BannedIP).to receive(:banned?).with(ip).and_return(true) }

    it 'returns status: :already_banned with null record fields' do
      result = described_class.new(
        ip_address: ip, actor: actor, reason: 'abuse', banned_by: banned_by
      ).call

      expect(result.status).to eq(:already_banned)
      expect(result.id).to be_nil
      expect(result.ip_address).to eq(ip)
      expect(result.reason).to be_nil
      expect(result.banned_by).to be_nil
      expect(result.banned_at).to be_nil
    end

    it 'does NOT mutate: BannedIP.ban! is never called' do
      described_class.new(ip_address: ip, actor: actor).call

      expect(Onetime::BannedIP).not_to have_received(:ban!)
    end

    it 'records NO audit event' do
      described_class.new(ip_address: ip, actor: actor).call

      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end
end
