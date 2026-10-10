# apps/api/colonel/spec/logic/colonel/replay_dlq_message_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/queues/dlq/:queue/messages/:message_id/replay (#4343) —
# TIER 2, like the queue-level ReplayDlq: confirmation (the queue name) only,
# no elevation, no destructive budget. The op (scan, transaction, email DLQ
# reservation, audit) is covered in
# spec/unit/onetime/operations/dlq/replay_message_spec.rb; here it is a double.
RSpec.describe ColonelAPI::Logic::Colonel::ReplayDlqMessage do
  let(:queue) { 'dlq.email.message' }
  let(:short_name) { 'email.message' }
  let(:message_id) { '6f1c2d3e-0000-4000-8000-00000000abcd' }

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

  def op_result(status: :success, replayed: 1, failed: 0, errors: [], would_replay: 0,
                found: true, outcome: nil, scanned: 1, truncated: false)
    Onetime::Operations::Dlq::Replay::Result.new(
      status: status, queue: queue, replayed: replayed, failed: failed, errors: errors,
      would_replay: would_replay, message_id: message_id, found: found, outcome: outcome,
      scanned: scanned, truncated: truncated,
    )
  end

  let(:op) { instance_double(Onetime::Operations::Dlq::Replay, call: op_result) }

  def strategy_result_for(user, confirm_token, session = {})
    double('StrategyResult', session: session, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = short_name, params = {})
    described_class.new(
      strategy_result_for(user, confirm_token),
      { 'queue' => short_name, 'message_id' => message_id }.merge(params),
    )
  end

  def processed(logic = logic_for)
    logic.raise_concerns
    logic.process
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Operations::Dlq::Replay).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    $rmq_conn = double('BunnyConnection', open?: true)
  end

  after { $rmq_conn = nil }

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { short_name }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'replays nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::Dlq::Replay).not_to have_received(:new)
    end
  end

  it 'does not charge the destructive budget (tier 2)' do
    logic = logic_for
    allow(logic).to receive(:enforce_colonel_destructive_limit!)

    logic.raise_concerns

    expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
  end

  it 'needs no confirmation for a dry run' do
    allow(op).to receive(:call).and_return(op_result(status: :dry_run, replayed: 0, would_replay: 1))
    data = processed(logic_for(colonel, nil, 'dry_run' => 'true'))

    expect(data[:record]).to include(dry_run: true, would_replay: 1, found: true)
    expect(data[:details][:message]).to eq('1 message would be replayed')
  end

  describe 'guard order' do
    it 'rejects an unknown queue with 404 BEFORE the confirmation gate' do
      expect { logic_for(colonel, nil, 'queue' => 'not-a-queue').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown dead-letter queue/)
    end

    it 'requires a message id' do
      expect { logic_for(colonel, short_name, 'message_id' => '').raise_concerns }
        .to raise_error(Onetime::FormError, /Message id is required/)
    end

    it 'rejects a non-colonel' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'process' do
    it 'hands the op the message id and the reason, never a count' do
      processed(logic_for(colonel, short_name, 'reason' => 'customer waiting on reset email'))

      expect(Onetime::Operations::Dlq::Replay).to have_received(:new).with(
        connection: $rmq_conn, queue: queue, message_id: message_id, actor: 'ur_colonel',
        dry_run: false, reason: 'customer waiting on reset email',
      )
    end

    it 'answers the contract shape on a hit' do
      expect(processed).to eq(
        record: {
          queue: queue, message_id: message_id, found: true, outcome: nil, scanned: 1, truncated: false,
          replayed: 1, failed: 0, would_replay: 0, dry_run: false,
        },
        details: { message: 'Replayed message', errors: [] },
      )
    end

    it 'answers 200 with outcome not_visible on a miss' do
      allow(op).to receive(:call).and_return(
        op_result(status: :not_visible, replayed: 0, found: false, outcome: 'not_visible', scanned: 3),
      )

      data = processed

      expect(data[:record]).to include(found: false, outcome: 'not_visible', replayed: 0, scanned: 3, truncated: false)
      expect(data[:details][:message]).to include('is not visible in dlq.email.message (scanned 3 message(s))')
    end

    it 'passes an email DLQ refusal through with its reason' do
      error = 'Not republished: the email DLQ consumer already republished this message id.'
      allow(op).to receive(:call).and_return(
        op_result(status: :refused, replayed: 0, outcome: 'already_replayed',
          errors: [{ message_id: message_id, error: error }]),
      )

      data = processed

      expect(data[:record]).to include(found: true, outcome: 'already_replayed', replayed: 0, failed: 0)
      expect(data[:details][:message]).to eq(error)
    end

    it 'reports a failed replay with its error' do
      allow(op).to receive(:call).and_return(
        op_result(replayed: 0, failed: 1, errors: [{ message_id: message_id, error: 'publish refused' }]),
      )

      data = processed

      expect(data[:details]).to eq(message: 'Replay failed', errors: [{ message_id: message_id, error: 'publish refused' }])
    end
  end
end
