# spec/unit/onetime/session/elevation_dropped_on_login_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/sync_session'

# An identity change must always land UNELEVATED (#4327).
#
# The finding, stated as the scenario it fixes: sign in as account B on a
# browser that already held account A's ELEVATED colonel session, and B must not
# inherit A's live step-up window.
#
# It is a real risk in this codebase because one `onetime.session` cookie can
# outlive an identity change on BOTH paths:
#
#   - simple mode — Core::Controllers::Authentication#perform_authentication
#     assigns the new identity into the session and calls neither `session.clear`
#     nor `request.session_options[:renew] = true`. (Compare
#     lib/onetime/helpers/session_helpers.rb, the OTHER authenticate path, which
#     does both; the controller does not use it. Fixing that omission is out of
#     this epic's charter — see the epic's non-goals — so #4327 only ensures
#     elevation cannot survive it.)
#   - full mode — Rodauth's :renew after a password change carries the session
#     hash to a new sid, where it is re-externalized.
#
# Elevation is ALSO identity-bound on read (see
# apps/api/colonel/spec/logic/colonel/elevation_identity_binding_spec.rb). These
# two closures are deliberately independent: the read-side binding holds if a
# third identity-change path is ever added, and this deletion holds if a future
# refactor changes the stored shape.
RSpec.describe 'elevation is dropped on every identity change' do
  let(:elevated) { { 'extid' => 'ur_alice', 'exp' => Familia.now.to_i + 600 } }

  describe 'simple mode — Core::Controllers::Authentication#perform_authentication' do
    subject(:controller) { Core::Controllers::Authentication.new(req, res) }

    let(:session_data) { { 'elevated_until' => elevated } }

    let(:rack_session) do
      session = double('RackSession')
      allow(session).to receive(:id).and_return(double('SessionId', public_id: 'sess_abc'))
      allow(session).to receive(:[]) { |key| session_data[key] }
      allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
      allow(session).to receive(:delete) { |key| session_data.delete(key) }
      session
    end

    let(:env) do
      {
        'rack.session' => rack_session,
        'rack.session.options' => {},
        'HTTP_ACCEPT' => 'application/json',
        'REMOTE_ADDR' => '127.0.0.1',
      }
    end

    let(:req) do
      request = double('Request')
      allow(request).to receive_messages(env: env, ip: '127.0.0.1', locale: 'en', params: {})
      allow(request).to receive(:app_path) { |path| path }
      request
    end

    let(:res) do
      response = double('Response', do_not_cache!: nil, redirect: nil)
      allow(response).to receive(:status=)
      response
    end

    let(:signing_in) do
      double('Customer', extid: 'ur_bob', email: 'bob@example.com', custid: 'bob@example.com',
        role: 'customer', obscure_email: 'b***@example.com')
    end

    before do
      allow(controller).to receive(:auth_logger).and_return(double('Logger', debug: nil, info: nil))
      allow(controller).to receive(:strategy_result).and_return(nil)
      allow(controller).to receive(:json_requested?).and_return(true)
      allow(controller).to receive(:json_success)
      allow(Core::Logic::Authentication::AuthenticateSession).to receive(:new)
        .and_return(double('Logic', cust: signing_in))
      allow(signing_in).to receive(:role?).with(:colonel).and_return(false)
      # The controller's own error-handling wrapper yields the success block;
      # what is under test is what that block writes to the session.
      allow(controller).to receive(:execute_with_error_handling) { |_logic, **_opts, &block| block.call }
    end

    it 'deletes the previous occupant\'s step-up window' do
      controller.send(:perform_authentication)

      expect(session_data).not_to have_key('elevated_until')
    end

    it 'still establishes the new identity (the deletion is additive)' do
      controller.send(:perform_authentication)

      expect(session_data).to include('external_id' => 'ur_bob', 'authenticated' => true)
    end
  end

  describe 'full mode — Auth::Operations::SyncSession#populate_session' do
    let(:session) { { 'elevated_until' => elevated } }

    let(:op) do
      Auth::Operations::SyncSession.new(
        account: { email: 'bob@example.com', external_id: 'ur_bob', status_id: 2 },
        account_id: 42,
        session: session,
        request: double('Request', ip: '203.0.113.7', user_agent: 'rspec'),
        correlation_id: 'corr_1',
        db: double('Sequel::Database'),
      )
    end

    let(:customer) do
      double('Customer', extid: 'ur_bob', email: 'bob@example.com', role: 'customer', locale: 'en')
    end

    it 'deletes the previous occupant\'s step-up window' do
      op.send(:populate_session, customer)

      expect(session).not_to have_key('elevated_until')
    end

    it 'still establishes the new identity (the deletion is additive)' do
      op.send(:populate_session, customer)

      expect(session).to include('external_id' => 'ur_bob', 'authenticated' => true)
    end
  end
end
