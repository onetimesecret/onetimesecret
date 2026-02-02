# spec/integration/full/password_migration_spec.rb
#
# frozen_string_literal: true

require_relative '../integration_spec_helper'
require 'rack/test'
require 'bcrypt'
require 'argon2'

# Integration test for zero-downtime password migration from Redis to Rodauth
#
# Tests the scenario where:
# 1. A user exists in Redis (Customer) with a bcrypt passphrase
# 2. An account exists in Rodauth WITHOUT a password hash
# 3. On login with the Redis password, the system:
#    - Verifies against Redis Customer record
#    - Creates argon2 hash in Rodauth account_password_hashes
#    - Allows login to succeed
# 4. Subsequent logins use Rodauth directly
#
# Requirements:
# - Valkey running on port 2121 (pnpm run test:database:start)
# - Full auth mode enabled
#
RSpec.describe 'Password Migration from Redis to Rodauth', type: :integration do
  include Rack::Test::Methods

  # Rack::Test requires an `app` method
  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  # Access auth database for direct assertions
  def auth_db
    Auth::Database.connection
  end

  # Unique test data for isolation
  let(:test_email) { "migration-test-#{SecureRandom.hex(8)}@example.com" }
  let(:test_password) { 'SecureTestP@ss123!' }

  before(:all) do
    # Set full mode before loading the application
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset registries to clear state from previous test runs
    Onetime::Application::Registry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application (Redis/Valkey must be running on port 2121)
    Onetime.boot! :test

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  after(:each) do
    # Clean up test Customer from Redis
    if defined?(@test_customer) && @test_customer
      begin
        @test_customer.delete!
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    # Clean up test account from Rodauth database
    # Delete in order: child tables first, then parent
    if defined?(@test_account_id) && @test_account_id
      begin
        # Session and security tables (reference account_id or id)
        auth_db[:account_active_session_keys].where(account_id: @test_account_id).delete
        auth_db[:account_login_failures].where(id: @test_account_id).delete
        auth_db[:account_lockouts].where(id: @test_account_id).delete
        auth_db[:account_remember_keys].where(id: @test_account_id).delete
        auth_db[:account_password_hashes].where(id: @test_account_id).delete
        # Finally delete the account
        auth_db[:accounts].where(id: @test_account_id).delete
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    # Reset CSRF token for next test
    reset_csrf_token if respond_to?(:reset_csrf_token)
  end

  # Establish session and get CSRF token
  def ensure_csrf_token
    return @csrf_token if defined?(@csrf_token) && @csrf_token

    header 'Accept', 'application/json'
    get '/auth'
    @csrf_token = last_response.headers['X-CSRF-Token']
    @csrf_token
  end

  def reset_csrf_token
    @csrf_token = nil
  end

  # Make a login request in a fresh browser session (no shared cookies/state)
  def login_in_fresh_session(email:, password:)
    # Use Rack::Test's with_session to create isolated session
    with_session('fresh_login') do
      # Get CSRF token in fresh session
      header 'Accept', 'application/json'
      get '/auth'
      csrf_token = last_response.headers['X-CSRF-Token']

      # Make login request
      header 'Content-Type', 'application/json'
      header 'Accept', 'application/json'
      header 'X-CSRF-Token', csrf_token if csrf_token
      post '/auth/login', JSON.generate({
        login: email,
        password: password,
        shrimp: csrf_token
      })

      last_response
    end
  end

  # Helper to POST JSON with CSRF token
  def json_post_with_csrf(path, params)
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token
    post path, JSON.generate(params.merge(shrimp: csrf_token))
  end

  # Create a Customer in Redis with bcrypt passphrase
  def create_redis_customer_with_bcrypt(email:, password:)
    customer = Onetime::Customer.create!(email)
    customer.update_passphrase(password, algorithm: :bcrypt)
    customer.save

    @test_customer = customer
    customer
  end

  # Create a Rodauth account WITHOUT password hash
  def create_rodauth_account_without_password(email:, external_id: nil)
    external_id ||= SecureRandom.uuid

    # Insert account with verified status (status_id: 2)
    account_id = auth_db[:accounts].insert(
      email: email,
      status_id: 2, # Verified
      external_id: external_id
    )

    @test_account_id = account_id
    account_id
  end

  # Check if password hash exists for account
  def password_hash_exists?(account_id)
    auth_db[:account_password_hashes].where(id: account_id).count > 0
  end

  # Get the password hash for an account
  def get_password_hash(account_id)
    record = auth_db[:account_password_hashes].where(id: account_id).first
    record&.fetch(:password_hash, nil)
  end

  describe 'when password_migration hook is enabled' do
    context 'user exists in Redis with bcrypt, Rodauth account has no password' do
      it 'migrates password on successful login' do
        # Step 1: Create Customer in Redis with bcrypt passphrase
        customer = create_redis_customer_with_bcrypt(
          email: test_email,
          password: test_password
        )

        # Verify Redis Customer has bcrypt passphrase
        expect(customer.has_passphrase?).to be true
        expect(customer.passphrase?(test_password)).to be true
        expect(customer.passphrase_encryption).to eq('1') # bcrypt

        # Step 2: Create Rodauth account WITHOUT password hash
        account_id = create_rodauth_account_without_password(
          email: test_email,
          external_id: customer.extid
        )

        # Verify no password hash exists in Rodauth
        expect(password_hash_exists?(account_id)).to be false

        # Step 3: POST to /auth/login with Redis password
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: test_password
        }

        # Step 4: Verify login succeeds (200 or 3xx redirect)
        # Note: Actual response may vary based on MFA requirements
        expect(last_response.status).to be_between(200, 399)

        # Step 5: Verify password hash now exists in account_password_hashes
        expect(password_hash_exists?(account_id)).to be true

        # Verify the migrated hash is argon2id format
        migrated_hash = get_password_hash(account_id)
        expect(migrated_hash).to start_with('$argon2id$')
      end

      it 'allows subsequent login via Rodauth directly' do
        # Setup: Create Redis Customer and Rodauth account, perform migration
        customer = create_redis_customer_with_bcrypt(
          email: test_email,
          password: test_password
        )

        account_id = create_rodauth_account_without_password(
          email: test_email,
          external_id: customer.extid
        )

        # First login triggers migration
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: test_password
        }

        expect(password_hash_exists?(account_id)).to be true

        # Second login in fresh session - uses migrated Rodauth password
        response = login_in_fresh_session(
          email: test_email,
          password: test_password
        )

        expect(response.status).to be_between(200, 399)
      end
    end

    context 'Redis password verification fails' do
      it 'rejects login with wrong password' do
        # Create Customer in Redis
        customer = create_redis_customer_with_bcrypt(
          email: test_email,
          password: test_password
        )

        # Create Rodauth account without password
        account_id = create_rodauth_account_without_password(
          email: test_email,
          external_id: customer.extid
        )

        # Attempt login with wrong password
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: 'WrongPassword123!'
        }

        # Should fail authentication
        expect(last_response.status).to eq(401)

        # Password should NOT be migrated
        expect(password_hash_exists?(account_id)).to be false
      end
    end

    context 'Rodauth account already has password hash' do
      it 'skips migration and uses Rodauth password' do
        # Create Redis Customer with one password
        customer = create_redis_customer_with_bcrypt(
          email: test_email,
          password: 'RedisPassword123!'
        )

        # Create Rodauth account WITH a different password
        rodauth_password = 'RodauthPassword456!'
        account_id = create_rodauth_account_without_password(
          email: test_email,
          external_id: customer.extid
        )

        # Manually insert password hash for Rodauth
        rodauth_hash = ::Argon2::Password.create(
          rodauth_password,
          { t_cost: 1, m_cost: 5, p_cost: 1 } # Test cost params
        )
        auth_db[:account_password_hashes].insert(
          id: account_id,
          password_hash: rodauth_hash,
          created_at: Time.now
        )

        # Login with Rodauth password should succeed
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: rodauth_password
        }

        expect(last_response.status).to be_between(200, 399)

        # Login with Redis password in fresh session should fail
        # (migration not triggered because Rodauth hash already exists)
        response = login_in_fresh_session(
          email: test_email,
          password: 'RedisPassword123!'
        )

        expect(response.status).to eq(401)
      end
    end

    context 'no Redis Customer exists' do
      it 'fails login when Rodauth account has no password' do
        # Create Rodauth account without password (no Redis Customer)
        account_id = create_rodauth_account_without_password(
          email: test_email
        )

        # Attempt login
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: test_password
        }

        # Should fail - no password in Rodauth, no Customer in Redis
        expect(last_response.status).to eq(401)

        # No password should be created
        expect(password_hash_exists?(account_id)).to be false
      end
    end

    context 'Redis Customer exists but has no passphrase' do
      it 'fails login when Customer has no passphrase' do
        # Create Customer without passphrase
        customer = Onetime::Customer.create!(test_email)
        customer.save
        @test_customer = customer

        expect(customer.has_passphrase?).to be false

        # Create Rodauth account without password
        account_id = create_rodauth_account_without_password(
          email: test_email,
          external_id: customer.extid
        )

        # Attempt login
        json_post_with_csrf '/auth/login', {
          login: test_email,
          password: test_password
        }

        # Should fail - Customer has no passphrase to verify against
        expect(last_response.status).to eq(401)

        # No password should be created
        expect(password_hash_exists?(account_id)).to be false
      end
    end
  end

  describe 'migration preserves password verification' do
    it 'argon2 hash verifies correctly after migration from bcrypt' do
      # Create Customer with bcrypt
      customer = create_redis_customer_with_bcrypt(
        email: test_email,
        password: test_password
      )

      # Create Rodauth account
      account_id = create_rodauth_account_without_password(
        email: test_email,
        external_id: customer.extid
      )

      # Perform migration via login
      json_post_with_csrf '/auth/login', {
        login: test_email,
        password: test_password
      }

      # Get the migrated hash
      migrated_hash = get_password_hash(account_id)
      expect(migrated_hash).not_to be_nil

      # Verify argon2 hash works directly
      expect(::Argon2::Password.verify_password(test_password, migrated_hash)).to be true
      expect(::Argon2::Password.verify_password('WrongPassword', migrated_hash)).to be false
    end
  end
end
