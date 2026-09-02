# apps/api/colonel/spec/logic/colonel/get_session_detail_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# GET /api/colonel/sessions/:session_handle used to take — and echo — the raw
# session id, a value byte-identical to the user's `onetime.session` cookie
# (#4330). These examples pin the boundary this adapter now owns:
#
#   - the route param is an opaque handle, resolved to a sid SERVER-SIDE;
#   - neither the sid nor its Redis key (`session:<sid>`) appears anywhere in
#     the response, and neither does the live `csrf` token in the raw payload;
#   - an unknown OR malformed handle answers the same 404, so a scanner learns
#     nothing from the shape of its guess;
#   - the bounded-scan truncation is disclosed rather than hidden behind a 404;
#   - being read-only, no path here writes a ColonelAuditEvent (CONTRACT 4).
#
# What this layer does NOT own: the resolution itself (Sessions::Store —
# try/unit/operations/sessions_try.rb) and the role gate at the router.
RSpec.describe ColonelAPI::Logic::Colonel::GetSessionDetail do
  let(:handle) { '0123456789abcdef0123456789abcdef' }
  let(:session_id) { 'a' * 64 }

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

  let(:payload) do
    {
      'authenticated' => true,
      'email' => 'alice@example.com',
      'external_id' => 'ur_alice',
      'account_id' => 42,
      'role' => 'customer',
      'locale' => 'en',
      'ip_address' => '203.0.113.7',
      'user_agent' => 'Mozilla/5.0',
      'org_context:019f4ac1-b8d6-7ca9-858d-ba3d7e1e0210' => true,
      'authenticated_at' => 1_700_000_000,
      'authenticated_by' => ['password'],
      'active_session_id' => 'as_1',
      'csrf' => 'live-csrf-token',
    }
  end

  let(:inspect_result) do
    Onetime::Operations::Sessions::Inspect::Result.new(
      found: true, session_id: session_id, key: "session:#{session_id}",
      ttl: 3600, data: payload,
    )
  end

  def strategy_result_for(user)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: {})
  end

  def logic_for(user = colonel, params = { 'session_handle' => handle })
    described_class.new(strategy_result_for(user), params)
  end

  # Resolution is stubbed at the Store boundary: this adapter owns "what the
  # handle buys you", not the two-stage lookup itself.
  def stub_resolution(sid: session_id, scan_capped: false)
    allow(Onetime::Operations::Sessions::Store).to receive(:resolve_handle)
      .and_return([sid, scan_capped])
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Familia).to receive(:dbclient).and_return(double('Redis'))
    allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
      instance_double(Onetime::Operations::Sessions::Inspect, call: inspect_result),
    )
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'handle resolution' do
    it 'resolves the handle server-side and inspects the resolved sid' do
      stub_resolution
      logic = logic_for
      logic.raise_concerns

      expect(Onetime::Operations::Sessions::Inspect).to have_received(:new)
        .with(session_id: session_id)
    end

    it 'passes the optional owner hint through to the resolver' do
      stub_resolution
      logic_for(colonel, { 'session_handle' => handle, 'user_id' => 'alice@example.com' })
        .raise_concerns

      expect(Onetime::Operations::Sessions::Store).to have_received(:resolve_handle)
        .with(anything, handle, owner_hint: 'alice@example.com')
    end

    it 'downcases the submitted handle so a pasted uppercase value still resolves' do
      stub_resolution
      logic_for(colonel, { 'session_handle' => handle.upcase }).raise_concerns

      expect(Onetime::Operations::Sessions::Store).to have_received(:resolve_handle)
        .with(anything, handle, owner_hint: '')
    end

    it '404s when the handle resolves to nothing' do
      stub_resolution(sid: nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end

    it '404s — never 422 — on a malformed handle, so a scanner cannot tell them apart' do
      # An unparseable handle never reaches the datastore: resolve_handle
      # rejects the shape and answers [nil, false].
      allow(Onetime::Operations::Sessions::Store).to receive(:resolve_handle).and_call_original

      expect { logic_for(colonel, { 'session_handle' => 'not-a-handle' }).raise_concerns }
        .to raise_error(Onetime::RecordNotFound)
    end

    it '422s only when no handle was supplied at all' do
      expect { logic_for(colonel, { 'session_handle' => '' }) }
        .to raise_error(Onetime::FormError)
    end

    it '404s when the resolved sid has no live session' do
      stub_resolution
      allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
        instance_double(Onetime::Operations::Sessions::Inspect,
          call: Onetime::Operations::Sessions::Inspect::Result.new(
            found: false, session_id: session_id, key: nil, ttl: nil, data: nil,
          )),
      )

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end
  end

  describe 'response shape' do
    subject(:response) do
      stub_resolution
      logic = logic_for
      logic.raise_concerns
      logic.process
    end

    it 'identifies the session by handle' do
      expect(response[:record][:session_handle]).to eq(handle)
    end

    it 'never carries the raw sid or its Redis key' do
      expect(response[:record]).not_to have_key(:session_id)
      expect(response[:record]).not_to have_key(:key)
      expect(response.to_s).not_to include(session_id)
    end

    it 'strips the live csrf token out of the raw payload the drawer renders' do
      expect(payload).to have_key('csrf') # the session really carries one
      expect(response[:details][:data]).not_to have_key('csrf')
      expect(response[:details][:data]['email']).to eq('alice@example.com')
    end

    it 'still surfaces the typed read-out fields' do
      expect(response[:record]).to include(
        ttl: 3600,
        authenticated: true,
        email: 'alice@example.com',
        external_id: 'ur_alice',
        account_id: 42,
        org_context: '019f4ac1-b8d6-7ca9-858d-ba3d7e1e0210',
      )
    end
  end

  describe 'bounded-scan truncation' do
    it 'discloses scan_capped so a 404 is not read as "does not exist"' do
      stub_resolution(scan_capped: true)
      logic = logic_for
      logic.raise_concerns

      expect(logic.process[:details][:scan_capped]).to be true
    end

    it 'reports false when the resolution did not hit the cap' do
      stub_resolution
      logic = logic_for
      logic.raise_concerns

      expect(logic.process[:details][:scan_capped]).to be false
    end
  end

  describe 'authorization' do
    it 'refuses a non-colonel and writes NO audit event' do
      stub_resolution
      logic = logic_for(customer)

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'writes no audit event on the success path either — reads never audit' do
      stub_resolution
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
