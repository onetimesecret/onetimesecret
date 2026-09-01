# apps/web/auth/spec/operations/customers/impersonate_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Impersonate.
#
# Covers: successful grant issuance (+ exactly one audit event that records the
# NON-SECRET grant_id, never the bearer token), the ADR-023 missing-actor
# refusal, the missing-reason refusal, the colonel privilege guard, the
# anonymous-target guard, and TTL clamping passthrough. The grant model is
# injected as a double so no datastore is touched.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/impersonate_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/impersonate'

RSpec.describe Auth::Operations::Customers::Impersonate do
  let(:customer) do
    double(
      'Customer',
      role: 'customer',
      extid: 'ur_target',
      email: 'alice@example.com',
      anonymous?: false,
    )
  end

  # Stand-in for Onetime::ImpersonationGrant. Exposes the class-level constants
  # and methods the op reads (DEFAULT_TTL, clamp_ttl, issue) plus a grant double.
  let(:grant) do
    double('ImpersonationGrant', token: 'secret-bearer-token', grant_id: 'grant-uuid-123')
  end

  # Stand-in for the Onetime::ImpersonationGrant class. clamp_ttl mirrors the
  # real semantics (nil / non-positive -> DEFAULT_TTL 120, else clamped 30..600)
  # so the op's nil-default handling is exercised without the real constant.
  let(:grant_model) do
    model = double('ImpersonationGrant class')
    allow(model).to receive(:clamp_ttl) { |ttl| ttl.to_i <= 0 ? 120 : ttl.to_i.clamp(30, 600) }
    allow(model).to receive(:issue).and_return(grant)
    model
  end

  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

  describe 'successful issuance' do
    subject(:result) do
      described_class.new(
        customer: customer,
        actor: 'ur_operator',
        reason: 'ticket #123',
        ttl: 300,
        grant_model: grant_model,
      ).call
    end

    it 'issues a grant scoped to the target and operator' do
      result
      expect(grant_model).to have_received(:issue).with(
        target_extid: 'ur_target',
        target_email: 'alice@example.com',
        actor: 'ur_operator',
        reason: 'ticket #123',
        ttl: 300,
      )
    end

    it 'returns :issued with the bearer token, grant_id, and clamped ttl' do
      expect(result.status).to eq(:issued)
      expect(result.token).to eq('secret-bearer-token')
      expect(result.grant_id).to eq('grant-uuid-123')
      expect(result.actor).to eq('ur_operator')
      expect(result.expires_in).to eq(300)
    end

    it 'records exactly one audit event with grant_id and reason, NEVER the token' do
      result
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_operator',
        verb: 'customer.impersonate',
        target: 'ur_target',
        result: :success,
        detail: { reason: 'ticket #123', grant_id: 'grant-uuid-123', ttl: 300 },
      )
    end
  end

  describe 'ADR-023 actor requirement' do
    it 'refuses an empty actor and issues no grant' do
      expect do
        described_class.new(
          customer: customer, actor: '', reason: 'x', grant_model: grant_model,
        ).call
      end.to raise_error(described_class::MissingActor)

      expect(grant_model).not_to have_received(:issue)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(hash_including(result: :success))
    end

    it 'refuses a nil actor' do
      expect do
        described_class.new(
          customer: customer, actor: nil, reason: 'x', grant_model: grant_model,
        ).call
      end.to raise_error(described_class::MissingActor)
    end
  end

  describe 'reason requirement' do
    it 'refuses a blank reason and issues no grant' do
      expect do
        described_class.new(
          customer: customer, actor: 'ur_operator', reason: '   ', grant_model: grant_model,
        ).call
      end.to raise_error(described_class::MissingReason)

      expect(grant_model).not_to have_received(:issue)
    end
  end

  describe 'privilege guard' do
    it 'refuses to impersonate a colonel-role account (no grant)' do
      allow(customer).to receive(:role).and_return('colonel')

      expect do
        described_class.new(
          customer: customer, actor: 'ur_operator', reason: 'x', grant_model: grant_model,
        ).call
      end.to raise_error(described_class::PrivilegedTarget)

      expect(grant_model).not_to have_received(:issue)
    end
  end

  describe 'anonymous guard' do
    it 'refuses an anonymous target (no grant)' do
      allow(customer).to receive(:anonymous?).and_return(true)

      expect do
        described_class.new(
          customer: customer, actor: 'ur_operator', reason: 'x', grant_model: grant_model,
        ).call
      end.to raise_error(described_class::AnonymousTarget)

      expect(grant_model).not_to have_received(:issue)
    end
  end

  describe 'ttl handling' do
    it 'clamps an oversized ttl through the model before issuing' do
      described_class.new(
        customer: customer, actor: 'ur_operator', reason: 'x', ttl: 99_999,
        grant_model: grant_model,
      ).call

      expect(grant_model).to have_received(:issue).with(hash_including(ttl: 600))
    end

    it 'defaults ttl when none is supplied' do
      described_class.new(
        customer: customer, actor: 'ur_operator', reason: 'x', grant_model: grant_model,
      ).call

      expect(grant_model).to have_received(:issue).with(hash_including(ttl: 120))
    end
  end
end
