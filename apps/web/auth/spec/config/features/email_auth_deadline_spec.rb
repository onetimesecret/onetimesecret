# apps/web/auth/spec/config/features/email_auth_deadline_spec.rb
#
# frozen_string_literal: true

# Magic-link deadline (#4689, RISK-2026-08-14-M02) on SQLite.
#
# The examples live in support/shared_examples/email_auth_deadline_examples.rb;
# the PostgreSQL copy is
# integration/full/email_auth_deadline_on_postgres_spec.rb.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/config/features/email_auth_deadline_spec.rb

require_relative '../../spec_helper'
require 'familia'
require 'rodauth'

# Auth::Config MUST be a Rodauth::Auth subclass, never a plain module or class
# (see the preamble in unit/omniauth_tenant_helpers_spec.rb).
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Features, Module.new) unless Auth::Config.const_defined?(:Features, false)
Auth::Config.const_set(:Email, Module.new) unless Auth::Config.const_defined?(:Email, false)
require_relative '../../../config/email/email_auth'
require_relative '../../../config/features/email_auth'
require_relative '../../support/shared_examples/email_auth_deadline_examples'

RSpec.describe 'Auth::Config::Features::EmailAuth deadline on SQLite (#4689)' do
  let(:db)         { create_test_database }
  let(:email)      { 'magic-link-deadline@example.com' }
  let(:account_id) { db[:accounts].insert(email: email, status_id: AuthTestConstants::STATUS_VERIFIED) }

  before { account_id }

  include_examples 'a 15-minute magic link deadline'
end
