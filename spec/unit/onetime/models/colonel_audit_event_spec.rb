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
    described_class.access_events.clear
  end

  after do
    described_class.events.clear
    described_class.security_events.clear
    described_class.access_events.clear
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

    # The fail-closed region is the BUILD and the ADD, nothing after them. Once
    # the event has been emitted to the sink and added to the collection it IS
    # recorded, so a failing retention pass is not a missing trail — it is a
    # collection sitting one member over its cap until the next write.
    describe 'when the post-write trim fails' do
      before do
        allow(described_class).to receive(:trim!).and_raise('trim exploded')
        allow(OT).to receive(:le)
      end

      it 'still returns the stored event and keeps it in the collection' do
        event = described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)

        expect(event).to include('verb' => 'customer.purge')
        expect(described_class.count).to eq(1)
      end

      it 'does NOT raise under fail_closed — the event exists, so nothing is untraceable' do
        event = nil

        expect do
          event = described_class.record(
            actor: 'a', verb: 'customer.purge', target: 'ur_victim', result: :success, fail_closed: true,
          )
        end.not_to raise_error

        expect(event).to include('verb' => 'customer.purge', 'target' => 'ur_victim')
        expect(described_class.count).to eq(1)
      end

      it 'logs the trim failure as a trim failure, never as a lost record' do
        described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)

        expect(OT).to have_received(:le).with(
          '[ColonelAuditEvent] trim failed', hash_including(trail: 'events'),
        )
        expect(OT).not_to have_received(:le).with('[ColonelAuditEvent] record failed', anything)
      end
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

    # Fail-open either way here, but a trim failure must still not turn a
    # STORED event into a nil return — the caller's `nil` means "not recorded".
    it 'returns the stored event when only the post-write trim fails' do
      allow(described_class).to receive(:trim_security!).and_raise('trim exploded')
      allow(OT).to receive(:le)

      event = described_class.record_security(actor: 'anonymous', verb: 'colonel.signin_failed', target: 't',
                                              result: :failure)

      expect(event).to include('verb' => 'colonel.signin_failed')
      expect(described_class.security_count).to eq(1)
    end
  end

  describe '.trim!' do
    it 'keeps only the newest MAX_EVENTS events, dropping the oldest overflow' do
      stub_const("#{described_class}::MAX_EVENTS", 3)
      # Written straight into the collection so the write path's own auto-trim
      # does not do the work this example is about.
      5.times { |i| described_class.events.add({ 'verb' => "v#{i}" }, Familia.now + i) }

      removed = described_class.trim!

      expect(removed).to eq(2)
      expect(described_class.count).to eq(3)
      expect(described_class.recent(3).map { |e| e['verb'] }).to eq(%w[v4 v3 v2])
    end

    it 'is a no-op when the set is already within the cap' do
      2.times { |i| described_class.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.trim!(described_class::MAX_EVENTS)).to eq(0)
      expect(described_class.count).to eq(2)
    end

    # #4334 — the tamper-resistance half. `trim!` is public, and before the
    # clamp its argument was taken at face value: `trim!(0)` emptied the whole
    # operator trail in one call. Retention may now only widen through this API.
    it 'clamps a cap below MAX_EVENTS: trim!(0) can no longer wipe the trail' do
      3.times { |i| described_class.record(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.trim!(0)).to eq(0)
      expect(described_class.trim!(1)).to eq(0)
      expect(described_class.trim!(-100)).to eq(0)
      expect(described_class.count).to eq(3)
    end
  end

  describe '.trim_security!' do
    it 'clamps a cap below MAX_SECURITY_EVENTS' do
      3.times { |i| described_class.record_security(actor: 'anonymous', verb: "s#{i}", target: 't', result: :failure) }

      expect(described_class.trim_security!(0)).to eq(0)
      expect(described_class.security_count).to eq(3)
    end

    # The age bound is the second door into the same wipe: without a clamp,
    # `trim_security!(cap, 1)` drops everything older than one second.
    it 'clamps a positive max_age below SECURITY_EVENT_RETENTION' do
      described_class.security_events.add({ 'verb' => 'older' }, Familia.now - 3600)
      described_class.security_events.add({ 'verb' => 'newer' }, Familia.now)

      expect(described_class.trim_security!(described_class::MAX_SECURITY_EVENTS, 1)).to eq(0)
      expect(described_class.recent_security(5).map { |e| e['verb'] }).to eq(%w[newer older])
    end

    it 'still applies the age bound at or above SECURITY_EVENT_RETENTION' do
      stub_const("#{described_class}::SECURITY_EVENT_RETENTION", 60)
      described_class.security_events.add({ 'verb' => 'stale' }, Familia.now - 3600)
      described_class.security_events.add({ 'verb' => 'fresh' }, Familia.now)

      expect(described_class.trim_security!(described_class::MAX_SECURITY_EVENTS, 60)).to eq(1)
      expect(described_class.recent_security(5).map { |e| e['verb'] }).to eq(%w[fresh])
    end

    it 'treats a non-positive max_age as "no age bound" (it keeps more, not less)' do
      described_class.security_events.add({ 'verb' => 'ancient' }, Familia.now - (10 * 365 * 24 * 3600))

      expect(described_class.trim_security!(described_class::MAX_SECURITY_EVENTS, 0)).to eq(0)
      expect(described_class.security_count).to eq(1)
    end
  end

  # #4334 — the sink half: every event is emitted as a structured log line on a
  # dedicated SemanticLogger category BEFORE the datastore write, so a Valkey
  # outage cannot lose the record. Message expectations on the logger, not
  # appender output: the point is what the write path emits, not how a
  # particular appender renders it.
  describe 'the external sink' do
    let(:sink) { instance_spy(SemanticLogger::Logger, described_class::SINK_LOGGER_NAME) }

    before { allow(described_class).to receive(:sink_logger).and_return(sink) }

    it 'emits every operator event, tagged with its trail' do
      described_class.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)

      expect(sink).to have_received(:info).once.with(
        described_class::SINK_MESSAGE,
        hash_including(
          'actor' => 'ur_col',
          'verb' => 'customer.purge',
          'target' => 'ur_v',
          'result' => 'success',
          'trail' => 'events',
        ),
      )
    end

    it 'emits security-telemetry events too, on the other trail' do
      described_class.record_security(actor: 'anonymous', verb: 'auth.throttled', target: 'ip', result: :failure)

      expect(sink).to have_received(:info).once.with(
        described_class::SINK_MESSAGE,
        hash_including('verb' => 'auth.throttled', 'trail' => 'security_events'),
      )
    end

    # Every trail ships. The three-way split exists to budget Redis, and the
    # sink has no budget to protect.
    it 'emits observation events too, on the third trail' do
      described_class.record_access(actor: 'ur_col', verb: 'audit.list', target: 'colonel_audit', result: :success)

      expect(sink).to have_received(:info).once.with(
        described_class::SINK_MESSAGE,
        hash_including('verb' => 'audit.list', 'trail' => 'access_events'),
      )
    end

    it 'emits the REDACTED detail, never the caller-supplied original' do
      described_class.record(
        actor: 'a', verb: 'v', target: 't', result: :success,
        detail: { 'passphrase' => 'hunter2', 'note' => 'safe' },
      )

      expect(sink).to have_received(:info).once.with(
        described_class::SINK_MESSAGE,
        hash_including('detail' => { 'passphrase' => described_class::REDACTED, 'note' => 'safe' }),
      )
    end

    # The ordering is the durability guarantee: the line is already gone before
    # anything touches Redis. Simulated by swapping the whole collection —
    # Familia's live SortedSet instance is frozen, so it cannot be stubbed in
    # place.
    def simulate_datastore_outage!
      broken = instance_double(Familia::SortedSet)
      allow(broken).to receive(:add).and_raise('valkey is down')
      allow(broken).to receive(:clear) # the suite's after hook still runs against it
      allow(described_class).to receive(:events).and_return(broken)
    end

    it 'emits before the datastore write, so a failed write still leaves a line' do
      simulate_datastore_outage!

      expect(described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)).to be_nil
      expect(sink).to have_received(:info).once
    end

    it 'raises the fail-closed error only after the sink has the record' do
      simulate_datastore_outage!

      expect do
        described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success, fail_closed: true)
      end.to raise_error(Onetime::AuditWriteFailure)
      expect(sink).to have_received(:info).once
    end

    # Independence in the other direction: the sink is a log destination, and a
    # broken appender must not cost the trail its Redis copy — nor, for a
    # fail-closed verb, abort the operation.
    it 'survives a sink failure without losing the datastore write' do
      allow(sink).to receive(:info).and_raise('appender exploded')

      event = described_class.record(actor: 'a', verb: 'customer.purge', target: 't', result: :success)

      expect(event).to include('verb' => 'customer.purge')
      expect(described_class.count).to eq(1)
    end
  end

  # The THIRD retention domain (#4335): authenticated observations — curated
  # sensitive reads and dry-run previews. Trusted writers, but chatty by
  # construction, so they get their own budget for the same reason anonymous
  # telemetry does: nothing that writes often may compete with the mutation
  # trail for eviction.
  describe '.record_access' do
    it 'stores the same event shape as the other two write paths' do
      event = described_class.record_access(
        actor: 'ur_col', verb: 'secret.receipt_view', target: 'sh_abc', result: :success,
        detail: { 'state' => 'received' },
      )

      expect(event).to include(
        'actor' => 'ur_col', 'verb' => 'secret.receipt_view',
        'target' => 'sh_abc', 'result' => 'success',
      )
      expect(event['detail']).to eq('state' => 'received')
      expect(described_class.access_count).to eq(1)
    end

    it 'records a dry-run preview as its own result value' do
      described_class.record_access(
        actor: 'ur_col', verb: 'organization.delete', target: 'on_org1', result: 'preview',
        detail: { dry_run: true },
      )

      expect(described_class.recent_access(1).first['result']).to eq('preview')
    end

    # The eviction boundary, in both directions.
    it 'never writes into the operator or security trails' do
      described_class.record_access(actor: 'ur_col', verb: 'audit.list', target: 't', result: :success)

      expect(described_class.count).to eq(0)
      expect(described_class.security_count).to eq(0)
      expect(described_class.access_count).to eq(1)
    end

    it 'cannot evict an operator record no matter how much is written' do
      stub_const("#{described_class}::MAX_ACCESS_EVENTS", 2)
      described_class.record(actor: 'ur_col', verb: 'customer.purge', target: 'ur_v', result: :success)

      10.times { |i| described_class.record_access(actor: 'ur_col', verb: "read#{i}", target: 't', result: :success) }

      expect(described_class.access_count).to eq(2)
      expect(described_class.count).to eq(1)
      expect(described_class.recent(1).first['verb']).to eq('customer.purge')
    end

    it 'redacts detail on the way in, like every other write path' do
      event = described_class.record_access(
        actor: 'ur_col', verb: 'v', target: 't', result: :success,
        detail: { 'passphrase' => 'hunter2', 'note' => 'safe' },
      )

      expect(event['detail']).to eq('passphrase' => described_class::REDACTED, 'note' => 'safe')
    end

    # Fail-open ALWAYS, with no keyword to opt out: observing mutated nothing,
    # so there is no destroyed-with-no-trail outcome for failing closed to
    # surface — only the chance to break the console over a broken audit write.
    it 'swallows a write failure and returns nil' do
      result = :unset

      expect { result = described_class.record_access(actor: 'a', verb: 'v', target: 't', result: :success, detail: boom_detail) }
        .not_to raise_error
      expect(result).to be_nil
      expect(described_class.access_count).to eq(0)
    end

    it 'takes no fail_closed keyword at all' do
      expect(described_class.method(:record_access).parameters.map(&:last)).not_to include(:fail_closed)
    end

    it 'auto-trims to MAX_ACCESS_EVENTS on every write' do
      stub_const("#{described_class}::MAX_ACCESS_EVENTS", 3)

      5.times { |i| described_class.record_access(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.access_count).to eq(3)
      expect(described_class.recent_access(3).map { |e| e['verb'] }).to eq(%w[v4 v3 v2])
    end

    it 'returns the stored event when only the post-write trim fails' do
      allow(described_class).to receive(:trim_access!).and_raise('trim exploded')
      allow(OT).to receive(:le)

      event = described_class.record_access(actor: 'a', verb: 'audit.list', target: 'colonel_audit',
                                            result: :success)

      expect(event).to include('verb' => 'audit.list')
      expect(described_class.access_count).to eq(1)
    end
  end

  describe '.trim_access!' do
    # Same tamper-resistance contract as trim! / trim_security! (#4334):
    # retention only ever widens through this API.
    it 'clamps a smaller cap up to MAX_ACCESS_EVENTS' do
      3.times { |i| described_class.record_access(actor: 'a', verb: "v#{i}", target: 't', result: :success) }

      expect(described_class.trim_access!(0)).to eq(0)
      expect(described_class.access_count).to eq(3)
    end

    it 'clamps a shorter max_age up to ACCESS_EVENT_RETENTION' do
      described_class.access_events.add({ 'verb' => 'older' }, Familia.now - 3600)
      described_class.access_events.add({ 'verb' => 'newer' }, Familia.now)

      expect(described_class.trim_access!(described_class::MAX_ACCESS_EVENTS, 1)).to eq(0)
      expect(described_class.access_count).to eq(2)
    end

    it 'drops members older than ACCESS_EVENT_RETENTION' do
      described_class.access_events.add(
        { 'verb' => 'stale' }, Familia.now - described_class::ACCESS_EVENT_RETENTION - 100,
      )
      described_class.access_events.add({ 'verb' => 'fresh' }, Familia.now)

      expect(described_class.trim_access!).to eq(1)
      expect(described_class.recent_access(5).map { |e| e['verb'] }).to eq(%w[fresh])
    end

    it 'treats a non-positive max_age as "keep everything", not as a wipe' do
      described_class.access_events.add({ 'verb' => 'ancient' }, Familia.now - 100_000_000)

      expect(described_class.trim_access!(described_class::MAX_ACCESS_EVENTS, 0)).to eq(0)
      expect(described_class.access_count).to eq(1)
    end
  end

  describe '.sink_logger' do
    it 'is the category the syslog appender filters on' do
      expect(described_class::SINK_LOGGER_NAME)
        .to eq(Onetime::Initializers::SetupLoggers::AUDIT_SINK_LOGGER_NAME)
    end

    # Pinned in code, not read from the logging config: the durability story
    # must not go quiet because the application default level was raised.
    it 'pins its level rather than following the application default' do
      expect(described_class.sink_logger.level).to eq(described_class::SINK_LEVEL)
    end
  end
end
