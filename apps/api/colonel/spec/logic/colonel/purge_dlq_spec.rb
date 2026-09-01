# apps/api/colonel/spec/logic/colonel/purge_dlq_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/queues/dlq/:queue/purge — irreversible message loss, TIER 1.
#
# The ONE gated verb whose confirmation token IS the URL parameter: a queue has
# no second identifier (no email, no display name, no hostname). That is stated
# plainly rather than dressed up as replay resistance it does not provide.
#
# `dry_run` defaults to FALSE here — the opposite of the domain/org verbs — so
# the preview exemption is worth pinning in both directions.
RSpec.describe ColonelAPI::Logic::Colonel::PurgeDlq do
  let(:queue) { Onetime::Operations::Dlq::Store.all_dlq_names.first }
  let(:short_name) { queue.sub('dlq.', '') }

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

  let(:op) do
    instance_double(
      Onetime::Operations::Dlq::Purge,
      call: Onetime::Operations::Dlq::Purge::Result.new(
        status: :purged, queue: queue, count: 3, purged: 3,
      ),
    )
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = short_name, params = {})
    described_class.new(
      strategy_result_for(user, confirm_token),
      { 'queue' => short_name }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Operations::Dlq::Purge).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    # The adapter's broker-availability guard reads the shared boot-time
    # connection; a real broker is a tryout's job, not a unit spec's.
    $rmq_conn = double('BunnyConnection', open?: true)
  end

  after { $rmq_conn = nil }

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { short_name }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'purges nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::Dlq::Purge).not_to have_received(:new)
    end
  end

  describe 'preview exemption' do
    let(:preview_op) do
      instance_double(
        Onetime::Operations::Dlq::Purge,
        call: Onetime::Operations::Dlq::Purge::Result.new(
          status: :dry_run, queue: queue, count: 3, purged: 0,
        ),
      )
    end

    it 'needs no confirmation for a dry run (it counts, it does not purge)' do
      allow(Onetime::Operations::Dlq::Purge).to receive(:new).and_return(preview_op)
      logic = logic_for(colonel, nil, 'dry_run' => 'true')

      expect { logic.raise_concerns }.not_to raise_error
      expect(logic.process[:record][:dry_run]).to be true
    end

    it 'still requires it when dry_run is absent (this verb defaults to APPLY)' do
      expect { logic_for(colonel, nil).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'guard order (§0.2)' do
    it 'rejects an unknown queue BEFORE the confirmation gate (allowlist, not secret)' do
      expect { logic_for(colonel, nil, 'queue' => 'not-a-queue').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown dead-letter queue/)
    end

    it 'rejects a non-colonel before either' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op the resolved queue name and the colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::Dlq::Purge).to have_received(:new)
        .with(hash_including(queue: queue, actor: 'ur_colonel', dry_run: false))
      expect(data[:record][:purged]).to eq(3)
    end
  end
end
