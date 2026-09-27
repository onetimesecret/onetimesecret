# apps/web/auth/spec/config/overrides/account_enumeration_duplicate_signup_spec.rb
#
# frozen_string_literal: true

# The one answer for a sign-up whose login already has an account (audit
# 2026-08-02 M-2), with the verify_account feature ENABLED.
#
# The integration lanes cannot show this: etc/defaults/auth.defaults.yaml turns
# verify_account off under RACK_ENV=test, so the branch where stock
# verify_account answers 403 for an unverified account is unreachable there.
# This builds a Rodauth app with the feature on and the production override
# applied. With no before_create_account hook in this app, every duplicate
# reaches the INSERT, so it also exercises the save_account race cover.
#
# Reference: apps/web/auth/config/overrides/account_enumeration.rb

require_relative '../../spec_helper'

# Namespace shim (the pattern of spec/config/hooks/*_spec.rb): the override
# file reopens Auth::Config without booting the app.
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)

require_relative '../../../lib/logging' # save_account logs the lost race
require_relative '../../../config/overrides/account_enumeration'

RSpec.describe Auth::Config::Overrides::AccountEnumeration, 'duplicate sign-up answer' do
  include Rack::Test::Methods

  let(:db) { create_test_database }
  let(:password) { 'Dup-Signup1234!xyz' }

  def build_app(with_override:)
    create_rodauth_app(db: db, features: [:base, :json, :create_account, :verify_account]) do
      only_json? true
      require_login_confirmation? false
      verify_account_set_password? false
      send_verify_account_email { nil }
      create_account_error_flash 'Unable to create account'
      attempt_to_create_unverified_account_error_flash 'Unable to create account'
      Auth::Config::Overrides::AccountEnumeration.configure(self) if with_override
    end.tap { |klass| klass.plugin :json_parser } # the helper app has no body parser
  end

  let(:app) { build_app(with_override: true) }

  def sign_up(email)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post '/create-account', JSON.generate(login: email, password: password, 'password-confirm' => password)
    { status: last_response.status, body: JSON.parse(last_response.body) }
  end

  def seed(email, status_id)
    db[:accounts].insert(email: email, status_id: status_id)
  end

  it 'answers an unverified and a verified existing account exactly like a fresh sign-up', :aggregate_failures do
    seed('unverified@example.com', 1)
    seed('verified@example.com', 2)

    fresh      = sign_up('fresh@example.com')
    unverified = sign_up('unverified@example.com')
    verified   = sign_up('verified@example.com')

    expect(fresh).to include(status: 200), fresh.inspect
    expect(unverified).to eq(fresh)
    expect(verified).to eq(fresh)
    expect(unverified[:body].to_s).not_to match(/unverified|already|resend|field-error/i)
    expect(db[:accounts].where(email: 'unverified@example.com').count).to eq(1)
    expect(db[:accounts].where(email: 'verified@example.com').count).to eq(1)
  end

  it 'still creates an account for a new login' do
    answer = sign_up('fresh@example.com')
    expect(answer).to include(status: 200), answer.inspect
    expect(db[:accounts].where(email: 'fresh@example.com').count).to eq(1)
  end

  # Non-vacuous: without the override, stock verify_account tells the two apart.
  context 'without the override' do
    let(:app) { build_app(with_override: false) }

    it 'answers 403 for an unverified account (the difference the override removes)' do
      seed('unverified@example.com', 1)
      expect(sign_up('unverified@example.com')[:status]).to eq(403)
    end
  end
end
