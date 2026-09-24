# spec/unit/onetime/session/impersonation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/session/impersonation'

# Unit tests for the colonel-impersonation session primitive.
#
# Two things are load-bearing here and are pinned as such:
#
#   1. The OVERLAY invariant — the marker never touches `external_id`, so a
#      lost marker degrades to an ordinary colonel session and never the other
#      way round.
#   2. Resolver fall-through — every invalidation ends the OVERLAY and answers
#      the PRINCIPAL. None of them may reject the session, because a rejected
#      session strands the operator with no way back to their own account.
RSpec.describe Onetime::SessionImpersonation do
  let(:now) { 1_756_700_000 }

  let(:target) do
    instance_double(
      Onetime::Customer,
      extid: 'ur_target', email: 'alice@example.com',
      exists?: true, suspended?: false, anonymous?: false,
    )
  end

  let(:colonel) do
    instance_double(
      Onetime::Customer,
      extid: 'ur_colonel', email: 'ops@example.com',
      exists?: true, suspended?: false, verified?: true,
    )
  end

  # String keys throughout: the session blob round-trips through JSON.
  let(:session) { { 'external_id' => 'ur_colonel', 'role' => 'colonel' } }

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(target).to receive(:role?).with('colonel').and_return(false)
    allow(colonel).to receive(:role?).with('colonel').and_return(true)
    described_class.clear_context
  end

  after { described_class.clear_context }

  def start!
    described_class.start!(session, target: target, reason: 'ticket #123')
  end

  describe '.start!' do
    it 'writes a marker with a correlation id and a fixed expiry' do
      marker = start!

      expect(marker['id']).to match(/\Aimp_[0-9a-f]{16}\z/)
      expect(marker['target_extid']).to eq('ur_target')
      expect(marker['target_email']).to eq('alice@example.com')
      expect(marker['reason']).to eq('ticket #123')
      expect(marker['started_at']).to eq(now)
      expect(marker['expires_at']).to eq(now + described_class::TTL)
    end

    it 'stores the marker under the session key' do
      marker = start!

      expect(session[described_class::SESSION_KEY]).to eq(marker)
    end

    # The whole safety argument rests on this line.
    it 'leaves external_id and role pointing at the colonel' do
      start!

      expect(session['external_id']).to eq('ur_colonel')
      expect(session['role']).to eq('colonel')
    end

    it 'takes no TTL from the caller' do
      expect(described_class.method(:start!).parameters.map(&:last))
        .to contain_exactly(:session, :target, :reason)
    end

    it 'round-trips through JSON unchanged' do
      marker = start!

      expect(JSON.parse(JSON.generate(marker))).to eq(marker)
    end
  end

  describe '.active' do
    it 'returns the live marker' do
      marker = start!

      expect(described_class.active(session)).to eq(marker)
    end

    it 'returns nil for a session with no marker' do
      expect(described_class.active({})).to be_nil
    end

    it 'returns nil for a nil session' do
      expect(described_class.active(nil)).to be_nil
    end

    it 'ignores a malformed marker rather than trusting it' do
      session[described_class::SESSION_KEY] = { 'target_extid' => '' }

      expect(described_class.active(session)).to be_nil
    end

    context 'when past expires_at' do
      before do
        start!
        allow(Familia).to receive(:now).and_return(now + described_class::TTL + 1)
      end

      it 'answers nil' do
        expect(described_class.active(session)).to be_nil
      end

      it 'clears the marker' do
        described_class.active(session)

        expect(session).not_to have_key(described_class::SESSION_KEY)
      end

      it 'audits the stop as expired' do
        described_class.active(session)

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: 'ur_colonel',
          verb: 'customer.impersonate.stop',
          target: 'ur_target',
          result: :success,
          detail: hash_including(ended_by: 'expired'),
        )
      end

      it 'audits exactly once even when read twice in a request' do
        described_class.active(session)
        described_class.active(session)

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      end
    end
  end

  describe '.stop!' do
    it 'clears the marker and records one stop event with the duration' do
      marker = start!
      allow(Familia).to receive(:now).and_return(now + 90)

      expect(described_class.stop!(session)).to eq(marker)
      expect(session).not_to have_key(described_class::SESSION_KEY)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_colonel',
        verb: 'customer.impersonate.stop',
        target: 'ur_target',
        result: :success,
        detail: { impersonation_id: marker['id'], ended_by: 'operator', duration_s: 90 },
      )
    end

    it 'is a silent no-op when nothing is active' do
      expect(described_class.stop!(session)).to be_nil
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe '.resolve' do
    before { start! }

    context 'when everything still holds' do
      before { allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target) }

      it 'answers the TARGET plus the marker' do
        effective, marker = described_class.resolve(session, colonel)

        expect(effective).to be(target)
        expect(marker['target_extid']).to eq('ur_target')
      end

      it 'keeps the marker in place' do
        described_class.resolve(session, colonel)

        expect(session).to have_key(described_class::SESSION_KEY)
      end
    end

    # The four fall-through cases. Each ends the OVERLAY and returns the
    # PRINCIPAL — never nil, never an exception.
    {
      'colonel_demoted' => :demoted,
      'target_missing' => :missing,
      'target_suspended' => :suspended,
      'target_privileged' => :privileged,
    }.each do |ended_by, scenario|
      context "when the target/principal becomes #{ended_by}" do
        before do
          case scenario
          when :demoted
            allow(colonel).to receive(:role?).with('colonel').and_return(false)
            allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
          when :missing
            allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
          when :suspended
            allow(target).to receive(:suspended?).and_return(true)
            allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
          when :privileged
            allow(target).to receive(:role?).with('colonel').and_return(true)
            allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
          end
        end

        it 'falls through to the principal with no marker' do
          effective, marker = described_class.resolve(session, colonel)

          expect(effective).to be(colonel)
          expect(marker).to be_nil
        end

        it 'ends the impersonation and records why' do
          described_class.resolve(session, colonel)

          expect(session).not_to have_key(described_class::SESSION_KEY)
          expect(Onetime::ColonelAuditEvent).to have_received(:record)
            .with(hash_including(detail: hash_including(ended_by: ended_by)))
        end
      end
    end

    it 'ends the overlay when the principal is an unverified colonel' do
      allow(colonel).to receive(:verified?).and_return(false)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)

      effective, = described_class.resolve(session, colonel)

      expect(effective).to be(colonel)
      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(detail: hash_including(ended_by: 'colonel_demoted')))
    end

    it 'answers the principal when nothing is impersonated' do
      described_class.clear!(session)

      expect(described_class.resolve(session, colonel)).to eq([colonel, nil])
    end

    it 'falls back to the principal rather than raising when the lookup blows up' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_raise(StandardError, 'boom')
      allow(OT).to receive(:le)

      expect(described_class.resolve(session, colonel)).to eq([colonel, nil])
    end
  end

  describe 'the per-request target memo' do
    before do
      start!
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    end

    it 'costs one load per request even though resolve reads the target twice' do
      env = {}

      described_class.resolve(session, colonel, env: env)

      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).once
      expect(env[described_class::TARGET_ENV_KEY]).to eq(['ur_target', target])
    end

    it 'reloads on every resolve when no env is supplied' do
      2.times { described_class.resolve(session, colonel) }

      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).exactly(4).times
    end

    # A cached nil is an ANSWER (the target was deleted), not a cache miss.
    it 'caches a missing target instead of re-querying it' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      env = {}

      described_class.resolve(session, colonel, env: env)

      expect(env[described_class::TARGET_ENV_KEY]).to eq(['ur_target', nil])
      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).once
    end

    # The memo is keyed on the marker's target, so a stale entry from a
    # different impersonation can never be served.
    it 'ignores a memo belonging to another target' do
      env = { described_class::TARGET_ENV_KEY => ['ur_someone_else', :stale] }

      effective, = described_class.resolve(session, colonel, env: env)

      expect(effective).to be(target)
      expect(env[described_class::TARGET_ENV_KEY]).to eq(['ur_target', target])
    end

    it 'primes the memo without a principal via .preload_target' do
      env    = {}
      marker = described_class.active(session)

      expect(described_class.preload_target(env, marker)).to be(target)
      expect(env[described_class::TARGET_ENV_KEY]).to eq(['ur_target', target])
    end
  end

  describe 'request context' do
    it 'publishes the marker plus the principal for the bootstrap payload' do
      marker = start!
      described_class.set_context(marker, impersonator_extid: 'ur_colonel')

      expect(described_class.context).to eq(
        'impersonation_id' => marker['id'],
        'impersonator_extid' => 'ur_colonel',
        'target_extid' => 'ur_target',
        'target_email' => 'alice@example.com',
        'started_at' => now,
        'expires_at' => now + described_class::TTL,
      )
    end

    # `reason` is operator-entered free text and stays out of the wire payload.
    it 'omits the reason' do
      described_class.set_context(start!, impersonator_extid: 'ur_colonel')

      expect(described_class.context).not_to have_key('reason')
    end

    it 'is frozen and cleared on demand' do
      described_class.set_context(start!, impersonator_extid: 'ur_colonel')

      expect(described_class.context).to be_frozen
      expect(described_class.active_context?).to be true

      described_class.clear_context
      expect(described_class.context).to be_nil
      expect(described_class.active_context?).to be false
    end
  end
end
