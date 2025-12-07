# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/sync_session_idempotency_try.rb
# Updated: 2025-12-06 19:02:33 -0800

require 'spec_helper'

RSpec.describe 'sync_session_idempotency_try', :full_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.prepare_application_registry
    require 'rack'
    require 'rack/mock'
    @db = Auth::Database.connection
    @account_id = nil
    @account = nil
    @session = {}
    @request = nil
    @db.transaction do
      email = "idempotency-test-#{Familia.now.to_i}@example.com"
      @account_id = @db[:accounts].insert(
        email: email,
        status_id: 2, # verified
        created_at: Time.now,
        updated_at: Time.now
      )
      @account = @db[:accounts].where(id: @account_id).first
    end
    env = Rack::MockRequest.env_for('/')
    env['REMOTE_ADDR'] = '192.168.1.100'
    env['HTTP_USER_AGENT'] = 'Test Agent'
    @request = Rack::Request.new(env)
    @session = { 'session_id' => "test-session-#{@account_id}" }
  end

  it 'First sync should succeed and create customer' do
    result = begin
      @customer = Auth::Operations::SyncSession.call(
        account: @account,
        account_id: @account_id,
        session: @session,
        request: @request
      )
      @customer.class.name
    end
    expect(result).to eq("Onetime::Customer")
  end

  it 'Session should be populated' do
    result = begin
      [@session['authenticated'], @session['account_id'], @session['email']]
    end
    expect(result).to eq([true, @account_id, @account[:email]])
  end

  it 'Customer should be linked to account' do
    result = begin
      linked_extid = @db[:accounts].where(id: @account_id).get(:external_id)
      linked_extid == @customer.extid
    end
    expect(result).to eq(true)
  end

  it 'Second call with same session should skip (idempotency protection)' do
    result = begin
      @customer2 = Auth::Operations::SyncSession.call(
        account: @account,
        account_id: @account_id,
        session: @session,
        request: @request
      )
      @customer2.custid == @customer.custid
    end
    expect(result).to eq(true)
  end

  it 'Create new session with different ID' do
    result = begin
      @session2 = { 'session_id' => "test-session-different-#{@account_id}" }
      @customer3 = Auth::Operations::SyncSession.call(
        account: @account,
        account_id: @account_id,
        session: @session2,
        request: @request
      )
      [@session2['authenticated'], @session2['external_id'] == @customer.extid]
    end
    expect(result).to eq([true, true])
  end

  it 'Temporarily disable Redis to test graceful degradation' do
    result = begin
      original_dbclient = Familia.instance_variable_get(:@dbclient)
      begin
        # Mock Redis unavailability
        Familia.instance_variable_set(:@dbclient, nil)
        @session3 = { 'session_id' => "test-session-no-redis-#{@account_id}" }
        # Should still work without Redis (no idempotency protection)
        @customer4 = Auth::Operations::SyncSession.call(
          account: @account,
          account_id: @account_id,
          session: @session3,
          request: @request
        )
        @customer4.class.name
      ensure
        # Restore Redis connection
        Familia.instance_variable_set(:@dbclient, original_dbclient)
      end
    end
    expect(result).to eq("Onetime::Customer")
  end

  it 'Check that idempotency keys from earlier tests have TTL set' do
    result = begin
      all_keys = Familia.dbclient.keys("sync_session:#{@account_id}:*")
      ttls = all_keys.map { |k| Familia.dbclient.ttl(k) }
      ttls.all? { |ttl| (0..310).include?(ttl) }
    end
    expect(result).to eq(true)
  end

  it 'Delete test account' do
    result = begin
      @db[:accounts].where(id: @account_id).delete if @account_id
      @customer.destroy! if @customer&.exists?
      pattern = "sync_session:#{@account_id}:*"
      keys = Familia.dbclient.keys(pattern)
      Familia.dbclient.del(*keys) if keys.any?
      nil
    end
    expect(result).to eq(nil)
  end

end
