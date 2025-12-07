# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/mfa_complete_flow_try.rb
# Updated: 2025-12-06 19:02:24 -0800

require 'spec_helper'

RSpec.describe 'mfa_complete_flow_try', :full_auth_mode do
  before(:all) do
    if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
      raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
    end
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
    def create_test_account(prefix, with_mfa: false)
      email = "#{prefix}-#{Familia.now.to_i}@example.com"
      password_hash = BCrypt::Password.create("SecurePass123!", cost: BCrypt::Engine::MIN_COST)
      @db.transaction do
        account_id = @db[:accounts].insert(
          email: email,
          status_id: 2, # verified
          created_at: Time.now,
          updated_at: Time.now
        )
        # Insert password hash in separate table
        @db[:account_password_hashes].insert(
          id: account_id,
          password_hash: password_hash.to_s
        )
        if with_mfa
          # Create OTP key to simulate MFA setup
          require 'rotp'
          otp_secret = ROTP::Base32.random
          @db[:account_otp_keys].insert(
            id: account_id,
            key: otp_secret,
            num_failures: 0,
            last_use: Time.now - 3600
          )
          { account_id: account_id, email: email, otp_secret: otp_secret }
        else
          { account_id: account_id, email: email }
        end
      end
    end
    def cleanup_account(account_id)
      return unless account_id
      @db[:account_otp_keys].where(id: account_id).delete rescue nil
      @db[:account_password_hashes].where(id: account_id).delete rescue nil
      @db[:accounts].where(id: account_id).delete rescue nil
      # Clean up idempotency keys
      pattern = "sync_session:#{account_id}:*"
      keys = Familia.dbclient.keys(pattern)
      Familia.dbclient.del(*keys) if keys.any? rescue nil
    end
  end

  it 'Test 1.1: Create account with MFA enabled' do
    result = begin
      @mfa_account = create_test_account('mfa-flow', with_mfa: true)
      @mfa_account[:account_id]
    end
  end

  it 'Test 1.2: Verify OTP key exists in database' do
    result = begin
      @db[:account_otp_keys].where(id: @mfa_account[:account_id]).count
    end
    expect(result).to eq(1)
  end

  it 'Test 1.3: Test MFA detection operation directly' do
    result = begin
      @mfa_account_data = @db[:accounts].where(id: @mfa_account[:account_id]).first
      @mfa_session = { 'session_id' => 'test-mfa-session' }
      @mock_rodauth = Object.new
      def @mock_rodauth.uses_two_factor_authentication?
        true
      end
      @mfa_decision = Auth::Operations::DetectMfaRequirement.call(
        account: @mfa_account_data,
        session: @mfa_session,
        rodauth: @mock_rodauth
      )
      @mfa_decision.requires_mfa?
    end
    expect(result).to eq(true)
  end

  it 'Test 1.4: MFA should defer session sync' do
    result = begin
      @mfa_decision.defer_session_sync?
    end
    expect(result).to eq(true)
  end

  it 'Test 1.5: Create mock request for session sync' do
    result = begin
      @mfa_env = Rack::MockRequest.env_for('/')
      @mfa_env['REMOTE_ADDR'] = '192.168.1.100'
      @mfa_env['HTTP_USER_AGENT'] = 'Test Agent'
      @mfa_request = Rack::Request.new(@mfa_env)
      nil
    end
    expect(result).to eq(nil)
  end

  it 'Test 1.6: Simulate session sync after MFA verification' do
    result = begin
      @mfa_customer = Auth::Operations::SyncSession.call(
        account: @mfa_account_data,
        account_id: @mfa_account[:account_id],
        session: @mfa_session,
        request: @mfa_request
      )
      @mfa_customer.class.name
    end
    expect(result).to eq("Onetime::Customer")
  end

  it 'Test 1.7: Session should be populated with authentication data' do
    result = begin
      [@mfa_session['authenticated'], @mfa_session['account_id'], @mfa_session['email']]
    end
    expect(result).to eq([true, @mfa_account[:account_id], @mfa_account[:email]])
  end

  it 'Test 1.8: Customer should be linked to account' do
    result = begin
      @linked_account = @db[:accounts].where(id: @mfa_account[:account_id]).first
      @linked_account[:external_id] == @mfa_customer.extid
    end
    expect(result).to eq(true)
  end

  it 'Test 2.1: Create account WITHOUT MFA' do
    result = begin
      @no_mfa_account = create_test_account('no-mfa-flow', with_mfa: false)
      @no_mfa_account[:account_id]
    end
  end

  it 'Test 2.2: Verify NO OTP key in database' do
    result = begin
      @db[:account_otp_keys].where(id: @no_mfa_account[:account_id]).count
    end
    expect(result).to eq(0)
  end

  it 'Test 2.3: Test MFA detection for non-MFA account' do
    result = begin
      @no_mfa_account_data = @db[:accounts].where(id: @no_mfa_account[:account_id]).first
      @no_mfa_session = { 'session_id' => 'test-no-mfa-session' }
      @mock_rodauth_no_mfa = Object.new
      def @mock_rodauth_no_mfa.uses_two_factor_authentication?
        false
      end
      @no_mfa_decision = Auth::Operations::DetectMfaRequirement.call(
        account: @no_mfa_account_data,
        session: @no_mfa_session,
        rodauth: @mock_rodauth_no_mfa
      )
      @no_mfa_decision.requires_mfa?
    end
    expect(result).to eq(false)
  end

  it 'Test 2.4: Should sync session immediately (no deferral)' do
    result = begin
      @no_mfa_decision.sync_session_now?
    end
    expect(result).to eq(true)
  end

  it 'Test 2.5: Create mock request and sync session' do
    result = begin
      @no_mfa_env = Rack::MockRequest.env_for('/')
      @no_mfa_env['REMOTE_ADDR'] = '192.168.1.101'
      @no_mfa_request = Rack::Request.new(@no_mfa_env)
      @no_mfa_customer = Auth::Operations::SyncSession.call(
        account: @no_mfa_account_data,
        account_id: @no_mfa_account[:account_id],
        session: @no_mfa_session,
        request: @no_mfa_request
      )
      @no_mfa_customer.class.name
    end
    expect(result).to eq("Onetime::Customer")
  end

  it 'Test 2.6: Session should be immediately populated' do
    result = begin
      @no_mfa_session['authenticated']
    end
    expect(result).to eq(true)
  end

  it 'Test 3.1: Create account for idempotency test' do
    result = begin
      @idem_account = create_test_account('idempotency-test', with_mfa: false)
      @idem_account_data = @db[:accounts].where(id: @idem_account[:account_id]).first
      @idem_session = { 'session_id' => 'test-idem-session' }
      @idem_env = Rack::MockRequest.env_for('/')
      @idem_request = Rack::Request.new(@idem_env)
      nil
    end
    expect(result).to eq(nil)
  end

  it 'Test 3.2: First sync should succeed' do
    result = begin
      @idem_customer1 = Auth::Operations::SyncSession.call(
        account: @idem_account_data,
        account_id: @idem_account[:account_id],
        session: @idem_session,
        request: @idem_request
      )
      @idem_customer1.class.name
    end
    expect(result).to eq("Onetime::Customer")
  end

  it 'Test 3.3: Second sync with same session should be idempotent' do
    result = begin
      @idem_customer2 = Auth::Operations::SyncSession.call(
        account: @idem_account_data,
        account_id: @idem_account[:account_id],
        session: @idem_session,
        request: @idem_request
      )
      @idem_customer2.custid == @idem_customer1.custid
    end
    expect(result).to eq(true)
  end

  it 'Test 3.4: Third sync should also return same customer' do
    result = begin
      @idem_customer3 = Auth::Operations::SyncSession.call(
        account: @idem_account_data,
        account_id: @idem_account[:account_id],
        session: @idem_session,
        request: @idem_request
      )
      @idem_customer3.custid == @idem_customer1.custid
    end
    expect(result).to eq(true)
  end

  it 'Test 3.5: Verify only one customer created (not duplicated)' do
    result = begin
      customers_found = 0
      begin
        cust = Onetime::Customer.find_by_email(@idem_account[:email])
        customers_found = 1 if cust
      rescue
        customers_found = 0
      end
      customers_found
    end
    expect(result).to eq(1)
  end

  it 'Cleanup: Remove all test accounts and data' do
    result = begin
      cleanup_account(@mfa_account[:account_id])
      cleanup_account(@no_mfa_account[:account_id])
      cleanup_account(@idem_account[:account_id])
      [@mfa_customer, @no_mfa_customer, @idem_customer1].compact.each do |customer|
        customer.destroy! if customer&.exists? rescue nil
      end
      nil
    end
    expect(result).to eq(nil)
  end

  it 'Cleanup: Verify all test accounts removed' do
    result = begin
      test_account_ids = [
        @mfa_account[:account_id],
        @no_mfa_account[:account_id],
        @idem_account[:account_id]
      ]
      test_account_ids.all? { |id| @db[:accounts].where(id: id).count == 0 }
    end
    expect(result).to eq(true)
  end

end
