# spec/integration/full/infrastructure_spec.rb
#
# frozen_string_literal: true

# Verify that the test infrastructure for full auth mode is working correctly.
# These tests validate our shared contexts, factories, and helpers before
# running the actual auth specs.

require 'spec_helper'

RSpec.describe 'Full Mode Test Infrastructure', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'auth/database'
  end

  describe 'MockAuthConfig' do
    it 'reports full mode as enabled' do
      expect(Onetime.auth_config.full_enabled?).to be true
    end

    it 'reports simple mode as disabled' do
      expect(Onetime.auth_config.simple_enabled?).to be false
    end

    it 'returns sqlite::memory: as database_url' do
      expect(Onetime.auth_config.database_url).to eq('sqlite::memory:')
    end

    it 'has feature toggles' do
      expect(Onetime.auth_config).to respond_to(:mfa_enabled)
      expect(Onetime.auth_config).to respond_to(:magic_links_enabled)
      expect(Onetime.auth_config).to respond_to(:security_features_enabled)
    end
  end

  describe 'FullModeSuiteDatabase' do
    # test_db is provided by FullModeSuiteDatabase for all :full_auth_mode specs

    it 'provides a test_db' do
      expect(test_db).to be_a(Sequel::Database)
    end

    it 'creates accounts table' do
      expect(test_db.tables).to include(:accounts)
    end

    it 'creates account_password_hashes table' do
      expect(test_db.tables).to include(:account_password_hashes)
    end

    it 'creates account_statuses with seed data' do
      statuses = test_db[:account_statuses].all
      expect(statuses.map { |s| s[:name] }).to contain_exactly('Unverified', 'Verified', 'Closed')
    end

    it 'creates account_otp_keys table for MFA' do
      expect(test_db.tables).to include(:account_otp_keys)
    end

    it 'creates account_active_session_keys table' do
      expect(test_db.tables).to include(:account_active_session_keys)
    end
  end

  describe 'AuthAccountFactory' do
    # test_db and AuthAccountFactory are provided by FullModeSuiteDatabase

    describe '#create_verified_account' do
      it 'creates an account with verified status' do
        account = create_verified_account(db: test_db, email: 'test@example.com')
        expect(account[:status_id]).to eq(AuthAccountFactory::STATUS_VERIFIED)
        expect(account[:email]).to eq('test@example.com')
      end

      it 'creates a password hash' do
        account = create_verified_account(db: test_db, email: 'pwd@example.com')
        hash_row = test_db[:account_password_hashes].where(id: account[:id]).first
        expect(hash_row).not_to be_nil
        expect(hash_row[:password_hash]).to start_with('$2')
      end

      it 'generates random email when not provided' do
        account = create_verified_account(db: test_db)
        expect(account[:email]).to match(/test-[a-f0-9]+@example\.com/)
      end
    end

    describe '#create_verified_account with MFA' do
      it 'creates OTP key when with_mfa: true' do
        account = create_verified_account(db: test_db, email: 'mfa@example.com', with_mfa: true)
        otp_row = test_db[:account_otp_keys].where(id: account[:id]).first
        expect(otp_row).not_to be_nil
        expect(otp_row[:key]).not_to be_empty
      end
    end

    describe '#create_unverified_account' do
      it 'creates account with unverified status' do
        account = create_unverified_account(db: test_db, email: 'unverified@example.com')
        expect(account[:status_id]).to eq(AuthAccountFactory::STATUS_UNVERIFIED)
      end

      it 'creates verification key' do
        account = create_unverified_account(db: test_db, email: 'verify-key@example.com')
        verify_row = test_db[:account_verification_keys].where(id: account[:id]).first
        expect(verify_row).not_to be_nil
        expect(verify_row[:key]).not_to be_empty
      end
    end

    describe '#cleanup_account' do
      it 'removes account and related data' do
        account = create_verified_account(db: test_db, email: 'cleanup@example.com', with_mfa: true)
        cleanup_account(db: test_db, account_id: account[:id])

        expect(test_db[:accounts].where(id: account[:id]).count).to eq(0)
        expect(test_db[:account_password_hashes].where(id: account[:id]).count).to eq(0)
        expect(test_db[:account_otp_keys].where(id: account[:id]).count).to eq(0)
      end
    end

    describe '#create_active_session' do
      it 'creates a session for an account' do
        account = create_verified_account(db: test_db, email: 'session@example.com')
        session_id = create_active_session(db: test_db, account_id: account[:id])

        session_row = test_db[:account_active_session_keys].where(
          account_id: account[:id],
          session_id: session_id
        ).first
        expect(session_row).not_to be_nil
      end
    end
  end

  describe 'auth_rack_test context' do
    include_context 'auth_rack_test'

    it 'provides an app' do
      expect(app).to respond_to(:call)
    end

    it 'provides json_response helper' do
      get '/api/v2/status'
      expect { json_response }.not_to raise_error
    end

    it 'provides post_json helper' do
      expect { post_json('/nonexistent', {}) }.not_to raise_error
    end

    it 'provides get_json helper' do
      expect { get_json('/api/v2/status') }.not_to raise_error
    end
  end

  describe 'AuthModeHelpers.reset_database_connection!' do
    it 'clears memoized connection' do
      # Save original connection
      original = Auth::Database.instance_variable_get(:@connection)

      # Set a fake memoized value
      Auth::Database.instance_variable_set(:@connection, 'fake')
      AuthModeHelpers.reset_database_connection!

      # Verify connection was reset (either nil or original lazy proxy restored)
      current = Auth::Database.instance_variable_get(:@connection)
      expect(current).not_to eq('fake')
    end
  end

  describe 'Auth::Database lazy connection' do
    it 'provides reset_connection! method' do
      expect(Auth::Database).to respond_to(:reset_connection!)
    end

    it 'provides connected? method' do
      expect(Auth::Database).to respond_to(:connected?)
    end
  end
end
