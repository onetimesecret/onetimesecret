# spec/unit/onetime/application/auth_strategies/admin_session_lifetime_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/auth_strategies/admin_session_lifetime'

# Unit coverage for the #4331 admin-surface session bounds, driven directly
# against the module rather than through a strategy.
#
# What THIS layer owns: the decision — given a session, a customer and a Rack
# env, may this request touch /api/colonel? The wiring (where the check runs in
# BaseSessionAuthStrategy, and the 401 message shape) is
# base_session_auth_strategy_spec.rb; the end-to-end proof that a colonel keeps
# their TENANT session while the admin surface refuses them is
# spec/integration/all/colonel_session_lifetime_spec.rb.
#
# The bounds are DISABLED in spec/config.test.yaml, so every example here opts in
# explicitly via `configure_bounds` — which is also what keeps the "enabled:false
# is a real off switch" example honest.
RSpec.describe Onetime::Application::AuthStrategies::AdminSessionLifetime do
  # The module is a mixin for an auth strategy; a bare host exercises it without
  # dragging in Otto, a Rack env stack or a customer load.
  let(:host_class) do
    Class.new do
      include Onetime::Application::AuthStrategies::AdminSessionLifetime
    end
  end

  let(:host) { host_class.new }
  let(:now) { 1_800_000_000 }

  let(:colonel) { instance_double(Onetime::Customer, role: 'colonel') }
  let(:customer) { instance_double(Onetime::Customer, role: 'customer') }

  # A Rack SessionHash responds to #id with a Rack::SessionId; a plain Hash does
  # not. Both shapes reach this code (Basic-auth and JSON paths carry a Hash), so
  # the sid-bearing case is modelled explicitly.
  def session_with_sid(sid, **fields)
    hash = { 'authenticated' => true }.merge(fields)
    hash.define_singleton_method(:id) { Struct.new(:public_id).new(sid) }
    hash
  end

  def env_for(script_name: '/api/colonel', path_info: '/sessions')
    { 'SCRIPT_NAME' => script_name, 'PATH_INFO' => path_info }
  end

  def configure_bounds(**settings)
    conf = YAML.load(YAML.dump(OT.conf))
    ((conf['site'] ||= {})['admin'] ||= {})['session'] =
      { 'enabled' => true }.merge(settings.transform_keys(&:to_s))
    allow(OT).to receive(:conf).and_return(conf)
  end

  def stub_sidecar(last_activity_at)
    record = instance_double(Onetime::SessionMetadata, last_activity_at: last_activity_at)
    allow(Onetime::SessionMetadata).to receive(:load).and_return(record)
  end

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::SessionMetadata).to receive(:load).and_return(nil)
    allow(OT).to receive(:ld)
    configure_bounds
  end

  describe 'the absolute bound' do
    it 'expires a colonel whose sign-in is older than the bound' do
      session = session_with_sid('sid1', 'authenticated_at' => now - 43_201)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end

    it 'lets a sign-in exactly at the bound through (the comparison is strict)' do
      session = session_with_sid('sid1', 'authenticated_at' => now - 43_200)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    # Nothing an attacker holding the cookie can do advances authenticated_at, so
    # this is the bound that always binds — but only when the field is present.
    # A session that never stamped one is not treated as infinitely old.
    it 'skips a session with no authenticated_at rather than failing it' do
      session = session_with_sid('sid1')

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    it 'is disabled by absolute_timeout: 0 while the idle bound still applies' do
      configure_bounds(absolute_timeout: 0)
      stub_sidecar(now - 10)
      session = session_with_sid('sid1', 'authenticated_at' => now - 100_000)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end
  end

  describe 'the idle bound' do
    it 'expires a colonel whose last activity is older than the bound' do
      stub_sidecar(now - 3_601)
      session = session_with_sid('sid1', 'authenticated_at' => now - 60)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:idle)
    end

    it 'lets a recently active session through' do
      stub_sidecar(now - 60)
      session = session_with_sid('sid1', 'authenticated_at' => now - 60)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    # THE fail-open-on-purpose case. SessionMetadata is best-effort: a session
    # predating the sidecar, one whose 30-day TTL lapsed, or one whose write was
    # swallowed has no record. Hard-failing here would log out live sessions for
    # a reason unrelated to their age.
    it 'SKIPS itself when no sidecar record exists' do
      session = session_with_sid('sid1', 'authenticated_at' => now - 60)

      expect(Onetime::SessionMetadata).to receive(:load).with('sid1').and_return(nil)
      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    it 'skips itself when the session carries no resolvable sid' do
      expect(Onetime::SessionMetadata).not_to receive(:load)
      expect(host.admin_session_expiry_reason({ 'authenticated' => true }, colonel, env_for))
        .to be_nil
    end

    it 'skips itself when the sidecar read raises' do
      allow(Onetime::SessionMetadata).to receive(:load).and_raise(StandardError, 'redis down')
      session = session_with_sid('sid1')

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    it 'is disabled by idle_timeout: 0 while the absolute bound still applies' do
      configure_bounds(idle_timeout: 0)
      stub_sidecar(now - 100_000)
      session = session_with_sid('sid1', 'authenticated_at' => now - 43_201)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end

    it 'reports :absolute first when both bounds are exceeded' do
      stub_sidecar(now - 100_000)
      session = session_with_sid('sid1', 'authenticated_at' => now - 100_000)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end
  end

  describe 'scope' do
    let(:stale) { session_with_sid('sid1', 'authenticated_at' => now - 100_000) }

    it 'bounds /api/colonel itself and everything under it' do
      expect(host.admin_session_expiry_reason(stale, colonel, env_for(path_info: '')))
        .to eq(:absolute)
      expect(host.admin_session_expiry_reason(stale, colonel, env_for(path_info: '/users/ur_1')))
        .to eq(:absolute)
    end

    # The rev-2 scope narrowing. A bare 401 on an HTML navigation has no defined
    # UX and the expired-session banner lives INSIDE the SPA, so the shell must
    # load; its first API call is what 401s.
    it 'does NOT bound the /colonel SPA shell' do
      env = env_for(script_name: '', path_info: '/colonel')

      expect(host.admin_session_expiry_reason(stale, colonel, env)).to be_nil
    end

    it 'does NOT bound a path that merely starts with the prefix string' do
      env = env_for(script_name: '', path_info: '/api/colonelish/thing')

      expect(host.admin_session_expiry_reason(stale, colonel, env)).to be_nil
    end

    # The regression this whole design exists to prevent: a colonel who is also
    # the site's only customer must keep their normal 24h session on the tenant
    # app.
    it 'does NOT bound a tenant route' do
      env = env_for(script_name: '', path_info: '/account')

      expect(host.admin_session_expiry_reason(stale, colonel, env)).to be_nil
    end

    it 'does NOT bound a non-colonel account' do
      expect(host.admin_session_expiry_reason(stale, customer, env_for)).to be_nil
    end
  end

  describe 'configuration' do
    it 'is a no-op when enabled is false' do
      configure_bounds(enabled: false)
      stub_sidecar(now - 100_000)
      session = session_with_sid('sid1', 'authenticated_at' => now - 100_000)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to be_nil
    end

    it 'applies the shipped defaults when the block is absent entirely' do
      conf = YAML.load(YAML.dump(OT.conf))
      conf['site']['admin'].delete('session')
      allow(OT).to receive(:conf).and_return(conf)
      session = session_with_sid('sid1', 'authenticated_at' => now - 43_201)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end

    # 0 disables a bound and must survive as 0; a NEGATIVE value is operator
    # error and falls back to the default rather than disabling the bound
    # silently (the inverse of the positive_*_setting trap #4329 documents).
    it 'falls back to the default on a negative value' do
      configure_bounds(absolute_timeout: -1)
      session = session_with_sid('sid1', 'authenticated_at' => now - 43_201)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end

    it 'reads a string value from ERB-rendered YAML' do
      configure_bounds(absolute_timeout: '60')
      session = session_with_sid('sid1', 'authenticated_at' => now - 61)

      expect(host.admin_session_expiry_reason(session, colonel, env_for)).to eq(:absolute)
    end
  end
end
