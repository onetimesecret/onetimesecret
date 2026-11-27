# spec/unit/onetime/session_require_order_spec.rb
#
# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Onetime::Session do
  def run_isolated_ruby(script, *)
    Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', script, *, chdir: Onetime::HOME)
  end

  it 'loads the namespace without the Rack store' do
    output, status = run_isolated_ruby(<<~RUBY)
      require 'onetime/session'
      abort 'expected a module' unless Onetime::Session.instance_of?(Module)
      abort 'namespace loaded the Rack store' if defined?(Onetime::Session::RackStore)
      abort 'namespace loaded rack-session' if defined?(Rack::Session::Abstract::PersistedSecure)
    RUBY
    expect(status.success?).to be(true), output
  end

  {
    active_session_gate: 'ActiveSessionGate',
    activity: 'Activity',
    auth_status: 'AuthStatus',
    codec: 'Codec',
    customer_session_evaluator: 'CustomerSessionEvaluator',
    ended: 'Ended',
    failure_code: 'FailureCode',
    impersonation: 'Impersonation',
    reauth_policy: 'ReauthPolicy',
    recent_reauth: 'RecentReauth',
    remember_me: 'RememberMe',
    rotation: 'Rotation',
    sidecar: 'Sidecar',
    snapshot_ordering: 'SnapshotOrdering',
    surface: 'Surface',
  }.each do |file, constant|
    it "loads #{file} before the Rack store" do
      output, status = run_isolated_ruby(<<~'RUBY', file.to_s, constant)
        require "onetime/session/#{ARGV.fetch(0)}"
        session = Onetime::Session
        session.const_get(ARGV.fetch(1), false)
        abort 'helper loaded the Rack store' if defined?(Onetime::Session::RackStore)
        abort 'helper loaded rack-session' if defined?(Rack::Session::Abstract::PersistedSecure)

        require 'onetime/session/rack_store'
        abort 'wrong Rack superclass' unless session::RackStore.superclass == Rack::Session::Abstract::PersistedSecure
      RUBY
      expect(status.success?).to be(true), output
    end
  end

  it 'loads the Rack store before individual helpers' do
    output, status = run_isolated_ruby(<<~RUBY)
      require 'onetime/session/rack_store'
      Dir['lib/onetime/session/*.rb'].sort.each { |file| require file.delete_prefix('lib/') }
      store = Onetime::Session::RackStore
      abort 'wrong Rack superclass' unless store.superclass == Rack::Session::Abstract::PersistedSecure
    RUBY
    expect(status.success?).to be(true), output
  end
end
