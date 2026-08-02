# apps/api/colonel/spec/logic/colonel/delete_secret_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/secrets/:secret_id was the only destructive colonel route
# with no audit trail — purge, domain remove, session delete and DLQ purge all
# record. These examples pin the trail this adapter now owns: the exact verb,
# a PUBLIC target, an objid-free payload, the failure event, and the fact that
# an authorization rejection writes nothing.
RSpec.describe ColonelAPI::Logic::Colonel::DeleteSecret do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  let(:secret) do
    instance_double(Onetime::Secret,
      exists?: true,
      objid: 'sec_internal_objid_do_not_leak',
      shortid: 'sec12345',
      state: 'new',
      owner_id: 'cust_owner_internal',
      receipt_identifier: 'rec_internal_objid',
      destroy!: true)
  end

  let(:receipt) do
    instance_double(Onetime::Receipt,
      exists?: true,
      objid: 'rec_internal_objid',
      shortid: 'rec98765',
      destroy!: true)
  end

  def strategy_result_for(user)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: {})
  end

  def logic_for(user = colonel)
    described_class.new(strategy_result_for(user), { 'secret_id' => 'sec12345abcdef' })
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Secret).to receive(:load).and_return(secret)
    allow(Onetime::Receipt).to receive(:load).and_return(receipt)
    allow(Onetime::AdminAuditEvent).to receive(:record)
  end

  describe 'success path' do
    it 'records exactly one secret.delete event with the acting colonel as actor' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'ur_colonel',
          verb: 'secret.delete',
          target: 'sec12345',
          result: :success,
        ),
      )
    end

    it 'keeps internal objids out of the audit payload (target and detail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      payload = nil
      expect(Onetime::AdminAuditEvent).to have_received(:record) { |args| payload = args }

      serialized = [payload[:target], payload[:detail]].inspect
      expect(serialized).not_to include('sec_internal_objid_do_not_leak')
      expect(serialized).not_to include('rec_internal_objid')
      expect(serialized).not_to include('cust_owner_internal')
      expect(payload[:detail]).to eq(state: 'new', receipt_shortid: 'rec98765')
    end

    it 'still returns the incumbent response shape (unchanged public API)' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:deleted]).to be true
      expect(data[:record][:secret][:shortid]).to eq('sec12345')
      expect(data[:record][:metadata][:shortid]).to eq('rec98765')
    end
  end

  describe 'failure path (Onetime::AuditedFailure)' do
    it 'records result: :failure when the destroy raises, and re-raises' do
      allow(secret).to receive(:destroy!).and_raise(Familia::Problem, 'datastore exploded')

      logic = logic_for
      logic.raise_concerns

      expect { logic.process }.to raise_error(Familia::Problem, 'datastore exploded')

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'ur_colonel',
          verb: 'secret.delete',
          target: 'sec12345',
          result: :failure,
          detail: hash_including(error: 'Familia::Problem'),
        ),
      )
    end
  end

  describe 'authorization rejection' do
    # The hard constraint: the audit set is capped by count with no TTL, so a
    # rejection that writes an event is a log-eviction primitive. The check
    # lives in raise_concerns, which Otto runs BEFORE the audited #process —
    # structurally outside the recorded region.
    it 'writes NO event when a non-colonel is refused' do
      logic = logic_for(customer)

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end
end
