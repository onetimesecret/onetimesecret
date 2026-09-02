# apps/web/auth/spec/operations/customers/stop_impersonation_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::StopImpersonation.
#
# The op is thin on purpose — the audit lives in the primitive so the expiry
# path produces the identical event. These examples pin exactly that: the op
# reports, the primitive records, and stopping nothing is silent.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/stop_impersonation_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/impersonate'
require 'auth/operations/customers/stop_impersonation'

RSpec.describe Auth::Operations::Customers::StopImpersonation do
  let(:now) { 1_756_700_000 }

  let(:customer) do
    double(
      'Customer',
      role: 'customer', extid: 'ur_target', email: 'alice@example.com',
      anonymous?: false, suspended?: false,
    )
  end

  let(:session) { { 'external_id' => 'ur_operator', 'role' => 'colonel' } }

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::EntitlementPreview).to receive(:clear_session!)
  end

  def start_impersonation
    Auth::Operations::Customers::Impersonate.new(
      customer: customer, actor: 'ur_operator', reason: 'ticket #123', session: session,
    ).call
  end

  context 'with an active impersonation' do
    let!(:started) { start_impersonation }

    it 'reports :stopped and names the target the console returns to' do
      result = described_class.new(session: session, actor: 'ur_operator').call

      expect(result.status).to eq(:stopped)
      expect(result.target_extid).to eq('ur_target')
      expect(result.impersonation_id).to eq(started.impersonation_id)
      expect(result.ended_by).to eq('operator')
    end

    it 'removes the marker' do
      described_class.new(session: session, actor: 'ur_operator').call

      expect(session).not_to have_key(Onetime::SessionImpersonation::SESSION_KEY)
    end

    it 'records exactly one stop event, with the duration' do
      allow(Familia).to receive(:now).and_return(now + 120)

      described_class.new(session: session, actor: 'ur_operator').call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_operator',
        verb: 'customer.impersonate.stop',
        target: 'ur_target',
        result: :success,
        detail: {
          impersonation_id: started.impersonation_id,
          ended_by: 'operator',
          duration_s: 120,
        },
      )
    end

    # The audit actor comes from the SESSION, not from this argument, so an
    # adapter cannot mis-attribute the trail.
    it 'audits the session principal even when handed a different actor' do
      described_class.new(session: session, actor: 'ur_someone_else').call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'customer.impersonate.stop', actor: 'ur_operator'),
      )
    end

    it 'carries a non-operator ended_by through to the trail' do
      described_class.new(
        session: session, actor: 'ur_operator',
        ended_by: Onetime::SessionImpersonation::ENDED_BY_TARGET_SUSPENDED,
      ).call

      expect(Onetime::ColonelAuditEvent)
        .to have_received(:record).with(hash_including(detail: hash_including(ended_by: 'target_suspended')))
    end
  end

  context 'with nothing active' do
    it 'reports :no_change and records nothing' do
      result = described_class.new(session: session, actor: 'ur_operator').call

      expect(result.status).to eq(:no_change)
      expect(result.target_extid).to be_nil
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
