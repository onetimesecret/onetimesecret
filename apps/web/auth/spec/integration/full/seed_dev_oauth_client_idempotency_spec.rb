# apps/web/auth/spec/integration/full/seed_dev_oauth_client_idempotency_spec.rb
#
# frozen_string_literal: true

# Proves the dev SP seed initializer is idempotent: running it twice leaves
# exactly one row with client_id="onetimesecret-sp-dev".
#
# Issue #3104, task 6.
#
# Uses the auth spec_helper (not the root one) so Auth::Application — and
# transitively Onetime::Boot::Initializer that SeedDevOAuthClient subclasses
# — is loaded before the example runs. See spec_helper #3234 note for why
# pre-loading matters when this file runs alongside integration specs.

# Pre-boot env: ensure AUTH_OAUTH_ENABLED is set BEFORE spec_helper triggers
# the Auth::Config.configure block. Without this, when this unit spec runs
# before any OAuth integration spec in the same rspec invocation, Auth::Config
# evaluates `oauth_enabled?` as false at class-configure time and skips
# `Features::OAuth.configure(self)`. The one-shot @configured guard at
# config.rb:166 then prevents re-configuration after the integration spec
# sets AUTH_OAUTH_ENABLED=true and reloads auth_config — causing
# NoMethodError: undefined method `load_openid_configuration_route` in the
# integration examples. Mirrors the pre-boot env block in the oauth_idp_*
# integration specs (see oauth_idp_protocol_spec.rb:66 and siblings).
#
# Setting it here is safe for this file's examples: the `before` block stubs
# `Onetime.auth_config.oauth_enabled?` per-example anyway, so the seeder
# logic is exercised under controlled conditions independent of the env var.
ENV['AUTH_OAUTH_ENABLED'] ||= 'true'
# OAUTH_JWT_RSA_PRIVATE_KEY is required when AUTH_OAUTH_ENABLED=true (the
# OAuth feature raises at configure time without it — see
# config/features/oauth.rb). Generate a throwaway key for this unit spec;
# the key is never used at runtime because no examples exercise the
# OAuth endpoints. Mirrors the integration-spec pre-boot env block.
require 'openssl'
ENV['OAUTH_JWT_RSA_PRIVATE_KEY'] ||= OpenSSL::PKey::RSA.new(2048).to_pem

# Same reasoning as AUTH_OAUTH_ENABLED above: when this unit spec runs
# before an OAuth integration spec, Auth::Config's OmniAuth feature is
# configured at class-load time. If OAUTH_SP_DEV_CLIENT_SECRET is unset at
# that moment, `configure_local_idp_provider` skips the :local provider
# registration (see config/features/omniauth.rb:184). The @configured guard
# then prevents the integration spec from re-registering it after setting
# the env var. Seed a placeholder here so the local provider gets registered
# before the integration spec overwrites it with its own value.
require 'securerandom'
ENV['OAUTH_SP_DEV_CLIENT_SECRET'] ||= "unit-spec-placeholder-#{SecureRandom.hex(8)}"

require_relative '../../spec_helper'

require 'sequel'
require 'bcrypt'
require 'auth/database'
require 'auth/initializers/seed_dev_oauth_client'

RSpec.describe Auth::Initializers::SeedDevOAuthClient, type: :unit do
  let(:db) { Sequel.sqlite }

  # Capture the file-load values (set at the top of this file) so the per-example
  # mutations don't leak into subsequent specs that read them via ENV.fetch.
  #
  # OAUTH_SP_DEV_CLIENT_SECRET: without restore, when this spec runs in the same
  # rspec invocation as oauth_idp_*_spec.rb, the `after` ENV.delete leaves the
  # var unset and the integration `let(:client_secret) { ENV.fetch(...) }` raises
  # KeyError.
  #
  # AUTH_OAUTH_ENABLED: the file-load `||= 'true'` (line 29) combined with
  # Auth::Config's @configured one-shot guard (config.rb:166) means once OAuth
  # is configured in this process, it stays configured. Restoring the original
  # value bounds the env-var leak to this file's lifetime — the @configured
  # guard's effect on other specs is a separate, deferred structural issue.
  #
  # OAUTH_JWT_RSA_PRIVATE_KEY: also `||=` set at file load. Restore for symmetry
  # so a downstream spec that intentionally runs without a key (e.g. to assert
  # the configure-time raise) isn't silently handed our throwaway key.
  before(:all) do
    @original_oauth_sp_dev_client_secret = ENV['OAUTH_SP_DEV_CLIENT_SECRET']
    @original_auth_oauth_enabled         = ENV['AUTH_OAUTH_ENABLED']
    @original_oauth_jwt_rsa_private_key  = ENV['OAUTH_JWT_RSA_PRIVATE_KEY']
  end

  after(:all) do
    restore_env('OAUTH_SP_DEV_CLIENT_SECRET', @original_oauth_sp_dev_client_secret)
    restore_env('AUTH_OAUTH_ENABLED',         @original_auth_oauth_enabled)
    restore_env('OAUTH_JWT_RSA_PRIVATE_KEY',  @original_oauth_jwt_rsa_private_key)
  end

  def restore_env(name, original)
    if original.nil?
      ENV.delete(name)
    else
      ENV[name] = original
    end
  end

  before do
    db.create_table(:oauth_applications) do
      primary_key :id, type: :Bignum
      Bignum :account_id, null: true
      String :name, null: false
      String :description, text: true, null: true
      String :redirect_uri, text: true, null: false
      String :client_id, null: false
      String :client_secret, null: false
      String :scopes, text: true, null: false
      String :subject_type, null: true
      String :id_token_signed_response_alg, null: true
      String :token_endpoint_auth_method, null: true
      String :grant_types, text: true, null: true
      String :response_types, text: true, null: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :client_id, unique: true
    end

    # Make the initializer pick up our in-memory DB and treat the env as dev.
    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(Onetime).to receive(:development?).and_return(true)
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
    allow(Onetime.auth_config).to receive(:oauth_enabled?).and_return(true)

    # Suppress the chatty logger
    allow(Onetime).to receive(:auth_logger).and_return(Logger.new(IO::NULL))

    ENV['OAUTH_SP_DEV_CLIENT_SECRET'] = 'idempotency-spec-secret'
  end

  after { ENV.delete('OAUTH_SP_DEV_CLIENT_SECRET') }

  it 'inserts exactly one row when run twice' do
    initializer = described_class.new
    initializer.run({})
    initializer2 = described_class.new
    initializer2.run({})

    rows = db[:oauth_applications].where(client_id: 'onetimesecret-sp-dev').all
    expect(rows.length).to eq(1)
  end

  it 'reconciles scopes and grant_types on a stale pre-existing row' do
    # Simulate a dev DB seeded before offline_access / refresh_token landed.
    # A plain skip-if-exists seeder would leave these stale, silently breaking
    # refresh-token issuance (the per-application scope intersection strips
    # offline_access). The seeder reconciles them on the next boot instead.
    stale_secret_hash = BCrypt::Password.create('idempotency-spec-secret')
    db[:oauth_applications].insert(
      name: 'OneTimeSecret SP (development)',
      redirect_uri: 'http://localhost:3000/auth/sso/local/callback',
      client_id: 'onetimesecret-sp-dev',
      client_secret: stale_secret_hash,
      scopes: 'openid email profile',
      grant_types: 'authorization_code',
    )

    described_class.new.run({})

    rows = db[:oauth_applications].where(client_id: 'onetimesecret-sp-dev').all
    expect(rows.length).to eq(1)
    row = rows.first
    expect(row[:scopes].split).to include('offline_access')
    expect(row[:grant_types].split).to include('refresh_token')
    # Reconcile is targeted: it must not disturb the existing secret hash
    # (BCrypt::Password.create re-salts, so a re-insert would change this).
    expect(row[:client_secret]).to eq(stale_secret_hash)
  end

  it 'stores a bcrypt-hashed secret that matches the plaintext' do
    described_class.new.run({})
    row = db[:oauth_applications].where(client_id: 'onetimesecret-sp-dev').first
    expect(BCrypt::Password.new(row[:client_secret])).to eq('idempotency-spec-secret')
  end

  it 'skips in production' do
    allow(Onetime).to receive(:development?).and_return(false)
    allow(Onetime).to receive(:testing?).and_return(false)
    initializer = described_class.new
    expect(initializer.should_skip?).to be(true)
  end

  it 'signals skip via should_skip? when OAUTH_SP_DEV_CLIENT_SECRET is missing' do
    ENV.delete('OAUTH_SP_DEV_CLIENT_SECRET')
    initializer = described_class.new
    expect(initializer.should_skip?).to be(true)
    expect(db[:oauth_applications].count).to eq(0)
  end
end
