# spec/unit/onetime/models/admin_audit_event_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Onetime::AdminAuditEvent — the single write path every mutating
# admin operation calls (epic #3653 / ticket #21).
#
# These exercise the real Familia-backed sorted set on the test database (port
# 2121), so each example clears the global events set to stay isolated.
#
# Coverage mirrors the acceptance criteria: an event is written on success, on
# failure, the write path is best-effort, reads are newest-first, and the capped
# sorted set is trimmed to its bound.
RSpec.describe Onetime::AdminAuditEvent do
  before { described_class.events.clear }
  after  { described_class.events.clear }

  describe '.record' do
    it 'persists a success event and returns the stored hash' do
      event = described_class.record(
        actor: 'ur7xexamples',
        verb: 'customer.set_role',
        target: 'ur9ytargets',
        result: :success,
        detail: { role: 'colonel' },
      )

      expect(event).to include(
        'actor' => 'ur7xexamples',
        'verb' => 'customer.set_role',
        'target' => 'ur9ytargets',
        'result' => 'success',
        'detail' => { 'role' => 'colonel' },
      )
      expect(event['created']).to be_a(Float)
      expect(described_class.count).to eq(1)
    end

    it 'records failure outcomes too (both success and failure are persisted)' do
      described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)
      described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :failure)

      results = described_class.recent(2).map { |e| e['result'] }
      expect(results).to contain_exactly('success', 'failure')
      expect(described_class.count).to eq(2)
    end

    it 'is best-effort: swallows a write error and returns nil without raising' do
      boom = Class.new do
        def to_s
          raise 'boom serializing detail'
        end
      end.new

      result = nil
      expect { result = described_class.record(actor: 'a', verb: 'v', target: 't', result: :success, detail: boom) }
        .not_to raise_error
      expect(result).to be_nil
      expect(described_class.count).to eq(0)
    end

    it 'stores the actor extid, never an internal objid' do
      customer = Struct.new(:extid, :email, :objid).new('ur1publics', 'c@example.com', 'objid_internal_secret')

      event = described_class.record(actor: customer, verb: 'v', target: 't', result: :success)

      expect(event['actor']).to eq('ur1publics')
      expect(event['actor']).not_to include('objid_internal')
    end

    it 'falls back to email when the actor has no extid' do
      customer = Struct.new(:extid, :email).new('', 'colonel@example.com')

      event = described_class.record(actor: customer, verb: 'v', target: 't', result: :success)

      expect(event['actor']).to eq('colonel@example.com')
    end

    it 'redacts secret content, tokens, and passphrases at any depth' do
      event = described_class.record(
        actor: 'a', verb: 'v', target: 't', result: :success,
        detail: {
          'passphrase' => 'hunter2',
          'api_token' => 'sk_live_abc',
          'note' => 'safe to keep',
          'nested' => { 'secret_value' => 'plaintext', 'ok' => 1 },
        },
      )

      detail = event['detail']
      expect(detail['passphrase']).to eq(described_class::REDACTED)
      expect(detail['api_token']).to eq(described_class::REDACTED)
      expect(detail['note']).to eq('safe to keep')
      expect(detail['nested']['secret_value']).to eq(described_class::REDACTED)
      expect(detail['nested']['ok']).to eq(1)
    end

    it 'truncates overlong string values' do
      event = described_class.record(
        actor: 'a', verb: 'v', target: 't', result: :success,
        detail: { 'blob' => 'x' * 500 },
      )

      expect(event['detail']['blob'].length).to eq(described_class::MAX_DETAIL_VALUE_LENGTH + 3)
    end

    it 'auto-trims to MAX_EVENTS on every write' do
      stub_const("#{described_class}::MAX_EVENTS", 3)

      5.times { |i| described_class.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.count).to eq(3)
    end
  end

  describe '.recent' do
    it 'returns events newest-first' do
      described_class.record(actor: 'a', verb: 'first', target: 't', result: :success)
      described_class.record(actor: 'a', verb: 'second', target: 't', result: :success)
      described_class.record(actor: 'a', verb: 'third', target: 't', result: :success)

      expect(described_class.recent(3).map { |e| e['verb'] }).to eq(%w[third second first])
    end

    it 'returns an empty array for a non-positive limit' do
      described_class.record(actor: 'a', verb: 'v', target: 't', result: :success)

      expect(described_class.recent(0)).to eq([])
    end
  end

  describe '.trim!' do
    it 'keeps only the newest `cap` events, dropping the oldest overflow' do
      5.times { |i| described_class.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      removed = described_class.trim!(3)

      expect(removed).to eq(2)
      expect(described_class.count).to eq(3)
      expect(described_class.recent(3).map { |e| e['verb'] }).to eq(%w[v4 v3 v2])
    end

    it 'is a no-op when the set is already within the cap' do
      2.times { |i| described_class.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.trim!(10)).to eq(0)
      expect(described_class.count).to eq(2)
    end
  end
end
