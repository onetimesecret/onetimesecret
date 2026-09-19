# spec/unit/onetime/helpers/session_helpers_active_session_spec.rb
#
# frozen_string_literal: true

# The controller-side half of full-mode active-session enforcement: once the
# Rack session's active-session row is revoked (or cannot be checked),
# SessionHelpers#authenticated? answers false the same way
# BaseSessionAuthStrategy refuses the request. Terms are defined in the
# gate's module doc. The gate's own
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

  # A host spelling the request `req`, as the core and billing controllers do.
  let(:req_helper_class) do
    Class.new do
      include Onetime::Helpers::SessionHelpers

      attr_reader :session, :req

      def initialize(session, req)
        @session = session
        @req     = req
      end
    end
  end

  # A session established on the canonical surface, with the #4409 marker set
  # so it survives the surface-bound-session gate that also runs inside
  # authenticated?. Tests focused on other predicates supply a matching
  # canonical request env; see session_helpers_surface_spec.rb for the
  # surface-mismatch coverage.
  let(:session) do
    {
      'authenticated'                     => true,
      'external_id'                       => 'ur_abc',
      Onetime::SessionSurface::KEY        => { 'kind' => 'canonical' },
    }
  end
  let(:canonical_env) { { 'onetime.domain_strategy' => :canonical } }
  let(:gate) { Onetime::ActiveSessionGate }
  let(:customer) do
    instance_double(
      Onetime::Customer,
      suspended?: false,
      last_password_update: 0,
      role?: false,
    )
  end

  before do
    allow(OT).to receive(:conf).and_return({ 'site' => { 'authentication' => { 'enabled' => true } } })
    allow(OT).to receive(:info)
    allow(Onetime::Customer).to receive(:find_by_extid).and_return(customer)
    allow(Onetime::SessionImpersonation).to receive(:resolve).and_return([customer, nil])
  end

  def helper_with_env(env)
    helper_class.new(session, instance_double(Rack::Request, env: env))
  end

  it 'stays authenticated while the gate says the active-session row is present' do
    allow(gate).to receive(:verdict).and_return(:active)
    expect(helper_with_env(canonical_env).authenticated?).to be(true)
  end

  it 'is no longer authenticated once the gate says the active-session row is gone' do
    allow(gate).to receive(:verdict).and_return(:revoked)
    expect(helper_with_env(canonical_env).authenticated?).to be(false)
  end

  it 'consults the gate once per helper, however often authenticated? is asked' do
    allow(gate).to receive(:verdict).and_return(:active)

    inst = helper_with_env(canonical_env)
    3.times { inst.authenticated? }
    inst.colonel?

    expect(gate).to have_received(:verdict).once
  end

  it 'passes the Rack env through so the strategy and the helper share one memo' do
    env = canonical_env.dup
    allow(gate).to receive(:verdict).and_return(:active)

    helper_class.new(session, instance_double(Rack::Request, env: env)).authenticated?

    expect(gate).to have_received(:verdict).with(session, env: env)
  end

  # The core and billing controllers expose the request as `req`, not
  # `request`. They must share the same env memo, or every authenticated? call
  # on those surfaces would pay for a second active-session SELECT the
  # strategy already made.
  it 'finds the Rack env through `req` on controllers that do not expose `request`' do
    env = canonical_env.dup
    req = instance_double(Rack::Request, env: env)
    allow(gate).to receive(:verdict).and_return(:active)

    req_helper_class.new(session, req).authenticated?

    expect(gate).to have_received(:verdict).with(session, env: env)
  end

  it 'forgets the verdict on logout! so the next identity is judged afresh' do
    allow(gate).to receive(:verdict).and_return(:revoked, :active)
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    inst = helper_with_env(canonical_env)
    expect(inst.authenticated?).to be(false)
    inst.logout!
    session.merge!(
      'authenticated' => true,
      'external_id' => 'ur_next',
      Onetime::SessionSurface::KEY => { 'kind' => 'canonical' },
    )

    expect(inst.authenticated?).to be(true)
    expect(gate).to have_received(:verdict).twice
  end

  it 'drops the shared env memo on logout!' do
    env     = canonical_env.merge(gate::ENV_KEY => :revoked)
    request = instance_double(Rack::Request, env: env)
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    helper_class.new(session, request).logout!

    expect(env).not_to have_key(gate::ENV_KEY)
  end

  it 'drops a last_use refresh deferred for the previous identity on logout! (#4455)' do
    env     = canonical_env.merge(gate::ENV_KEY => :active, gate::TOUCH_DEFERRED_ENV_KEY => true)
    request = instance_double(Rack::Request, env: env)
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    helper_class.new(session, request).logout!

    expect(env).not_to have_key(gate::TOUCH_DEFERRED_ENV_KEY)
  end

  # RISK-2026-09-19-01: only a renewed id gets an ended-marker, and only the
  # marker stops a request in flight from writing the session back.
  it 'renews the session id on logout!' do
    options = {}
    request = instance_double(Rack::Request, env: canonical_env.merge('rack.session.options' => options))
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    helper_class.new(session, request).logout!

    expect(options[:renew]).to be(true)
  end

  # #4461: the sid is the bearer credential. Neither it nor Rack's private id
  # is logged; the line carries the handle every other session log line uses.
  it 'logs the session handle on logout!, never a session id', :aggregate_failures do
    sid            = Rack::Session::SessionId.new('c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655')
    rack_session   = session.dup
    rack_session.define_singleton_method(:id) { sid }
    logged         = []
    allow(OT).to receive(:info) { |message| logged << message }
    allow(Onetime::SessionImpersonation).to receive(:stop!)

    helper_class.new(rack_session, instance_double(Rack::Request, env: canonical_env)).logout!

    line = logged.grep(/\[logout\]/).first
    expect(line).to include("session_handle=#{Onetime::SessionMetadata.handle_for(sid.public_id)}")
    expect(line).not_to include(sid.public_id)
    expect(line).not_to include(sid.private_id)
  end
end
