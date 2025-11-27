# apps/web/auth/spec/spec_helper.rb
#
# frozen_string_literal: true

# Rodauth Feature Configuration Tests
#
# These tests verify that Rodauth features are correctly enabled/disabled
# based on ENV variables after the configuration refactoring.
#
# Run all auth config tests:
#   bundle exec rspec apps/web/auth/spec/
#
# Run specific feature tests:
#   bundle exec rspec apps/web/auth/spec/config/features/mfa_spec.rb

require 'rspec'
require 'sequel'
require 'roda'
require 'rodauth'
require 'securerandom'

# Helper module for creating isolated Rodauth test environments
module RodauthTestHelper
  # Creates a fresh SQLite in-memory database with all Rodauth tables
  #
  # @return [Sequel::Database] configured database connection
  def self.create_test_database
    db = Sequel.sqlite # In-memory SQLite
    db.extension :date_arithmetic

    create_core_tables(db)
    create_security_tables(db)
    create_mfa_tables(db)
    create_email_auth_tables(db)
    create_webauthn_tables(db)
    create_audit_tables(db)
    create_password_tables(db)

    db
  end

  # Creates account-related tables
  def self.create_core_tables(db)
    db.create_table(:account_statuses) do
      Integer :id, primary_key: true
      String :name, null: false, unique: true
    end
    db[:account_statuses].import([:id, :name], [[1, 'Unverified'], [2, 'Verified'], [3, 'Closed']])

    db.create_table(:accounts) do
      primary_key :id, type: :Bignum
      foreign_key :status_id, :account_statuses, null: false, default: 1
      String :email, null: false
      String :external_id, null: true, unique: true
      index :email, unique: true
    end

    db.create_table(:account_password_hashes) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :password_hash, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    db.create_table(:account_verification_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  # Creates tables for security features (lockout, active_sessions, remember)
  def self.create_security_tables(db)
    db.create_table(:account_login_failures) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      Integer :number, null: false, default: 1
    end

    db.create_table(:account_lockouts) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent
    end

    db.create_table(:account_active_session_keys) do
      foreign_key :account_id, :accounts, type: :Bignum
      String :session_id
      Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
      primary_key [:account_id, :session_id]
    end

    db.create_table(:account_remember_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
    end
  end

  # Creates tables for MFA features (OTP, recovery codes)
  def self.create_mfa_tables(db)
    db.create_table(:account_otp_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      Integer :num_failures, null: false, default: 0
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    db.create_table(:account_recovery_codes) do
      foreign_key :id, :accounts, type: :Bignum
      String :code
      primary_key [:id, :code]
    end

    db.create_table(:account_otp_unlocks) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      Integer :num_successes, null: false, default: 1
      Time :next_auth_attempt_after, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  # Creates tables for email auth (magic links)
  def self.create_email_auth_tables(db)
    db.create_table(:account_email_auth_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  # Creates tables for WebAuthn
  def self.create_webauthn_tables(db)
    db.create_table(:account_webauthn_user_ids) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :webauthn_id, null: false
    end

    db.create_table(:account_webauthn_keys) do
      foreign_key :account_id, :accounts, type: :Bignum
      String :webauthn_id
      String :public_key, null: false
      Integer :sign_count, null: false
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
      primary_key [:account_id, :webauthn_id]
    end
  end

  # Creates tables for audit logging
  def self.create_audit_tables(db)
    db.create_table(:account_authentication_audit_logs) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum
      DateTime :at, null: false, default: Sequel::CURRENT_TIMESTAMP
      String :message, null: false
      String :metadata # JSON stored as text in SQLite
    end
  end

  # Creates tables for password management
  def self.create_password_tables(db)
    db.create_table(:account_password_reset_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    db.create_table(:account_password_change_times) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      DateTime :changed_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  # Creates a minimal Roda app with Rodauth configured
  #
  # @param db [Sequel::Database] database connection
  # @param features [Array<Symbol>] Rodauth features to enable
  # @param config_block [Proc] additional Rodauth configuration
  # @return [Class] Roda application class
  def self.create_rodauth_app(db:, features: [:base, :login, :logout], &config_block)
    app_db = db
    app_features = features
    app_config_block = config_block

    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :halt

      plugin :rodauth do
        db app_db

        # Enable requested features
        enable(*app_features)

        # Login column
        login_column :email

        # HMAC secret (required for OTP features)
        hmac_secret SecureRandom.hex(32)

        # Apply custom configuration if provided
        instance_eval(&app_config_block) if app_config_block
      end

      route do |r|
        r.rodauth

        r.root do
          { status: 'ok' }
        end
      end
    end
  end

  # Checks if a Rodauth method exists (verifies feature is enabled)
  #
  # @param app [Class] Roda application class
  # @param method_name [Symbol] method to check
  # @return [Boolean] true if method exists
  def self.rodauth_responds_to?(app, method_name)
    rodauth_class = app.rodauth
    rodauth_class.method_defined?(method_name) ||
      rodauth_class.private_method_defined?(method_name)
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # Use default expectations configuration
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  # Helper methods available in all tests
  config.include Module.new {
    def create_test_database
      RodauthTestHelper.create_test_database
    end

    def create_rodauth_app(db:, features: [:base, :login, :logout], &block)
      RodauthTestHelper.create_rodauth_app(db: db, features: features, &block)
    end

    def rodauth_responds_to?(app, method_name)
      RodauthTestHelper.rodauth_responds_to?(app, method_name)
    end
  }

  # Integration test helpers (for tests requiring full app boot)
  config.include Rack::Test::Methods, type: :integration

  # Skip integration tests if Valkey not available
  config.before(:each, type: :integration) do
    unless valkey_available?
      skip 'Valkey not available on port 2121 (run: pnpm run test:database:start)'
    end
  end
end

# Helper module for integration tests that need production config
module ProductionConfigHelper
  # Check if Valkey is available on test port
  def valkey_available?
    return @valkey_available if defined?(@valkey_available)

    @valkey_available = begin
      require 'redis'
      redis = Redis.new(url: 'redis://127.0.0.1:2121/0')
      redis.ping == 'PONG'
    rescue StandardError
      false
    end
  end

  # Boot the full Onetime application for integration tests
  def boot_onetime_app
    return if defined?(@onetime_booted) && @onetime_booted

    ENV['VALKEY_URL'] ||= 'valkey://127.0.0.1:2121/0'
    ENV['AUTHENTICATION_MODE'] ||= 'advanced'

    require 'onetime'
    Onetime.boot! :app unless Onetime.ready?
    @onetime_booted = true
  end

  # Build the Auth::Application for Rack::Test
  def build_auth_app
    boot_onetime_app
    require_relative '../application'
    Auth::Application.new.to_app
  end

  # Rack::Test app method
  def app
    @app ||= build_auth_app
  end
end
