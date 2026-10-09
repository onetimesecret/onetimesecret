# apps/web/auth/spec/config/features/email_auth_deadline_spec.rb
#
# frozen_string_literal: true

# Magic-link deadline (#4689, RISK-2026-08-14-M02).
#
# Rodauth writes a key's deadline only when set_deadline_values? is true,
# which by default is MySQL only. On PostgreSQL and SQLite the 24-hour
# column default applied, not the configured email_auth_deadline_interval.
# Auth::Config::Features::EmailAuth now writes the deadline itself, for the
# email_auth table only. These examples load that real configure method and
# pin:
#
# - the stored deadline is issue time + 15 minutes
# - the link is refused once 15 minutes have passed
# - a resend inside the window reuses the key and keeps its deadline
#
# Rodauth checks the deadline against the database clock
# (`CURRENT_TIMESTAMP > deadline`), which Timecop cannot move. Elapsed time is
# simulated the same way the active-sessions specs do it: shift the row's
# timestamps back with Sequel.date_sub.
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

RSpec.describe 'Auth::Config::Features::EmailAuth deadline (#4689)' do
  let(:db) { create_test_database }

  let(:app) do
    create_rodauth_app(db: db, features: [:base, :login, :logout]) do
      Auth::Config::Features::EmailAuth.configure(self)
    end
  end

  let(:email)      { 'magic-link-deadline@example.com' }
  let(:account_id) { db[:accounts].insert(email: email, status_id: AuthTestConstants::STATUS_VERIFIED) }
  let(:keys)       { db[:account_email_auth_keys].where(id: account_id) }

  let(:fifteen_minutes) { 15 * 60 }

  def new_rodauth
    env     = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/',
      'rack.input' => StringIO.new,
      'rack.session' => {},
    }
    request = Roda::RodaRequest.new(app.new(env), env)
    app.rodauth.new(request.scope)
  end

  # The key-handling half of Rodauth's _email_auth_request (generate a value,
  # then create_email_auth_key), without composing the email. Returns the
  # token the email would carry.
  def request_link
    rodauth = new_rodauth
    rodauth.account_from_login(email)
    rodauth.send(:generate_email_auth_key_value)
    rodauth.create_email_auth_key
    rodauth.send(:token_param_value, rodauth.send(:email_auth_key_value))
  end

  def link_valid?(token)
    !new_rodauth.account_from_email_auth_key(token).nil?
  end

  # Move the row's timestamps back, as if `seconds` had passed since it was
  # written.
  def age_row(seconds)
    keys.update(
      deadline: Sequel.date_sub(:deadline, seconds: seconds),
      email_last_sent: Sequel.date_sub(:email_last_sent, seconds: seconds),
    )
  end

  before { account_id }

  it 'leaves the Rodauth-wide set_deadline_values? off (scoped to email_auth)' do
    expect(new_rodauth.send(:set_deadline_values?)).to be false
  end

  it 'writes the deadline as issue time + 15 minutes', :aggregate_failures do
    request_link
    row = keys.first

    expect(row[:deadline] - row[:email_last_sent]).to be_within(1).of(fifteen_minutes)
    expect(row[:deadline]).to be_within(5).of(Time.now + fifteen_minutes)
  end

  it 'accepts the link just inside 15 minutes' do
    token = request_link
    age_row(fifteen_minutes - 5)

    expect(link_valid?(token)).to be true
  end

  it 'refuses the link once 15 minutes have passed and removes the row', :aggregate_failures do
    token = request_link
    age_row(fifteen_minutes + 1)

    expect(link_valid?(token)).to be false
    expect(keys.count).to eq(0)
  end

  describe 'resend inside the window' do
    it 'reuses the key and keeps the original deadline', :aggregate_failures do
      token = request_link
      # Past email_auth_skip_resend_email_within (30s), inside the deadline.
      age_row(10 * 60)
      original = keys.first

      resent_token = request_link
      row          = keys.first

      expect(keys.count).to eq(1)
      expect(resent_token).to eq(token)
      expect(row[:key]).to eq(original[:key])
      expect(row[:deadline]).to eq(original[:deadline])
      expect(row[:email_last_sent]).to be > original[:email_last_sent]
    end

    it 'does not extend the link past 15 minutes from the first issue' do
      token = request_link
      age_row(10 * 60)
      request_link
      # Five more minutes pass (15 since the first issue). Only the deadline
      # decides validity, so only it is moved.
      keys.update(deadline: Sequel.date_sub(:deadline, seconds: (5 * 60) + 1))

      expect(link_valid?(token)).to be false
    end
  end

  it 'issues a fresh key with a fresh deadline after the old one expired', :aggregate_failures do
    token = request_link
    age_row(fifteen_minutes + 1)

    new_token = request_link
    row       = keys.first

    expect(keys.count).to eq(1)
    expect(new_token).not_to eq(token)
    expect(row[:deadline]).to be_within(5).of(Time.now + fifteen_minutes)
    expect(link_valid?(token)).to be false
    expect(link_valid?(new_token)).to be true
  end
end
