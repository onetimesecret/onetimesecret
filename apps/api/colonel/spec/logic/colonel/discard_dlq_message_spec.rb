# apps/api/colonel/spec/logic/colonel/discard_dlq_message_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/queues/dlq/:queue/messages/:message_id/discard (#4343) —
# irreversible single-message loss, TIER 1: the per-message twin of PurgeDlq,
# with the same token (the queue name), elevation, and the tight budget
# charged last. The op itself (scan, confirmed ack, fail-closed audit) is
# covered in spec/unit/onetime/operations/dlq/discard_spec.rb; here it is a
# double.
RSpec.describe ColonelAPI::Logic::Colonel::DiscardDlqMessage do
  let(:queue) { 'dlq.billing.event' }
  let(:short_name) { 'billing.event' }
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

  def op_result(status: :success, found: true, outcome: nil, scanned: 2, truncated: false, error: nil)
    Onetime::Operations::Dlq::Discard::Result.new(
      status: status, queue: queue, message_id: message_id, found: found, outcome: outcome,
      original_queue: found ? 'billing.event.process' : nil, scanned: scanned, truncated: truncated, error: error,
    )
  end

  let(:op) { instance_double(Onetime::Operations::Dlq::Discard, call: op_result) }

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
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

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Operations::Dlq::Discard).to receive(:new).and_return(op)
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

    it 'discards nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::Dlq::Discard).not_to have_received(:new)
    end

    it 'does not accept the message id as the token' do
      expect { logic_for(colonel, message_id).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'elevation (#4327)' do
    let(:expected_confirm_token) { short_name }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session),
        { 'queue' => short_name, 'message_id' => message_id },
      )
    end

    it_behaves_like 'an elevated colonel action'
  end

  describe 'destructive budget (#4329)' do
    it 'charges the tight bucket after the gate passes' do
      logic = logic_for
      allow(logic).to receive(:enforce_colonel_destructive_limit!)

      logic.raise_concerns

      expect(logic).to have_received(:enforce_colonel_destructive_limit!).with('ur_colonel').once
    end

    it 'does not charge it for a refused confirmation' do
      logic = logic_for(colonel, nil)
      allow(logic).to receive(:enforce_colonel_destructive_limit!)

      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    it 'does not charge it for a dry run' do
      logic = logic_for(colonel, nil, 'dry_run' => 'true')
      allow(logic).to receive(:enforce_colonel_destructive_limit!)

      logic.raise_concerns

      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end
  end

  describe 'preview exemption' do
    it 'needs no confirmation for a dry run, and says so in the record' do
      allow(op).to receive(:call).and_return(op_result(status: :dry_run))
      logic = logic_for(colonel, nil, 'dry_run' => 'true')

      expect { logic.raise_concerns }.not_to raise_error
      data = logic.process
      expect(data[:record]).to include(dry_run: true, discarded: false, found: true)
      expect(data[:details][:message]).to eq('1 message would be discarded')
      expect(Onetime::Operations::Dlq::Discard).to have_received(:new).with(hash_including(dry_run: true))
    end

    it 'still requires it when dry_run is absent (this verb defaults to APPLY)' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'guard order' do
    it 'rejects an unknown queue with 404 BEFORE the confirmation gate' do
      expect { logic_for(colonel, nil, 'queue' => 'not-a-queue').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown dead-letter queue/)
    end

    it 'requires a message id' do
      expect { logic_for(colonel, short_name, 'message_id' => '%%%').raise_concerns }
        .to raise_error(Onetime::FormError, /Message id is required/)
    end

    it 'answers 422 when the broker is not connected' do
      $rmq_conn = double('BunnyConnection', open?: false)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::FormError, /not connected/)
    end

    it 'rejects a non-colonel before any of them' do
      expect { logic_for(customer, nil, 'queue' => 'not-a-queue').raise_concerns }
        .to raise_error(Onetime::Forbidden)
    end
  end

  describe 'process' do
    it 'hands the op the resolved queue, the message id, the colonel extid and the reason' do
      logic = logic_for(colonel, short_name, 'reason' => 'poison message')
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Dlq::Discard).to have_received(:new).with(
        connection: $rmq_conn, queue: queue, message_id: message_id,
        actor: 'ur_colonel', dry_run: false, reason: 'poison message',
      )
    end

    it 'answers the contract shape on a hit' do
      logic = logic_for
      logic.raise_concerns

      expect(logic.process).to eq(
        record: {
          queue: queue, message_id: message_id, found: true, outcome: nil, scanned: 2, truncated: false,
          discarded: true, original_queue: 'billing.event.process', dry_run: false,
        },
        details: { message: 'Discarded message' },
      )
    end

    it 'answers 200 with outcome not_visible on a miss' do
      allow(op).to receive(:call)
        .and_return(op_result(status: :not_visible, found: false, outcome: 'not_visible', scanned: 500, truncated: true))
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:record]).to include(found: false, outcome: 'not_visible', discarded: false,
        original_queue: nil, scanned: 500, truncated: true)
      expect(data[:details][:message]).to include('not visible', 'stopped at the scan limit')
    end

    it 'passes an unconfirmed drop through as not discarded, with the reason' do
      allow(op).to receive(:call).and_return(op_result(status: :unconfirmed, outcome: 'unconfirmed', error: 'Discard outcome unknown: x'))
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:record]).to include(discarded: false, outcome: 'unconfirmed')
      expect(data[:details][:message]).to eq('Discard outcome unknown: x')
    end
  end
end
