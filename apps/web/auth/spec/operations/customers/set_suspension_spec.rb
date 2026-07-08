# apps/web/auth/spec/operations/customers/set_suspension_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::SetSuspension.
#
# Covers: successful suspend (+ exactly one audit event + session sweep),
# unsuspend (clears fields, no sweep), idempotent no_change (no save, no
# audit), the colonel privilege guard, and the exact-match session predicate
# (a substring must NOT revoke a different customer's session).
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/set_suspension_spec.rb

require 'spec_helper'
require 'json'
require 'onetime/models/admin_audit_event'
require 'auth/operations/customers/set_suspension'

RSpec.describe Auth::Operations::Customers::SetSuspension do
  let(:customer) do
    double(
      'Customer',
      role: 'customer',
      extid: 'ur_test',
      email: 'alice@example.com',
      suspended?: false,
      save: true,
      :suspended= => nil,
      :suspended_at= => nil,
      :suspended_by= => nil,
      :suspended_reason= => nil,
    )
  end

  # Redis-like double for the session sweep. `scan_each` returns an Array
  # (Store.scan_keys calls .first on it), `get` serves plain-JSON payloads.
  def dbclient_with_sessions(sessions)
    db = double('dbclient')
    allow(db).to receive(:scan_each).and_return(sessions.keys)
    allow(db).to receive(:get) { |key| JSON.generate(sessions.fetch(key)) }
    allow(db).to receive(:del)
    db
  end

  let(:empty_db) { dbclient_with_sessions({}) }

  before { allow(Onetime::AdminAuditEvent).to receive(:record) }

  describe 'suspend' do
    it 'stamps the suspension fields, saves, and returns :success' do
      result = described_class.new(
        customer: customer, suspended: true, actor: 'ur_col',
        reason: 'abuse report', dbclient: empty_db,
      ).call

      expect(result.status).to eq(:success)
      expect(result.suspended).to be(true)
      expect(customer).to have_received(:suspended=).with(true)
      expect(customer).to have_received(:suspended_at=).with(kind_of(Integer))
      expect(customer).to have_received(:suspended_by=).with('ur_col')
      expect(customer).to have_received(:suspended_reason=).with('abuse report')
      expect(customer).to have_received(:save)
    end

    it 'records exactly one audit event with the reason and revoked count' do
      described_class.new(
        customer: customer, suspended: true, actor: 'ur_col',
        reason: 'abuse report', dbclient: empty_db,
      ).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: 'ur_col',
        verb: 'customer.suspend',
        target: 'ur_test',
        result: :success,
        detail: { reason: 'abuse report', sessions_revoked: 0 },
      )
    end

    it 'revokes only sessions whose identity EXACTLY matches the customer' do
      db = dbclient_with_sessions(
        'session:aaa' => { 'email' => 'alice@example.com', 'authenticated' => true },
        'session:bbb' => { 'external_id' => 'ur_test' },
        # Substring trap: a *different* customer whose email contains the
        # target's email must NOT be revoked.
        'session:ccc' => { 'email' => 'not-alice@example.com' },
        'session:ddd' => { 'email' => 'someone@else.com' },
      )

      result = described_class.new(
        customer: customer, suspended: true, actor: 'ur_col', dbclient: db,
      ).call

      expect(db).to have_received(:del).with('session:aaa')
      expect(db).to have_received(:del).with('session:bbb')
      expect(db).not_to have_received(:del).with('session:ccc')
      expect(db).not_to have_received(:del).with('session:ddd')
      expect(result.sessions_revoked).to eq(2)
    end

    it 'is a no_change (no save, no audit, no sweep) when already suspended' do
      allow(customer).to receive(:suspended?).and_return(true)
      db = dbclient_with_sessions('session:aaa' => { 'email' => 'alice@example.com' })

      result = described_class.new(
        customer: customer, suspended: true, actor: 'ur_col', dbclient: db,
      ).call

      expect(result.status).to eq(:no_change)
      expect(customer).not_to have_received(:save)
      expect(db).not_to have_received(:del)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'refuses to suspend a colonel-role account (no save, no audit)' do
      allow(customer).to receive(:role).and_return('colonel')

      expect do
        described_class.new(
          customer: customer, suspended: true, actor: 'ur_col', dbclient: empty_db,
        ).call
      end.to raise_error(described_class::PrivilegedAccount)

      expect(customer).not_to have_received(:save)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'treats a blank reason as nil in fields and audit detail' do
      described_class.new(
        customer: customer, suspended: true, actor: 'ur_col',
        reason: '   ', dbclient: empty_db,
      ).call

      expect(customer).to have_received(:suspended_reason=).with(nil)
      expect(Onetime::AdminAuditEvent).to have_received(:record).with(
        hash_including(detail: { reason: nil, sessions_revoked: 0 }),
      )
    end
  end

  describe 'unsuspend' do
    before { allow(customer).to receive(:suspended?).and_return(true) }

    it 'clears all suspension fields, saves, and audits customer.unsuspend' do
      db = dbclient_with_sessions('session:aaa' => { 'email' => 'alice@example.com' })

      result = described_class.new(
        customer: customer, suspended: false, actor: 'ur_col', dbclient: db,
      ).call

      expect(result.status).to eq(:success)
      expect(customer).to have_received(:suspended=).with(false)
      expect(customer).to have_received(:suspended_at=).with(nil)
      expect(customer).to have_received(:suspended_by=).with(nil)
      expect(customer).to have_received(:suspended_reason=).with(nil)
      expect(customer).to have_received(:save)
      # Unsuspending never sweeps sessions (there is nothing to revoke).
      expect(db).not_to have_received(:del)
      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: 'ur_col',
        verb: 'customer.unsuspend',
        target: 'ur_test',
        result: :success,
        detail: { sessions_revoked: 0 },
      )
    end

    it 'allows unsuspending a colonel-role account (guard is suspend-only)' do
      allow(customer).to receive(:role).and_return('colonel')

      result = described_class.new(
        customer: customer, suspended: false, actor: 'ur_col', dbclient: empty_db,
      ).call

      expect(result.status).to eq(:success)
    end

    it 'is a no_change when not suspended' do
      allow(customer).to receive(:suspended?).and_return(false)

      result = described_class.new(
        customer: customer, suspended: false, actor: 'ur_col', dbclient: empty_db,
      ).call

      expect(result.status).to eq(:no_change)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end
end
