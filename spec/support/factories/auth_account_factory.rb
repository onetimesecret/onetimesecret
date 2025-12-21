# spec/support/factories/auth_account_factory.rb
#
# frozen_string_literal: true

require 'bcrypt'
require 'securerandom'

# Load shared auth test constants
require_relative '../../../apps/web/auth/spec/support/auth_test_constants'

# Factory methods for creating test accounts in Rodauth database.
#
# Usage:
#   include AuthAccountFactory
#
#   it 'creates account' do
#     account = create_verified_account(db: test_db, email: 'test@example.com')
#     expect(account[:email]).to eq('test@example.com')
#   end
#
module AuthAccountFactory
  include AuthTestConstants

  # All Rodauth tables that may contain test data (order matters for foreign keys)
  RODAUTH_TABLES = %i[
    account_sms_codes
    account_recovery_codes
    account_otp_unlocks
    account_otp_keys
    account_webauthn_keys
    account_webauthn_user_ids
    account_session_keys
    account_active_session_keys
    account_activity_times
    account_password_change_times
    account_email_auth_keys
    account_lockouts
    account_login_failures
    account_remember_keys
    account_login_change_keys
    account_verification_keys
    account_jwt_refresh_keys
    account_password_reset_keys
    account_authentication_audit_logs
    account_password_hashes
    accounts
  ].freeze

  # Account status IDs inherited from AuthTestConstants

  # Create a verified account with password
  #
  # @param db [Sequel::Database] The test database
  # @param email [String] Account email (default: random)
  # @param password [String] Account password (default: 'Test1234!@')
  # @param with_mfa [Boolean] Whether to set up OTP (default: false)
  # @return [Hash] The created account row
  def create_verified_account(db:, email: nil, password: 'Test1234!@', with_mfa: false)
    email ||= "test-#{SecureRandom.hex(8)}@example.com"

    account_id = db[:accounts].insert(
      email: email,
      status_id: STATUS_VERIFIED,
      external_id: SecureRandom.uuid
    )

    # Create password hash using BCrypt (matches Rodauth's default)
    password_hash = BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST)
    db[:account_password_hashes].insert(
      id: account_id,
      password_hash: password_hash,
      created_at: Time.now
    )

    if with_mfa
      setup_otp_for_account(db: db, account_id: account_id)
    end

    db[:accounts].where(id: account_id).first
  end

  # Create an unverified account (pending email verification)
  #
  # @param db [Sequel::Database] The test database
  # @param email [String] Account email (default: random)
  # @param password [String] Account password (default: 'Test1234!@')
  # @return [Hash] The created account row
  def create_unverified_account(db:, email: nil, password: 'Test1234!@')
    email ||= "unverified-#{SecureRandom.hex(8)}@example.com"

    account_id = db[:accounts].insert(
      email: email,
      status_id: STATUS_UNVERIFIED,
      external_id: SecureRandom.uuid
    )

    # Create password hash
    password_hash = BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST)
    db[:account_password_hashes].insert(
      id: account_id,
      password_hash: password_hash,
      created_at: Time.now
    )

    # Create verification key
    db[:account_verification_keys].insert(
      id: account_id,
      key: SecureRandom.urlsafe_base64(32),
      requested_at: Time.now,
      email_last_sent: Time.now
    )

    db[:accounts].where(id: account_id).first
  end

  # Set up OTP (TOTP) for an existing account
  #
  # @param db [Sequel::Database] The test database
  # @param account_id [Integer] The account ID
  # @return [String] The OTP secret key
  def setup_otp_for_account(db:, account_id:)
    # Generate a TOTP key (16 bytes = 128 bits, base32 encoded)
    otp_key = SecureRandom.random_bytes(16).unpack1('H*')

    db[:account_otp_keys].insert(
      id: account_id,
      key: otp_key,
      num_failures: 0,
      last_use: Time.now
    )

    otp_key
  end

  # Create recovery codes for an account with MFA
  #
  # @param db [Sequel::Database] The test database
  # @param account_id [Integer] The account ID
  # @param count [Integer] Number of codes to generate (default: RECOVERY_CODES_LIMIT)
  # @return [Array<String>] The generated recovery codes
  def create_recovery_codes(db:, account_id:, count: MFA_RECOVERY_CODES_LIMIT)
    codes = count.times.map { SecureRandom.alphanumeric(12).downcase }

    codes.each do |code|
      db[:account_recovery_codes].insert(
        id: account_id,
        code: BCrypt::Password.create(code, cost: BCrypt::Engine::MIN_COST)
      )
    end

    codes
  end

  # Create an active session for an account
  #
  # @param db [Sequel::Database] The test database
  # @param account_id [Integer] The account ID
  # @param session_id [String] Session ID (default: random)
  # @return [String] The session ID
  def create_active_session(db:, account_id:, session_id: nil)
    session_id ||= SecureRandom.urlsafe_base64(32)

    db[:account_active_session_keys].insert(
      account_id: account_id,
      session_id: session_id,
      created_at: Time.now,
      last_use: Time.now
    )

    session_id
  end

  # Clean up all data for an account
  #
  # @param db [Sequel::Database] The test database
  # @param account_id [Integer] The account ID to clean up
  def cleanup_account(db:, account_id:)
    return unless account_id

    # Delete from tables with foreign keys first
    RODAUTH_TABLES.each do |table|
      column = table == :accounts ? :id : (db[table].columns.include?(:account_id) ? :account_id : :id)
      db[table].where(column => account_id).delete
    rescue Sequel::DatabaseError
      # Table might not exist or column might not match
      nil
    end
  end

  # Clean up all test accounts (use in after(:all))
  #
  # @param db [Sequel::Database] The test database
  def cleanup_all_accounts(db:)
    RODAUTH_TABLES.each do |table|
      db[table].delete
    rescue Sequel::DatabaseError
      nil
    end
  end
end
