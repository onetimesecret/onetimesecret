# apps/web/auth/spec/spec_helper.rb
#
# frozen_string_literal: true

# Start code coverage before any application code loads (see .simplecov).
# Enabled only when COVERAGE=true.
require 'simplecov' if ENV['COVERAGE'] == 'true'

# Rodauth Feature Configuration Tests
#
# These tests verify that Rodauth features are correctly enabled/disabled
# based on ENV variables after the configuration refactoring.
#
# Run all auth config tests:
#   pnpm run test:rspec apps/web/auth/spec/
#
# Run specific feature tests:
#   pnpm run test:rspec apps/web/auth/spec/config/features/mfa_spec.rb

# =============================================================================
# EARLY WEBMOCK SETUP
# =============================================================================
# WebMock stubs BEFORE any requires that might trigger config loading or
# provider registration. The OmniAuth OIDC strategy fetches the discovery
# document during provider registration (boot time), so the placeholder
# issuer must be stubbed before the app boots.
#
# No OIDC env vars are injected here — all four SSO providers (OIDC, Entra,
# GitHub, Google) register via placeholder credentials when
# ORGS_SSO_ENABLED=true. The OmniAuthTenant hook injects real credentials
# at request time.
#
# AUTHENTICATION_MODE must be 'full' before requiring ../application.
# Without it, Auth::Database.connection returns nil and Rodauth's post_configure
# crashes calling db.database_type on nil.
ENV['AUTHENTICATION_MODE'] ||= 'full'

PLACEHOLDER_OIDC_ISSUER = 'https://placeholder.invalid'

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

WebMock.stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/openid-configuration")
  .to_return(
    status: 200,
    body: {
      issuer: PLACEHOLDER_OIDC_ISSUER,
      authorization_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/authorize",
      token_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/token",
      userinfo_endpoint: "#{PLACEHOLDER_OIDC_ISSUER}/userinfo",
      jwks_uri: "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json",
      response_types_supported: %w[code],
      subject_types_supported: %w[public],
      id_token_signing_alg_values_supported: %w[RS256],
      scopes_supported: %w[openid email profile],
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
      claims_supported: %w[sub email email_verified name],
      code_challenge_methods_supported: %w[S256],
    }.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

WebMock.stub_request(:get, "#{PLACEHOLDER_OIDC_ISSUER}/.well-known/jwks.json")
  .to_return(
    status: 200,
    body: { keys: [] }.to_json,
    headers: { 'Content-Type' => 'application/json' }
  )

require 'rspec'
require 'sequel'
require 'roda'
require 'rodauth'
require 'securerandom'
require 'rack/test'

# Load OmniAuth test helper for additional helper methods
require_relative 'support/omniauth_test_helper'
require_relative 'support/auth_test_constants'
require_relative 'support/mock_omniauth_strategy'
require_relative 'support/config_recreator'
require_relative '../database'

# =============================================================================
# PRE-LOAD AUTH APPLICATION (#3234)
# =============================================================================
# Force-load Auth::Application so the full constant chain
# (Onetime::Boot::Initializer, Auth::Config, Auth::Config::Features::*,
# Auth::Config::Hooks::*, the initializer subclasses) is defined before any
# example runs.
#
# Without this, unit specs that mock Onetime/Auth::Database in isolation pass
# fine on their own but fail when paired with an integration spec that boots
# the real app: the integration spec's `Onetime.boot!` is memoized
# process-wide, and the unit spec's stub of `Onetime.auth_config` leaks across
# example boundaries unless the namespace is stable up front.
#
# Safe to load eagerly here because Auth::Config's OAuth feature block only
# runs when `Onetime.auth_config.oauth_enabled?` returns true (config.rb:149),
# which requires AUTH_OAUTH_ENABLED=true in the environment. Integration specs
# that need OAuth set the env var BEFORE `require_relative '../spec_helper'`;
# unit specs leave it unset and the RSA-key requirement (features/oauth.rb:234)
# stays dormant.
#
# Reload Onetime.auth_config before requiring the application. The
# AuthConfig singleton was first instantiated during `require 'onetime'`
# (lib/onetime/initializers.rb:75, called from the root spec_helper) — at
# which point AUTHENTICATION_MODE was unset, so mode cached as 'simple'.
# Without a reload here, Auth::Database.connection returns nil (full-mode
# guard at database.rb:111), and rodauth's post_configure (base.rb:443)
# crashes calling db.database_type on nil. Mirrors the reload performed
# by ProductionConfigHelper#boot_onetime_app for integration specs.
Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)

# Only eagerly load the full auth application in full mode. The reload above has
# now picked up AUTHENTICATION_MODE from the environment; in simple mode (the
# unit/apps RSpec leg that also runs these config specs) full_enabled? is false
# and Auth::Database.connection is nil (database.rb:111), so configuring Rodauth
# via application.rb -> router.rb would crash post_configure on db.database_type
# (base.rb:443). Self-contained config specs that build their own in-memory app
# (e.g. mfa_provisioning_uri_spec.rb via create_test_database) don't need the
# real application booted. Integration specs always run in full mode, where this
# pre-load still happens and #3234's namespace-stability guarantee holds.
require_relative '../application' if Onetime.respond_to?(:auth_config) && Onetime.auth_config.full_enabled?

# =============================================================================
# TENANT VERIFYING MOCK REGISTRATION
# =============================================================================
#
# Register TenantVerifyingMock as an OmniAuth provider for integration tests.
#
# This module prepends Auth::Config::Features::OmniAuth to register our mock
# strategy alongside other OmniAuth providers. The registration happens during
# Rodauth's configure phase, ensuring the mock is included in the OmniAuth
# middleware stack built by post_configure.
#
# The TenantVerifyingMock strategy captures credentials injected via the setup
# proc during the request phase, enabling tests to verify:
#   - Tenant resolution from Host header
#   - Credential injection into strategy options
#   - Setup proc execution
#
# Routes created:
#   POST /auth/sso/tenant_verify (request phase)
#   GET  /auth/sso/tenant_verify/callback (callback phase)
#
# @see apps/web/auth/spec/support/mock_omniauth_strategy.rb
#
module TenantVerifyingMockRegistration
  def self.register_with_rodauth(auth)
    # Register TenantVerifyingMock strategy.
    # Uses the strategy class from OmniAuth::Strategies namespace.
    auth.omniauth_provider(
      :tenant_verifying_mock,
      name: :tenant_verify
    )
  end
end

# Helper module for creating isolated Rodauth test environments
module RodauthTestHelper
  include AuthTestConstants
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
    create_omniauth_tables(db)
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
    db[:account_statuses].import(
      [:id, :name],
      [[STATUS_UNVERIFIED, 'Unverified'], [STATUS_VERIFIED, 'Verified'], [STATUS_CLOSED, 'Closed']]
    )

    db.create_table(:accounts) do
      primary_key :id, type: :Bignum
      foreign_key :status_id, :account_statuses, null: false, default: STATUS_UNVERIFIED
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

  # Creates tables for OmniAuth (SSO identity linking)
  def self.create_omniauth_tables(db)
    db.create_table(:account_identities) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :provider, null: false
      String :uid, null: false
      index [:provider, :uid], unique: true
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

# Helper module for integration tests that need production config
#
# Integration tests require:
# - Valkey running on port 2121 (pnpm run test:database:start)
# - AUTH_DATABASE_URL set for SQLite auth database
#
# Tests using this helper should be tagged with `type: :integration`
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

  # Check if auth database is configured
  def auth_database_configured?
    !ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
  end

  # Boot the full Onetime application for integration tests
  # This is called once per test file in before(:all)
  def boot_onetime_app
    return if defined?(@@onetime_booted) && @@onetime_booted

    ENV['AUTHENTICATION_MODE'] ||= 'full'

    # Reset registries to clear state from previous test runs
    require 'onetime'

    # Config resolution is handled automatically by ConfigResolver when RACK_ENV=test
    require 'onetime/application/registry'
    require 'onetime/boot/initializer_registry'

    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    require 'onetime/auth_config'
    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)

    # Install TenantVerifyingMock registration hook BEFORE boot.
    # This prepends our registration method to the OmniAuth feature configure,
    # ensuring the mock strategy is included in Rodauth's OmniAuth middleware.
    install_tenant_verifying_mock_hook

    # Boot application
    Onetime.boot! :test unless Onetime.ready?

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry

    @@onetime_booted = true
  end

  # Install a hook to register TenantVerifyingMock during OmniAuth configuration.
  #
  # This prepends a module to Auth::Config::Features::OmniAuth.configure that
  # registers TenantVerifyingMock after other providers. The hook runs during
  # Rodauth's configure phase, before post_configure builds the middleware stack.
  #
  # @see TenantVerifyingMockRegistration
  def install_tenant_verifying_mock_hook
    # Only install once
    return if defined?(@@tenant_mock_hook_installed) && @@tenant_mock_hook_installed

    # features.rb uses the shorthand `module Auth::Config::Features`, which
    # requires Auth::Config to already be defined. In normal full-suite runs
    # an earlier spec (e.g. env_feature_loading_spec.rb) has populated the
    # namespace before this point. When this hook runs in isolation (a
    # single-file rspec invocation of an integration spec), Auth::Config is
    # still undefined — and the original `require_relative '../config/features'`
    # blew up with NameError. The TenantVerifyingMock is only used by tenant-SSO
    # specs; if the auth namespace isn't ready, skip cleanly so unrelated
    # integration specs can boot.
    unless defined?(Auth::Config)
      return
    end

    # Load the Auth features module structure
    require_relative '../config/features'

    # Check if OmniAuth feature exists
    return unless defined?(Auth::Config::Features::OmniAuth)

    # Prepend our registration hook
    original_configure = Auth::Config::Features::OmniAuth.method(:configure)

    Auth::Config::Features::OmniAuth.define_singleton_method(:configure) do |auth|
      # Call original configure first (registers OIDC, Entra, GitHub, Google)
      original_configure.call(auth)

      # Then register TenantVerifyingMock for testing
      TenantVerifyingMockRegistration.register_with_rodauth(auth)
    end

    @@tenant_mock_hook_installed = true
  end

  # Build the full Rack URL map (all mounted apps)
  def build_rack_app
    boot_onetime_app
    Onetime::Application::Registry.generate_rack_url_map
  end

  # Rack::Test app method - returns the full application stack
  def app
    @app ||= build_rack_app
  end

  # Helper method to send JSON requests
  def json_post(path, params)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post path, JSON.generate(params)
  end

  def json_get(path)
    # Clear headers that may have leaked from previous POST requests
    # GET requests shouldn't have Content-Type or body-related headers
    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get path
  end

  # Clean up test data in Valkey
  def flush_test_database
    return unless valkey_available?

    Familia.dbclient.flushdb
  rescue StandardError => e
    OT.le "[flush_test_database] Failed to flush test database: #{e.message}"
  end

  # Clean up SQL auth data between integration examples.
  #
  # The Valkey side is flushed every example, but Auth::Database.connection is
  # memoized for the whole process, so accounts accumulate and desync from the
  # flushed Redis customers (manifests as account_id climbing, then a JIT
  # re-create colliding on the unique email index in SyncSession).
  #
  # DELETE rows rather than reconnect: the in-memory SQLite schema lives in the
  # single shared connection, so disconnecting would drop the tables. Reset the
  # autoincrement counter so account_id restarts at 1 (deterministic IDs).
  #
  # For PostgreSQL in CI, the application connection (onetime_user) lacks TRUNCATE
  # privileges. Use AUTH_DATABASE_URL_MIGRATIONS (onetime_migrator) when available.
  def clear_auth_database
    db = Auth::Database.connection
    # Preserve schema bookkeeping and seed-once reference tables (PRESERVED_TABLES).
    tables = db.tables - AuthTestConstants::PRESERVED_TABLES
    return if tables.empty?

    case db.database_type
    when :postgres
      # Use elevated connection for TRUNCATE if available (CI privilege separation)
      # Prefer existing PostgresModeSuiteDatabase connection to avoid per-test connect overhead
      if defined?(PostgresModeSuiteDatabase) && PostgresModeSuiteDatabase.migration_database
        PostgresModeSuiteDatabase.migration_database.run("TRUNCATE #{tables.join(', ')} RESTART IDENTITY CASCADE")
      else
        migration_url = ENV['AUTH_DATABASE_URL_MIGRATIONS']
        if migration_url && !migration_url.to_s.empty? && migration_url != ENV['AUTH_DATABASE_URL']
          elevated_db = Sequel.connect(migration_url)
          begin
            elevated_db.run("TRUNCATE #{tables.join(', ')} RESTART IDENTITY CASCADE")
          ensure
            elevated_db.disconnect
          end
        else
          db.run("TRUNCATE #{tables.join(', ')} RESTART IDENTITY CASCADE")
        end
      end
    when :sqlite
      db.run('PRAGMA foreign_keys = OFF')
      tables.each { |t| db[t].delete }
      db[:sqlite_sequence].delete if db.table_exists?(:sqlite_sequence)
      db.run('PRAGMA foreign_keys = ON')
    end
  rescue StandardError => e
    OT.le "[clear_auth_database] Failed to clear auth database: #{e.message}"
  end

  # Get the auth database connection for assertions
  def auth_db
    Auth::Database.connection
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
  config.include ProductionConfigHelper, type: :integration

  # Capture AUTH_* env vars before integration suite to prevent leakage
  # between spec files that set different feature flags.
  # See: apps/web/auth/docs/auth-config-one-shot.md (Pattern 2)
  config.before(:all, type: :integration) do
    @saved_auth_env = Auth::ConfigRecreator.capture_auth_env
  end

  config.after(:all, type: :integration) do
    Auth::ConfigRecreator.restore_auth_env(@saved_auth_env) if @saved_auth_env
  end

  # Skip integration tests if Valkey not available
  config.before(:each, type: :integration) do
    unless valkey_available?
      skip 'Valkey not available on port 2121 (run: pnpm run test:database:start)'
    end
  end

  # Clean database before each integration test.
  #
  # Respect the same opt-outs as the top-level spec/spec_helper.rb flush:
  # specs that build fixtures in before(:all) and read them across examples
  # set shared_db_state: true; billing specs manage their own state. Without
  # this guard, requiring this helper in a shared rspec process (apps + core
  # integration specs run together since 7b9cd9202) flushes those specs'
  # before(:all) data out from under them.
  config.before(:each, type: :integration) do |example|
    next if example.metadata[:shared_db_state]
    next if example.metadata[:billing]

    flush_test_database if respond_to?(:flush_test_database)
  end

  # Clean database after each integration test (same opt-outs as above).
  config.after(:each, type: :integration) do |example|
    next if example.metadata[:shared_db_state]
    next if example.metadata[:billing]

    flush_test_database if respond_to?(:flush_test_database)
    clear_auth_database if respond_to?(:clear_auth_database)
  end

  # Restore the OmniAuth request-method global after every example.
  #
  # OmniAuth.config is process-global mutable state. Many specs set
  # allowed_request_methods = %i[get post] (to exercise GET callbacks) but
  # never reset it, so :get leaks into subsequent strategy inits and triggers
  # the CVE-2015-9284 GET-request CSRF warning mid-suite. Unguarded (no
  # shared_db_state/billing opt-out) so it always runs.
  config.after(:each) do
    next unless defined?(OmniAuth)

    OmniAuth.config.allowed_request_methods = [:post]
    OmniAuth.config.silence_get_warning = false
  end
end
