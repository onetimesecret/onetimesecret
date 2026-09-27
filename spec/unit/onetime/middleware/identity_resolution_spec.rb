# spec/unit/onetime/middleware/identity_resolution_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/session'
require 'onetime/middleware/identity_resolution'

# The middleware resolves whatever session Onetime::Session handed it as
# live: the store has already ended sessions past their absolute deadline
# and holds the rest to the rolling lifetime through the blob TTL. It must
# not re-derive expiry from the age of `authenticated_at` (it once did,
# against the rolling `expire_after`, which treated a session signed in 24h
# ago as anonymous however active it was), and `expires_at` is the
# session's absolute deadline, not sign-in plus a day.
RSpec.describe Onetime::Middleware::IdentityResolution do
  let(:now) { Time.now.to_i }
  let(:observed) { {} }

  def lifetime
    Onetime::ActiveSessionGate::DEFAULT_LIFETIME_DEADLINE
  end

  def long_ago
    now - (Onetime.session_config['expire_after'].to_i * 3)
  end

  def middleware
    downstream = ->(env) do
      observed[:authenticated] = env['identity.authenticated']
      observed[:source]        = env['identity.source']
      observed[:metadata]      = env['identity.metadata']
      [200, {}, ['']]
    end
    described_class.new(downstream)
  end

  before do
    allow(Onetime).to receive(:session_config).and_wrap_original do |original|
      original.call.merge('absolute_timeout' => lifetime)
    end
  end

  def call_with(session, mode:)
    allow(Onetime.auth_config).to receive(:mode).and_return(mode)
    env = Rack::MockRequest.env_for('/', 'rack.session' => session)
    middleware.call(env)
    observed
  end

  describe 'full mode' do
    before do
      customer = instance_double(Onetime::Customer, objid: 'cust1', extid: 'ur_full')
      allow(Onetime::Customer).to receive(:find_by_extid).with('ur_full').and_return(customer)
    end

    it 'resolves a session signed in long before the rolling lifetime as authenticated', :aggregate_failures do
      result = call_with({ 'authenticated_at' => long_ago, 'external_id' => 'ur_full', 'account_external_id' => 'ur_full' }, mode: 'full')
      expect(result[:authenticated]).to be(true)
      expect(result[:source]).to eq('full')
    end

    it 'reports the absolute deadline as expires_at' do
      result = call_with({ 'authenticated_at' => now, 'external_id' => 'ur_full', 'account_external_id' => 'ur_full' }, mode: 'full')
      expect(result[:metadata][:expires_at]).to eq(now + lifetime)
    end

    it 'reports a nearer remember deadline as expires_at' do
      stamp  = now + 3600
      result = call_with({ 'authenticated_at' => now, 'remember_until' => stamp, 'external_id' => 'ur_full', 'account_external_id' => 'ur_full' }, mode: 'full')
      expect(result[:metadata][:expires_at]).to eq(stamp)
    end

    it 'still needs the sign-in markers', :aggregate_failures do
      expect(call_with({ 'external_id' => 'ur_full' }, mode: 'full')[:authenticated]).to be(false)
      expect(call_with({ 'authenticated_at' => now }, mode: 'full')[:authenticated]).to be(false)
    end
  end
end
