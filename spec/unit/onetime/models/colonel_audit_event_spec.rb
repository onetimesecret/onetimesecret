# spec/unit/onetime/models/colonel_audit_event_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
# Onetime::AuditedFailure is not loaded by the app boot; the fail-closed cases
# below assert its authorization_rejection? predicate does NOT swallow the new
# write-failure error.
require 'onetime/audited_failure'

# Unit tests for Onetime::ColonelAuditEvent — the single write path every mutating
# admin operation calls (epic #3653 / ticket #21).
#
# These exercise the real Familia-backed sorted set on the test database (port
# 2163), so each example clears the global events set to stay isolated.
#
# Coverage mirrors the acceptance criteria: an event is written on success, on
# failure, the write path is best-effort, reads are newest-first, and the capped
# sorted set is trimmed to its bound.
RSpec.describe Onetime::ColonelAuditEvent do
  # A detail value whose #to_s raises, forcing an exception inside `record`
  # before anything is written. The two write-failure postures (fail-open by
  # default, fail-closed on opt-in) are both exercised through it.
  let(:boom_detail) do
    Class.new do
      def to_s
        raise 'boom serializing detail'
      end
    end.new
  end

  before do
    described_class.events.clear
    described_class.security_events.clear
  end

  after do
    described_class.events.clear
    described_class.security_events.clear
  end

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

    # #4333 — the fail-closed half. Same simulated write failure as the case
    # above; the only difference is the destructive caller's opt-in.
    it 'raises Onetime::AuditWriteFailure when fail_closed and the write fails' do
      expect do
        described_class.record(
          actor: 'a', verb: 'customer.purge', target: 'ur_victim', result: :success,
          detail: boom_detail, fail_closed: true,
        )
      end.to raise_error(Onetime::AuditWriteFailure) do |error|
        expect(error.verb).to eq('customer.purge')
        expect(error.target).to eq('ur_victim')
        # verb + target are PUBLIC identifiers; `detail` is the field that can
        # carry operator-supplied text and must never reach the message.
        expect(error.message).to include('customer.purge', 'ur_victim')
        expect(error.message).not_to include('boom')
      end

      expect(described_class.count).to eq(0)
    end

    # AuditedFailure.authorization_rejection? drops the Forbidden/Unauthorized
    # families outright. If the write-failure error landed in either, the
    # follow-up `result: :failure` record would be silently suppressed.
    it 'raises an error outside the Forbidden/Unauthorized families' do
      error = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 't')

      expect(error).not_to be_a(Onetime::Forbidden)
      expect(error).not_to be_a(Onetime::Unauthorized)
      expect(Onetime::AuditedFailure.authorization_rejection?(error)).to be(false)
    end

    it 'keeps the original exception as the cause of the fail-closed error' do
      expect do
        described_class.record(
          actor: 'a', verb: 'customer.purge', target: 't', result: :success,
          detail: boom_detail, fail_closed: true,
        )
      end.to raise_error(Onetime::AuditWriteFailure) { |error| expect(error.cause).to be_a(RuntimeError) }
    end

    it 'behaves exactly like the default when fail_closed and the write succeeds' do
      event = described_class.record(
        actor: 'a', verb: 'customer.purge', target: 't', result: :success, fail_closed: true,
      )

      expect(event).to include('verb' => 'customer.purge')
      expect(described_class.count).to eq(1)
    end

    it 'stays fail-open by default even for a destructive verb' do
      result = nil
      expect do
        result = described_class.record(
          actor: 'a', verb: 'customer.purge', target: 't', result: :success, detail: boom_detail,
        )
      end.not_to raise_error
      expect(result).to be_nil
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

    it 'redacts snake_case otp/pin keys without over-redacting lookalike words' do
      event = described_class.record(
        actor: 'a', verb: 'v', target: 't', result: :success,
        detail: {
          'otp_code' => '123456',
          'user_pin' => '0000',
          'otp'      => '654321',
          'shipping' => 'safe',   # contains "pin" — must NOT redact
          'caption'  => 'safe',   # contains "ption" — must NOT redact
          'options'  => 'safe',   # must NOT redact
        },
      )

      detail = event['detail']
      expect(detail['otp_code']).to eq(described_class::REDACTED)
      expect(detail['user_pin']).to eq(described_class::REDACTED)
      expect(detail['otp']).to eq(described_class::REDACTED)
      expect(detail['shipping']).to eq('safe')
      expect(detail['caption']).to eq('safe')
      expect(detail['options']).to eq('safe')
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

  # The security trail is the collection an UNAUTHENTICATED caller can drive, so
  # its bounds are the thing standing between a flood and an unbounded sorted set
  # in Valkey. Both bounds are applied by the WRITE path (record_security calls
  # trim_security!), and that is what these pin: calling trim_security! directly
  # would still pass if the write path stopped trimming, which would silently
  # turn `security_events` into an unbounded store.
  describe '.record_security' do
    it 'auto-trims to MAX_SECURITY_EVENTS on every write' do
      stub_const("#{described_class}::MAX_SECURITY_EVENTS", 3)

      5.times { |i| described_class.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }

      expect(described_class.security_count).to eq(3)
      expect(described_class.recent_security(3).map { |e| e['verb'] }).to eq(%w[s4 s3 s2])
    end

    it 'applies the age bound on every write, not only when trimmed by hand' do
      stub_const("#{described_class}::SECURITY_EVENT_RETENTION", 60)
      described_class.security_events.add({ 'verb' => 'stale' }, Familia.now - 3600)

      described_class.record_security(actor: 'anonymous', verb: 'fresh', target: 't', result: :failure)

      expect(described_class.recent_security(5).map { |e| e['verb'] }).to eq(%w[fresh])
    end

    it 'is best-effort: swallows a write error and returns nil without raising' do
      boom = Class.new do
        def to_s
          raise 'boom serializing detail'
        end
      end.new

      result = nil
      expect do
        result = described_class.record_security(actor: 'anonymous', verb: 'v', target: 't', result: :failure,
                                                 detail: boom)
      end.not_to raise_error
      expect(result).to be_nil
      expect(described_class.security_count).to eq(0)
    end

    it 'never writes into the operator trail' do
      described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)

      3.times { |i| described_class.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }

      expect(described_class.count).to eq(1)
      expect(described_class.recent(5).map { |e| e['verb'] }).to eq(%w[customer.purge])
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
