# apps/api/v2/spec/logic/secrets/show_receipt_access_details_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Creator-facing surfacing of the access timeline (#3633).
#
# ShowReceipt's details payload carries the aggregates derived from the
# receipt's access timeline: view_count (long a null placeholder), plus
# first/last access timestamps. They must be present whether or not the
# secret still exists -- the timeline outlives the secret by design.
RSpec.describe V2::Logic::Secrets::ShowReceipt, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    session = double('Session')
    allow(session).to receive(:[]).and_return(nil)
    allow(session).to receive(:[]=)
    allow(session).to receive(:empty?).and_return(true)
    session
  end

  def build_logic(params)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org },
      auth_method: 'basicauth')

    described_class.new(strategy_result, params)
  end

  let!(:pair)   { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt) { pair.first }
  let(:secret)  { pair.last }

  context 'before the secret link has been fetched' do
    it 'reports a zero view_count and null first/last access' do
      logic = build_logic({ 'identifier' => receipt.identifier })
      logic.process_params
      logic.raise_concerns
      details = logic.process[:details]

      expect(details[:view_count]).to eq(0)
      expect(details[:first_access]).to be_nil
      expect(details[:last_access]).to be_nil
    end
  end

  context 'after the secret link has been fetched' do
    it 'reports the count and first/last timestamps from the timeline' do
      t1 = Familia.now.to_f - 60
      t2 = Familia.now.to_f - 30
      receipt.record_access_event('status_get', at: t1)
      receipt.record_access_event('secret_get', at: t2)

      logic = build_logic({ 'identifier' => receipt.identifier })
      logic.process_params
      logic.raise_concerns
      details = logic.process[:details]

      expect(details[:view_count]).to eq(2)
      expect(details[:first_access]).to be_within(0.001).of(t1)
      expect(details[:last_access]).to be_within(0.001).of(t2)
    end
  end

  context 'after the secret has been consumed' do
    it 'still reports the pre-reveal accesses (the timeline outlives the secret)' do
      receipt.record_access_event('secret_get')
      expect(secret.revealed!).to be true

      logic = build_logic({ 'identifier' => receipt.identifier })
      logic.process_params
      logic.raise_concerns
      details = logic.process[:details]

      expect(details[:view_count]).to eq(1)
      expect(details[:first_access]).not_to be_nil
    end
  end
end
