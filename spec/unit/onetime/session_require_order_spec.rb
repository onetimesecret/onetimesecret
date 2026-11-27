# spec/unit/onetime/session_require_order_spec.rb
#
# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe Onetime::Session do
  def run_isolated_ruby(script, *)
    Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', script, *, chdir: Onetime::HOME)
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
        abort 'leaf loaded the Rack store' if session.instance_method(:initialize).owner == session

        require 'onetime/session'
        abort 'wrong Rack superclass' unless session.superclass == Rack::Session::Abstract::PersistedSecure
        abort 'Rack store did not load' unless session.instance_method(:initialize).owner == session
      RUBY
      expect(status.success?).to be(true), output
    end
  end

  it 'loads the Rack store before individual helpers' do
    output, status = run_isolated_ruby(<<~RUBY)
      require 'onetime/session'
      Dir['lib/onetime/session/*.rb'].sort.each { |file| require file.delete_prefix('lib/') }
      session = Onetime::Session
      abort 'wrong Rack superclass' unless session.superclass == Rack::Session::Abstract::PersistedSecure
      abort 'Rack store did not load' unless session.instance_method(:initialize).owner == session
    RUBY
    expect(status.success?).to be(true), output
  end
end
