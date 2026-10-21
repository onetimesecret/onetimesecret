# apps/web/auth/spec/integration/full/already_logged_in_spec.rb
#
# frozen_string_literal: true

# A logged-in session is refused on the routes Rodauth serves to the logged
# out (`already_logged_in`, config/base.rb). Rodauth's own default is a no-op,
# under which a valid login could run signup again or redeem another account's
# email link; rodauth 2.47 warns at boot while it is unconfigured, and the
# router's active-session gate only diverts REJECTED sessions.
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/already_logged_in_spec.rb

require_relative '../../spec_helper'
require 'rack/test'

RSpec.describe 'already logged in (config/base.rb)', type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  let(:email) { unique_test_email('already-logged-in') }
  let(:other_email) { unique_test_email('already-logged-in-other') }
  let!(:account_id) { seed_account_with_password(email) }

  before do
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
    csrf_login(email)
  end

  after do
    [email, other_email].each { |address| Onetime::Customer.find_by_email(address)&.destroy! }
  end

  def expect_refused_as_already_logged_in
    expect(last_response.status).to eq(403), last_response.body
    expect(json_body).to eq('error' => 'Already logged in')
  end

  it 'refuses a second login with 403 and keeps the session signed in', :aggregate_failures do
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect_refused_as_already_logged_in

    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth/account.json'
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include('email' => email)
  end

  it 'refuses signup before any account is written' do
    csrf_json_post('/auth/create-account', login: other_email, password: AuthTestConstants::TEST_PASSWORD)
    expect_refused_as_already_logged_in
    expect(auth_db[:accounts].where(email: other_email).count).to eq(0)
  end

  it 'refuses a password reset request before any key is written' do
    csrf_json_post('/auth/reset-password-request', login: email)
    expect_refused_as_already_logged_in
    expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)
  end
end
