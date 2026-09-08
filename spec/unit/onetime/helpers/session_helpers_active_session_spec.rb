# spec/unit/onetime/helpers/session_helpers_active_session_spec.rb
#
# frozen_string_literal: true

# The controller-side half of full-mode active-session enforcement: once the
# session's Rodauth row is gone, SessionHelpers#authenticated? answers false
# the same way BaseSessionAuthStrategy refuses the request. The gate's own
# decision table is spec/unit/onetime/session/active_session_gate_spec.rb;
# what is pinned here is the wiring — the memo, and that login/logout forget
# a verdict reached for the previous identity.

require 'spec_helper'
require 'onetime/helpers/session_helpers'

RSpec.describe Onetime::Helpers::SessionHelpers do
  subject(:helper) { helper_class.new(session) }

  let(:helper_class) do
    Class.new do
      include Onetime::Helpers::SessionHelpers

      attr_reader :session, :request

      def initialize(session, request = nil)
        @session = session
        @request = request
      end
    end
  end

  let(:session) { { 'authenticated' => true, 'external_id' => 'ur_abc' } }
  let(:gate) { Onetime::ActiveSessionGate }

  before do
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => { 'enabled' => true } } })
    allow(OT).to receive(:info)
  end

  it 'stays authenticated while the gate says the row is present' do
    allow(gate).to receive(:revoked?).and_return(false)
    expect(helper.authenticated?).to be(true)
  end

  it 'is no longer authenticated once the gate says the row is gone' do
    allow(gate).to receive(:revoked?).and_return(true)
    expect(helper.authenticated?).to be(false)
  end

  it 'consults the gate once per helper, however often authenticated? is asked' do
    allow(gate).to receive(:revoked?).and_return(false)

    3.times { helper.authenticated? }
    helper.colonel?

    expect(gate).to have_received(:revoked?).once
  end

  it 'passes the Rack env through so the strategy and the helper share one memo' do
    env     = {}
    request = instance_double(Rack::Request, env: env)
    allow(gate).to receive(:revoked?).and_return(false)

    helper_class.new(session, request).authenticated?

    expect(gate).to have_received(:revoked?).with(session, env: env)
  end

  it 'forgets the verdict on logout! so the next identity is judged afresh' do
    allow(gate).to receive(:revoked?).and_return(true, false)
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    expect(helper.authenticated?).to be(false)
    helper.logout!
    session.merge!('authenticated' => true, 'external_id' => 'ur_next')

    expect(helper.authenticated?).to be(true)
    expect(gate).to have_received(:revoked?).twice
  end

  it 'drops the shared env memo on logout!' do
    env     = { gate::ENV_KEY => :revoked }
    request = instance_double(Rack::Request, env: env)
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    helper_class.new(session, request).logout!

    expect(env).not_to have_key(gate::ENV_KEY)
  end
end
