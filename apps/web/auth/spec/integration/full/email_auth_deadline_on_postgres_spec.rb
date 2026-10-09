# apps/web/auth/spec/integration/full/email_auth_deadline_on_postgres_spec.rb
#
# frozen_string_literal: true

# Magic-link deadline (#4689, RISK-2026-08-14-M02) on PostgreSQL.
#
# The deadline is written as a database expression; on PostgreSQL it compiles
# to `CAST(CURRENT_TIMESTAMP AS timestamp) + make_interval(mins := 15)`, which
# the SQLite copy (config/features/email_auth_deadline_spec.rb) cannot
# exercise. Same examples, from
# support/shared_examples/email_auth_deadline_examples.rb.
#
# Run: tests/lanes/run full-pg-agnostic --only apps/web/auth/spec/integration/full/email_auth_deadline_on_postgres_spec.rb

require_relative '../../spec_helper'
require_relative '../../support/shared_examples/email_auth_deadline_examples'

RSpec.describe 'Auth::Config::Features::EmailAuth deadline on PostgreSQL (#4689)',
  :postgres_database, type: :integration do
  # Loads Auth::Config, including Features::EmailAuth.
  before(:all) { boot_onetime_app }

  let(:db)         { test_db }
  let(:email)      { "magic-link-deadline-#{SecureRandom.hex(8)}@example.com" }
  let(:account_id) { create_verified_account(db: setup_db, email: email)[:id] }

  before { account_id }

  after do
    next unless PostgresModeSuiteDatabase.postgres_available?

    setup_db[:account_email_auth_keys].where(id: account_id).delete
  end

  include_examples 'a 15-minute magic link deadline'
end
