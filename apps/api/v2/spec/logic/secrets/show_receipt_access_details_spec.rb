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

  # Regression (#3633): loading the receipt page is a safe GET. It must not
  # advance lifecycle state to 'previewed' (the old side effect), and the
  # page load is recorded as a 'receipt_viewed' audit event -- distinct from
  # the creator opening the secret *link* ('previewed').
  context 'when the receipt page is loaded (safe GET)' do
    it 'does not advance the receipt or secret lifecycle state' do
      logic = build_logic({ 'identifier' => receipt.identifier })
      logic.process_params
      logic.raise_concerns
      logic.process

      reloaded_receipt = Onetime::Receipt.load(receipt.identifier)
      expect(reloaded_receipt.state).to eq('new')
      expect(reloaded_receipt.state?(:previewed)).to be false
      expect(Onetime::Secret.load(secret.identifier).state).to eq('new')
    end

    it 'does not inflate the access timeline view_count' do
      logic = build_logic({ 'identifier' => receipt.identifier })
      logic.process_params
      logic.raise_concerns
      details = logic.process[:details]

      # Viewing the receipt page is audit-trail telemetry only; it must not
      # count as an access of the secret link.
      expect(details[:view_count]).to eq(0)
    end

    it "reveals a generated secret's value to the creator exactly once (#3633)" do
      # The generated plaintext is shown nowhere but the receipt page, so this
      # is the enforcement point for the "one time" guarantee. Before #3633 the
      # previewed! state mutation bounded it; now an atomic claim does, so a
      # second load must return nil even inside the display window.
      display_ttl = OT.conf.dig('site', 'secret_options', 'generated_value_display_ttl').to_i
      expect(display_ttl).to be_positive # config sanity: the value path is dead at 0

      receipt.kind = 'generate'
      receipt.save_fields(:kind)

      first = build_logic({ 'identifier' => receipt.identifier })
      first.process_params
      first.raise_concerns
      first_details = first.process[:details]

      second = build_logic({ 'identifier' => receipt.identifier })
      second.process_params
      second.raise_concerns
      second_details = second.process[:details]

      expect(first_details[:secret_value]).to eq('a secret value')
      expect(second_details[:secret_value]).to be_nil
      # A safe GET either way: the one-time reveal never advanced lifecycle state.
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('new')
    end

    it "records a 'receipt_viewed' audit event on the owning org's trail, exactly once across repeated loads" do
      org = Onetime::Organization.new(
        display_name: 'Receipt View Test Org',
        contact_email: "rcpt-view-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)
      receipt.org_id = org.objid
      receipt.save_fields(:org_id)

      # Load the receipt page three times: a bookmarked/monitored page must not
      # flood the org's capped audit trail, so the event is bounded to one.
      3.times do
        logic = build_logic({ 'identifier' => receipt.identifier })
        logic.process_params
        logic.raise_concerns
        logic.process
      end

      kinds = Onetime::Organization.load(org.objid).audit_events_page.map { |e| e['kind'] }
      expect(kinds).to eq(['receipt_viewed'])
    end
  end
end
