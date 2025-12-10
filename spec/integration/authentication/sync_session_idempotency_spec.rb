# spec/integration/authentication/sync_session_idempotency_spec.rb
#
# frozen_string_literal: true

# Tests for SyncSession idempotency behavior.
# Ensures that repeated sync calls with the same session don't create duplicate state.

require 'spec_helper'
require 'rack/mock'

RSpec.describe 'SyncSession Idempotency', :full_auth_mode do
  include_context 'auth_rack_test'

  let(:test_email) { "idempotency-test-#{SecureRandom.hex(8)}@example.com" }
  let(:account) do
    # Use factory which correctly handles Rodauth schema (no created_at/updated_at columns)
    create_verified_account(db: test_db, email: test_email)
  end
  let(:account_id) { account[:id] }
  let(:session) { { 'session_id' => "test-session-#{account_id}" } }
  let(:request) do
    env = Rack::MockRequest.env_for('/')
    env['REMOTE_ADDR'] = '192.168.1.100'
    env['HTTP_USER_AGENT'] = 'Test Agent'
    Rack::Request.new(env)
  end

  after do
    # Clean up test account - delete from child tables first due to foreign keys
    if account_id
      test_db[:account_password_hashes].where(id: account_id).delete rescue nil
      test_db[:accounts].where(id: account_id).delete rescue nil
    end
    # Clean up Redis keys
    pattern = "sync_session:#{account_id}:*"
    keys = Familia.dbclient.keys(pattern)
    Familia.dbclient.del(*keys) if keys.any?
  end

  describe 'first sync call' do
    it 'creates customer and populates session' do
      customer = Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session,
        request: request
      )

      expect(customer).to be_a(Onetime::Customer)
      expect(session['authenticated']).to be true
      expect(session['account_id']).to eq(account_id)
      expect(session['email']).to eq(test_email)

      # Verify customer is linked to account via external_id
      linked_extid = test_db[:accounts].where(id: account_id).get(:external_id)
      expect(linked_extid).to eq(customer.extid)

      # Clean up customer
      customer.destroy! if customer&.exists?
    end
  end

  describe 'idempotency protection' do
    it 'returns same customer on repeated calls with same session' do
      customer1 = Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session,
        request: request
      )

      customer2 = Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session,
        request: request
      )

      expect(customer2.custid).to eq(customer1.custid)

      # Clean up customer
      customer1.destroy! if customer1&.exists?
    end

    it 'allows sync with different session ID for same account' do
      session1 = { 'session_id' => "test-session-1-#{account_id}" }
      session2 = { 'session_id' => "test-session-2-#{account_id}" }

      customer1 = Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session1,
        request: request
      )

      customer2 = Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session2,
        request: request
      )

      # Both sessions should be authenticated
      expect(session1['authenticated']).to be true
      expect(session2['authenticated']).to be true

      # Both should reference the same customer
      expect(session2['external_id']).to eq(customer1.extid)

      # Clean up customer
      customer1.destroy! if customer1&.exists?
    end

    it 'sets TTL on idempotency keys' do
      Auth::Operations::SyncSession.call(
        account: account,
        account_id: account_id,
        session: session,
        request: request
      )

      all_keys = Familia.dbclient.keys("sync_session:#{account_id}:*")
      expect(all_keys).not_to be_empty

      ttls = all_keys.map { |k| Familia.dbclient.ttl(k) }
      # TTL should be set (positive value, typically 300 seconds)
      expect(ttls).to all(be_between(0, 310))
    end
  end

  describe 'graceful degradation' do
    it 'works without Redis idempotency protection' do
      original_dbclient = Familia.instance_variable_get(:@dbclient)

      begin
        # Temporarily remove Redis client
        Familia.instance_variable_set(:@dbclient, nil)

        graceful_session = { 'session_id' => "test-session-no-redis-#{account_id}" }
        customer = Auth::Operations::SyncSession.call(
          account: account,
          account_id: account_id,
          session: graceful_session,
          request: request
        )

        expect(customer).to be_a(Onetime::Customer)
      ensure
        # Restore Redis connection
        Familia.instance_variable_set(:@dbclient, original_dbclient)
      end
    end
  end
end
