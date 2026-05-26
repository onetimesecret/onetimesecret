# apps/web/auth/spec/unit/seed_dev_oauth_client_idempotency_spec.rb
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

require_relative '../spec_helper'

require 'sequel'
require 'bcrypt'
require 'auth/database'
require 'auth/initializers/seed_dev_oauth_client'

RSpec.describe Auth::Initializers::SeedDevOAuthClient, type: :unit do
  let(:db) { Sequel.sqlite }

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
