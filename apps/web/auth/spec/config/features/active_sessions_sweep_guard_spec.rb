# apps/web/auth/spec/config/features/active_sessions_sweep_guard_spec.rb
#
# frozen_string_literal: true

# Guard for the sweep override in Auth::Config::Features::ActiveSessions.
#
# The feature overrides Rodauth's PRIVATE `inactive_session_cond` so that
# `remove_inactive_sessions` (the sessions-page sweep) deletes on
# Onetime::ActiveSessionGate.expired_condition, which knows about a
# remembered row's `remember_until` (migration 011). That is a private seam
# of rodauth's active_sessions feature, pinned here so a gem upgrade that
# renames the hook or stops routing the sweep through it fails this spec
# instead of silently reverting the sweep to Rodauth's rule (which would
# delete a remembered row left idle past the inactivity deadline).

require_relative '../../spec_helper'
require 'rodauth'
require 'rodauth/features/active_sessions'

# Auth::Config MUST be a Rodauth::Auth subclass, never a plain module or class
# (see the preamble in unit/omniauth_tenant_helpers_spec.rb).
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)
require_relative '../../../config/features/active_sessions'

RSpec.describe 'Auth::Config::Features::ActiveSessions sweep guard' do
  let(:db) { create_test_database }

  let(:app) do
    create_rodauth_app(db: db, features: [:base, :login, :logout, :active_sessions]) do
      Auth::Config::Features::ActiveSessions.configure(self)
    end
  end

  describe "rodauth's active_sessions feature (the seam being overridden)" do
    let(:feature) { Rodauth::ActiveSessions }

    it 'defines inactive_session_cond as a private instance method' do
      expect(feature.private_instance_methods(false)).to include(:inactive_session_cond)
    end

    it 'routes remove_inactive_sessions through inactive_session_cond' do
      path, line = feature.instance_method(:remove_inactive_sessions).source_location
      body       = File.readlines(path)[line - 1, 6].join

      expect(body).to include('inactive_session_cond')
    end
  end

  describe 'the override' do
    let(:rodauth) do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/',
        'rack.input' => StringIO.new,
        'rack.session' => {},
      }
      request = Roda::RodaRequest.new(app.new(env), env)
      app.rodauth.new(request.scope)
    end

    let(:account_id) { db[:accounts].insert(email: 'sweep-guard@example.com') }
    let(:rows)       { db[:account_active_session_keys].where(account_id: account_id) }

    let(:day) { 86_400 }

    def insert_row(session_id, last_use_ago:, remember_until_in: nil)
      db[:account_active_session_keys].insert(
        account_id: account_id,
        session_id: session_id,
        created_at: Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: last_use_ago),
        last_use: Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: last_use_ago),
        remember_until: remember_until_in && Sequel.date_add(Sequel::CURRENT_TIMESTAMP, seconds: remember_until_in),
      )
    end

    before do
      # The gate reads the remember-me switch when it builds the condition;
      # a feature spec has no booted Onetime config, so pin it on.
      allow(Onetime::RememberMe).to receive(:enabled?).and_return(true)

      rodauth.session[rodauth.session_key] = account_id

      insert_row('fresh',           last_use_ago: 60)
      insert_row('idle',            last_use_ago: 4 * day)
      insert_row('remembered-idle', last_use_ago: 4 * day, remember_until_in: 5 * day)
      insert_row('remember-lapsed', last_use_ago: 60, remember_until_in: -60)
    end

    it 'is private, as the Rodauth original is' do
      expect(app.rodauth.private_method_defined?(:inactive_session_cond)).to be true
    end

    it "returns the gate's expired_condition" do
      expect(rodauth.send(:inactive_session_cond)).to eq(Onetime::ActiveSessionGate.expired_condition)
    end

    it "sweeps on the gate's rule: idle default rows and lapsed remembered rows go, remembered idle rows stay", :aggregate_failures do
      rodauth.remove_inactive_sessions

      expect(rows.select_order_map(:session_id)).to eq(%w[fresh remembered-idle])
    end

    it "would have swept the remembered idle row on Rodauth's own rule (why the override exists)" do
      rodauth_rule = Rodauth::ActiveSessions.instance_method(:inactive_session_cond).bind_call(rodauth)

      expect(rows.where(rodauth_rule).select_order_map(:session_id)).to eq(%w[idle remembered-idle])
    end
  end
end
