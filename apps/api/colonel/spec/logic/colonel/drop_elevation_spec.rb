# apps/api/colonel/spec/logic/colonel/drop_elevation_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/elevation — ending the step-up window early (#4327).
#
# Strictly de-escalating, so it is idempotent by design: dropping a window that
# is not live still answers 200. A 404 there would only tell the operator
# whether they happened to be elevated, and the intent ("I am done with elevated
# access") is satisfied either way.
#
# It DOES audit, with .record: a deliberate operator action, on the same trail as
# the matching colonel.elevate success so the pair reads as one bracket. That is
# safe where the elevation FAILURE path is not, because this one cannot be
# driven usefully — it de-escalates.
RSpec.describe ColonelAPI::Logic::Colonel::DropElevation do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false, has_passphrase?: true)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain', email: 'plain@example.com',
      role: 'customer', verified?: true, anonymous?: false, has_passphrase?: true)
  end

  def logic_for(user = colonel, session = {})
    described_class.new(
      double('StrategyResult', session: session, user: user,
        auth_method: 'sessionauth', metadata: {}),
      {},
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    stub_colonel_elevation(enabled: true, window: 600)
  end

  it 'refuses a non-colonel' do
    expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
  end

  it 'removes a live window from the session' do
    session = elevated_session('ur_colonel')
    logic = logic_for(colonel, session)
    logic.raise_concerns
    data = logic.process

    expect(session).not_to have_key('elevated_until')
    expect(data[:record][:elevated]).to be false
    expect(data[:details][:was_elevated]).to be true
  end

  it 'is a 200 no-op when nothing was elevated' do
    logic = logic_for
    logic.raise_concerns
    data = logic.process

    expect(data[:record][:elevated]).to be false
    expect(data[:details][:was_elevated]).to be false
  end

  it 'records colonel.elevate_drop with the acting colonel as actor and target' do
    logic = logic_for(colonel, elevated_session('ur_colonel'))
    logic.raise_concerns
    logic.process

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(
        actor: 'ur_colonel', verb: 'colonel.elevate_drop', target: 'ur_colonel',
        result: :success,
      ),
    )
  end

  # A stale record belonging to somebody else reads as "not elevated", but the
  # delete must still clear it — otherwise a foreign record could sit in the
  # session with no way for its holder to remove it.
  it 'clears a record belonging to a different identity too' do
    session = elevated_session('ur_someone_else')
    logic = logic_for(colonel, session)
    logic.raise_concerns
    logic.process

    expect(session).not_to have_key('elevated_until')
  end
end
