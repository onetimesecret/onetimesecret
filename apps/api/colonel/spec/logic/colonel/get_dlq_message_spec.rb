# apps/api/colonel/spec/logic/colonel/get_dlq_message_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# GET /api/colonel/queues/dlq/:queue/messages/:message_id (#4343) — read-only
# full-payload inspect. Unknown queue is 404; a miss on a configured queue is
# 200 with outcome not_visible; a hit records one access observation because
# the payload can carry a customer's email address.
RSpec.describe ColonelAPI::Logic::Colonel::GetDlqMessage do
  let(:queue) { 'dlq.email.message' }
  let(:short_name) { 'email.message' }
  let(:message_id) { '6f1c2d3e-0000-4000-8000-00000000abcd' }
  let(:detail) do
    {
      delivery_tag: 1, message_id: message_id, timestamp: nil, content_type: 'application/json',
      headers: {}, death_info: { original_queue: 'email.message.send' }, payload: { 'raw' => true },
    }
  end

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

  let(:show) do
    instance_double(Onetime::Operations::Dlq::Show,
      call: Onetime::Operations::Dlq::Show::Result.new(
        found: true, empty: false, message: detail, scanned: 4, truncated: false,
      ))
  end

  def logic_for(user = colonel, params = {})
    described_class.new(
      double('StrategyResult', session: {}, user: user, auth_method: 'sessionauth', metadata: {}),
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
    allow(Onetime::Operations::Dlq::Show).to receive(:new).and_return(show)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    $rmq_conn = double('BunnyConnection', open?: true)
  end

  after { $rmq_conn = nil }

  it 'rejects a non-colonel' do
    expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
  end

  it 'answers 404 for a queue outside the allowlist, before touching the broker' do
    expect { logic_for(colonel, 'queue' => 'not-a-queue').raise_concerns }
      .to raise_error(Onetime::RecordNotFound, /Unknown dead-letter queue/)
    expect(Onetime::Operations::Dlq::Show).not_to have_received(:new)
  end

  it 'answers 422 when the broker is not connected' do
    $rmq_conn = double('BunnyConnection', open?: false)

    expect { logic_for.raise_concerns }.to raise_error(Onetime::FormError, /not connected/)
  end

  it 'looks the message up by id on the resolved queue' do
    processed

    expect(Onetime::Operations::Dlq::Show).to have_received(:new)
      .with(connection: $rmq_conn, queue: queue, message_id: message_id)
  end

  it 'returns the full message and the scan facts on a hit' do
    expect(processed).to eq(
      record: { queue: queue, message_id: message_id, found: true, outcome: nil, scanned: 4, truncated: false },
      details: { message: detail },
    )
  end

  it 'records ONE access observation on a hit, never the payload' do
    processed

    expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
      actor: 'ur_colonel', verb: 'queue.dlq.inspect', target: queue, result: :success,
      detail: { message_id: message_id },
    )
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  it 'answers 200 with outcome not_visible on a miss, and records nothing' do
    allow(show).to receive(:call).and_return(
      Onetime::Operations::Dlq::Show::Result.new(found: false, empty: false, message: nil, scanned: 500, truncated: true),
    )

    expect(processed).to eq(
      record: { queue: queue, message_id: message_id, found: false, outcome: 'not_visible', scanned: 500, truncated: true },
      details: { message: nil },
    )
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
  end

  it 'treats a configured queue that is not declared on the broker as not_visible' do
    allow(show).to receive(:call).and_raise(Bunny::NotFound.new('NOT_FOUND', nil, nil))

    expect(processed[:record]).to include(found: false, outcome: 'not_visible', scanned: 0, truncated: false)
  end
end
