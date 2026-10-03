# apps/web/auth/spec/config/features/account_management_spec.rb
#
# frozen_string_literal: true

# next_action and the success text in the create-account JSON response,
# with the verify_account feature LOADED.
#
# The integration lanes only see the verification-off answer:
# etc/defaults/auth.defaults.yaml turns verify_account off under
# RACK_ENV=test, so 'verify_email' and verify_account's email-sent notice
# are unreachable there. This builds a Rodauth app with the feature on and
# applies the production response block.
#
# Reference: apps/web/auth/config/features/account_management.rb

require_relative '../../spec_helper'

# Namespace shim (the pattern of
# spec/config/overrides/account_enumeration_duplicate_signup_spec.rb): the
# feature file reopens Auth::Config without booting the app.
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)

require_relative '../../../config/features/account_management'

RSpec.describe Auth::Config::Features::AccountManagement, '.configure_create_account_response' do
  include Rack::Test::Methods

  let(:db) { create_test_database }
  let(:password) { 'Next-Action1234!xyz' }
  let(:email_sent_notice) { 'An email has been sent to you with a link to verify your account' }
  let(:created_notice) { 'Your account has been created' }

  # opens_account stands in for the invite signup, whose after_create_account
  # opens the account (config/hooks/account.rb). No signup is logged in, as in
  # production (config/features/account_management.rb).
  def build_app(extra_features:, opens_account: false)
    app = create_rodauth_app(db: db, features: [:base, :json, :create_account, *extra_features]) do
      only_json? true
      require_login_confirmation? false
      require_password_confirmation? false
      create_account_autologin? false

      if extra_features.include?(:verify_account)
        verify_account_set_password? false
        send_verify_account_email { nil }
      end

      if opens_account
        after_create_account { update_account(account_status_column => account_open_status_value) }
      end

      Auth::Config::Features::AccountManagement.configure_create_account_response(self)
    end
    app.plugin :json_parser # the helper app has no body parser
    app
  end

  def sign_up(email)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post '/create-account', JSON.generate(login: email, password: password)
    [last_response.status, JSON.parse(last_response.body)]
  end

  def status_id_for(email)
    db[:accounts].where(email: email).get(:status_id)
  end

  context 'with verify_account loaded' do
    let(:app) { build_app(extra_features: [:verify_account]) }

    it 'answers verify_email and the email-sent notice for a new account, which starts unverified', :aggregate_failures do
      status, body = sign_up('new@example.com')

      expect(status).to eq(200), body.inspect
      expect(body).to include('success' => email_sent_notice, 'next_action' => 'verify_email')
      expect(status_id_for('new@example.com')).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    end
  end

  context 'with verify_account loaded and the account opened at signup (the invite shape)' do
    let(:app) { build_app(extra_features: [:verify_account], opens_account: true) }

    # No email goes out for this account, so the notice must not say one did.
    it 'answers sign_in and the account-created notice, not verify_email', :aggregate_failures do
      status, body = sign_up('invitee@example.com')

      expect(status).to eq(200), body.inspect
      expect(body).to include('success' => created_notice, 'next_action' => 'sign_in')
      expect(status_id_for('invitee@example.com')).to eq(AuthTestConstants::STATUS_VERIFIED)
    end
  end

  context 'without verify_account' do
    let(:app) { build_app(extra_features: []) }

    it 'answers sign_in and the account-created notice (Rodauth default)', :aggregate_failures do
      status, body = sign_up('open@example.com')

      expect(status).to eq(200), body.inspect
      expect(body).to include('success' => created_notice, 'next_action' => 'sign_in')
    end
  end
end
