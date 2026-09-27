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
  let(:session_hash) do
    # A Rack session hash answers `id` (Rack::Session::Abstract::SessionHash);
    # a bare Hash does not, and the simple-mode resolver reads it.
    Class.new(Hash) { def id = nil }
  end

  def lifetime
    Onetime::ActiveSessionGate::DEFAULT_LIFETIME_DEADLINE
  end

  def long_ago
    now - (Onetime.session_config['expire_after'].to_i * 3)
  end

  def middleware
    downstream = ->(env) do
      observed[:resolved]      = env['identity.resolved']
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

  def call_with(session_data, mode:)
    allow(Onetime.auth_config).to receive(:mode).and_return(mode)
    session = session_hash.new.update(session_data)
    env     = Rack::MockRequest.env_for('/', 'rack.session' => session)
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

  # Simple mode never loads the Customer (controllers lazy-load it), so its
  # result carries no user. The mode switch must still surface it: gating on
  # the user would send every signed-in simple-mode session to anonymous.
  describe 'simple mode' do
    it 'resolves a signed-in session without a user', :aggregate_failures do
      result = call_with({ 'authenticated' => true, 'authenticated_at' => long_ago, 'external_id' => 'ur_simple' }, mode: 'simple')
      expect(result[:authenticated]).to be(true)
      expect(result[:source]).to eq('simple')
      expect(result[:resolved]).to be_nil
      expect(result[:metadata][:external_id]).to eq('ur_simple')
    end

    it 'reports the absolute deadline as expires_at' do
      result = call_with({ 'authenticated' => true, 'authenticated_at' => now }, mode: 'simple')
      expect(result[:metadata][:expires_at]).to eq(now + lifetime)
    end

    it 'reports a nearer remember deadline as expires_at' do
      stamp  = now + 3600
      result = call_with({ 'authenticated' => true, 'authenticated_at' => now, 'remember_until' => stamp }, mode: 'simple')
      expect(result[:metadata][:expires_at]).to eq(stamp)
    end

    it 'falls through to anonymous without the authenticated flag', :aggregate_failures do
      result = call_with({ 'authenticated_at' => now, 'external_id' => 'ur_simple' }, mode: 'simple')
      expect(result[:authenticated]).to be(false)
      expect(result[:source]).to eq('anonymous')
    end
  end
end
