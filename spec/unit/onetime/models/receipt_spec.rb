# spec/unit/onetime/models/receipt_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Receipt.spawn_pair
#
# spawn_pair populates every field of the linked pair before it commits them,
# with the caller's required registrations, in one Familia.atomic_write
# (docs/specs/api/01-creation-commit.md). These examples stub that write to
# observe what it receives and how each failure is classified;
# spec/api/v3/api_v3_creation_commit_spec.rb exercises it against Valkey.
#
RSpec.describe Onetime::Receipt do
  describe '.spawn_pair' do
    let(:owner_id)   { 'testuser@example.com' }
    let(:lifespan)   { 86_400 } # 1 day in seconds
    let(:content)    { 'super secret content' }
    let(:domain)     { 'secrets.example.com' }
    let(:kind)       { 'share' }
    let(:commits)    { [] }

    # Stubs for Redis-backed operations that spawn_pair touches.
    # We allow real Ruby field assignment but intercept persistence.
    before do
      # Record each commit's instances and run its registrations block, as
      # Familia.atomic_write does inside the MULTI, without touching Redis.
      allow(Familia).to receive(:atomic_write) do |*instances, &registrations|
        commits << instances
        registrations&.call
        true
      end

      # The ciphertext= setter is an encrypted_field that triggers Familia's
      # encryption pipeline, requiring key version config. Stub it to no-op
      # since we're testing receipt field population, not encryption.
      allow_any_instance_of(Onetime::Secret).to receive(:ciphertext=).and_return(nil)

      # update_passphrase writes passphrase fields; stub it to be a no-op
      # but still allow the receipt's has_passphrase to be set by spawn_pair.
      allow_any_instance_of(Onetime::Secret).to receive(:update_passphrase).and_return(true)

      # Post-commit follow-ups touch class-level sorted sets and counters.
      allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications).and_return(false)
      allow(Onetime::Customer).to receive(:increment_secrets_active)
      allow(Onetime::DailyMetric).to receive(:increment)
    end

    # -----------------------------------------------------------
    # 1. One commit for the pair
    # -----------------------------------------------------------
    context 'commit' do
      it 'writes the secret and receipt in exactly one atomic write' do
        receipt, secret = Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)

        expect(commits).to eq([[secret, receipt]])
      end

      it 'never saves either record outside that write' do
        allow_any_instance_of(Onetime::Receipt).to receive(:save).and_raise('unexpected receipt save')
        allow_any_instance_of(Onetime::Secret).to receive(:save).and_raise('unexpected secret save')

        expect { Onetime::Receipt.spawn_pair(owner_id, lifespan, content) }.not_to raise_error
      end

      it 'runs the caller registrations inside the commit with the pending pair' do
        registered = nil
        committing = nil
        receipt, secret = Onetime::Receipt.spawn_pair(owner_id, lifespan, content) do |pending_receipt, pending_secret|
          registered = [pending_receipt, pending_secret]
          committing = commits.size
        end

        expect(registered).to eq([receipt, secret])
        expect(committing).to eq(1)
      end
    end

    # -----------------------------------------------------------
    # 2. Field completeness
    # -----------------------------------------------------------
    context 'receipt field population' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }
      let(:secret)  { pair[1] }

      it 'sets secret_identifier to the secret objid' do
        expect(receipt.secret_identifier).to eq(secret.objid)
      end

      it 'sets secret_shortid to the secret shortid' do
        expect(receipt.secret_shortid).to eq(secret.shortid)
      end

      it 'sets secret_ttl to the lifespan argument' do
        expect(receipt.secret_ttl.to_i).to eq(lifespan)
      end

      it 'sets lifespan to the lifespan argument' do
        expect(receipt.lifespan.to_i).to eq(lifespan)
      end

      it 'sets share_domain to the domain argument' do
        expect(receipt.share_domain).to eq(domain)
      end

      it 'sets kind to the kind argument' do
        expect(receipt.kind).to eq(kind)
      end

      it 'sets the scope identifiers given as keywords' do
        receipt, = Onetime::Receipt.spawn_pair(owner_id, lifespan, content, org_id: 'org-objid', domain_id: 'domain-objid')

        expect(receipt.org_id).to eq('org-objid')
        expect(receipt.domain_id).to eq('domain-objid')
      end
    end

    context 'when a passphrase is provided' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          passphrase: 'hunter2', domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }

      it 'sets has_passphrase on the receipt' do
        expect(receipt.has_passphrase).to be true
      end
    end

    context 'when no passphrase is provided' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(
          owner_id, lifespan, content,
          domain: domain, kind: kind
        )
      end

      let(:receipt) { pair[0] }

      it 'does not set has_passphrase on the receipt' do
        expect(receipt.has_passphrase).to be_nil
      end
    end

    # -----------------------------------------------------------
    # 3. Mutual linking
    # -----------------------------------------------------------
    context 'mutual linking between receipt and secret' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)
      end

      let(:receipt) { pair[0] }
      let(:secret)  { pair[1] }

      it 'links receipt.secret_identifier to secret.objid' do
        expect(receipt.secret_identifier).to eq(secret.objid)
      end

      it 'links secret.receipt_identifier to receipt.objid' do
        expect(secret.receipt_identifier).to eq(receipt.objid)
      end
    end

    # -----------------------------------------------------------
    # 4. Return value
    # -----------------------------------------------------------
    context 'return value' do
      subject(:pair) do
        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)
      end

      it 'returns a two-element array' do
        expect(pair).to be_an(Array)
        expect(pair.size).to eq(2)
      end

      it 'returns a Receipt as the first element' do
        expect(pair[0]).to be_a(Onetime::Receipt)
      end

      it 'returns a Secret as the second element' do
        expect(pair[1]).to be_a(Onetime::Secret)
      end
    end

    # -----------------------------------------------------------
    # 5. All fields set BEFORE the commit
    # -----------------------------------------------------------
    # The commit is the only write, so every receipt-level field must already
    # be populated when it runs; nothing is filled in by a later save.
    context 'field completeness at commit time' do
      it 'has all fields populated when the commit runs' do
        committed_fields = nil

        allow(Familia).to receive(:atomic_write) do |_secret, receipt_instance, &_registrations|
          committed_fields = {
            secret_ttl: receipt_instance.secret_ttl,
            lifespan: receipt_instance.lifespan,
            share_domain: receipt_instance.share_domain,
            kind: receipt_instance.kind,
            secret_shortid: receipt_instance.secret_shortid,
            secret_identifier: receipt_instance.secret_identifier,
            default_expiration: receipt_instance.default_expiration,
          }
          true
        end

        Onetime::Receipt.spawn_pair(owner_id, lifespan, content, domain: domain, kind: kind)

        expect(committed_fields[:secret_ttl]).to eq(lifespan)
        expect(committed_fields[:lifespan]).to eq(lifespan)
        expect(committed_fields[:share_domain]).to eq(domain)
        expect(committed_fields[:kind]).to eq(kind)
        expect(committed_fields[:secret_shortid]).not_to be_nil
        expect(committed_fields[:secret_identifier]).not_to be_nil
        expect(committed_fields[:default_expiration]).to eq(lifespan * 2)
      end
    end

    # -----------------------------------------------------------
    # 6. Failure evidence
    # -----------------------------------------------------------
    # An error never proves rollback: only a datastore verdict makes a failed
    # commit :incomplete, and anything else stays :unconfirmed.
    context 'when the creation does not commit' do
      let(:logger) { instance_spy(SemanticLogger::Logger) }

      before { allow(Onetime).to receive(:secret_logger).and_return(logger) }

      def expect_creation_failure(stage, persistence, cause_class = nil, &block)
        expect(&block).to raise_error(Onetime::SecretCreationFailed) do |error|
          expect(error.stage).to eq(stage)
          expect(error.persistence).to eq(persistence)
          cause_class ? expect(error.cause).to(be_a(cause_class)) : expect(error.cause).to(be_nil)
        end
      end

      it 'classifies a rejected command as incomplete' do
        allow(Familia).to receive(:atomic_write).and_raise(Redis::WrongTypeError, 'WRONGTYPE injected')

        expect_creation_failure(:commit, :incomplete, Redis::WrongTypeError) do
          Onetime::Receipt.spawn_pair(owner_id, lifespan, content)
        end
      end

      it 'classifies a commit reporting failed commands as incomplete' do
        allow(Familia).to receive(:atomic_write).and_return(false)

        expect_creation_failure(:commit, :incomplete) do
          Onetime::Receipt.spawn_pair(owner_id, lifespan, content)
        end
      end

      [Redis::TimeoutError, Redis::ConnectionError, IOError].each do |error_class|
        it "classifies #{error_class} as unconfirmed" do
          allow(Familia).to receive(:atomic_write).and_raise(error_class, 'injected')

          expect_creation_failure(:commit, :unconfirmed, error_class) do
            Onetime::Receipt.spawn_pair(owner_id, lifespan, content)
          end
        end
      end

      it 'classifies a preparation failure as no write, without committing' do
        allow_any_instance_of(Onetime::Secret).to receive(:update_passphrase).and_raise(ArgumentError, 'injected')

        expect_creation_failure(:prepare, :none, ArgumentError) do
          Onetime::Receipt.spawn_pair(owner_id, lifespan, content, passphrase: 'hunter2')
        end
        expect(Familia).not_to have_received(:atomic_write)
      end

      it 'skips every optional follow-up' do
        allow(Familia).to receive(:atomic_write).and_raise(Redis::TimeoutError, 'injected')

        expect { Onetime::Receipt.spawn_pair(owner_id, lifespan, content) }
          .to raise_error(Onetime::SecretCreationFailed)
        expect(Onetime::Customer).not_to have_received(:increment_secrets_active)
        expect(Onetime::DailyMetric).not_to have_received(:increment)
      end

      it 'logs the stage and evidence with shortids only' do
        receipt = nil
        allow(Familia).to receive(:atomic_write) do |_secret, pending_receipt|
          receipt = pending_receipt
          raise Redis::TimeoutError, 'injected'
        end

        expect { Onetime::Receipt.spawn_pair(owner_id, lifespan, content) }
          .to raise_error(Onetime::SecretCreationFailed)
        expect(logger).to have_received(:error).with(
          'Secret creation failed',
          {
            stage: 'commit',
            persistence: 'unconfirmed',
            receipt: receipt.shortid,
            secret: receipt.secret_shortid,
            error: 'Redis::TimeoutError',
          },
        )
      end
    end

    # -----------------------------------------------------------
    # 7. Optional follow-ups
    # -----------------------------------------------------------
    context 'when an optional follow-up fails after the commit' do
      let(:logger) { instance_spy(SemanticLogger::Logger) }

      before do
        allow(Onetime).to receive(:secret_logger).and_return(logger)
        allow_any_instance_of(Onetime::Receipt).to receive(:register_for_expiration_notifications)
          .and_raise(IOError, 'injected follow-up failure')
      end

      it 'returns the committed pair and logs the failure' do
        receipt, secret = Onetime::Receipt.spawn_pair(owner_id, lifespan, content)

        expect(commits).to eq([[secret, receipt]])
        expect(Onetime::Customer).to have_received(:increment_secrets_active)
        expect(Onetime::DailyMetric).to have_received(:increment).with(:secrets_created)
        expect(logger).to have_received(:error).with(
          'Secret creation follow-up failed',
          {
            followup: 'expiration_notifications',
            stage: 'followup',
            persistence: 'committed',
            receipt: receipt.shortid,
            error: 'IOError',
          },
        )
      end
    end
  end

  # Shared by V2/V3 ShowReceipt (show_secret) and BurnSecret, so a burn that
  # does not commit and a later fetch agree on secret_identifier (#4835).
  describe '#offers_secret?' do
    let(:receipt) { described_class.new(state: 'new') }
    let(:secret)  { double('Onetime::Secret', has_passphrase?: false) }

    it 'is true for a live receipt whose secret has no passphrase' do
      expect(receipt.offers_secret?(secret)).to be true
    end

    it 'is false when the secret is gone' do
      expect(receipt.offers_secret?(nil)).to be false
    end

    it 'is false when the secret has a passphrase' do
      allow(secret).to receive(:has_passphrase?).and_return(true)

      expect(receipt.offers_secret?(secret)).to be false
    end

    described_class::SECRET_WITHDRAWN_STATES.each do |withdrawn|
      it "is false in state #{withdrawn}" do
        receipt.state = withdrawn

        expect(receipt.offers_secret?(secret)).to be false
      end
    end

    it 'withdraws the secret in every terminal state' do
      expect(described_class::SECRET_WITHDRAWN_STATES).to include(*described_class::TERMINAL_STATES)
    end
  end
end
