# apps/web/auth/spec/integration/full/already_logged_in_spec.rb
#
# frozen_string_literal: true

# A signed-in session is refused on the routes Rodauth serves to the logged
# out (`already_logged_in`, config/base.rb). Rodauth's own default is a no-op,
# under which a valid login could run signup again or redeem another account's
# email link; rodauth 2.47 warns at boot while it is unconfigured, and the
# router's active-session gate only diverts REJECTED sessions.
#
# "Signed in" is the app's `authenticated` flag, not Rodauth's account_id
# alone: the verify-account autologin session has the id and not the flag and
# must still log in (verify_account_autologin_session_rotation_spec.rb). The
# reset-password request and redemption stay open to a signed-in session
# because the account settings page uses them (ResetPassword.vue).
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/already_logged_in_spec.rb

require_relative '../../spec_helper'
require 'rack/test'
require 'cgi'

RSpec.describe 'already logged in (config/base.rb)', type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  let(:email) { unique_test_email('already-logged-in') }
  let(:other_email) { unique_test_email('already-logged-in-other') }
  let!(:account_id) { seed_account_with_password(email) }

  before do
    # The delivery seam: each rendered email, as the publisher would receive it.
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |mail, **_kwargs|
      @delivered << mail
      true
    end
    csrf_login(email)
  end

  after do
    [email, other_email].each { |address| Onetime::Customer.find_by_email(address)&.destroy! }
  end

  def expect_refused_as_already_logged_in
    expect(last_response.status).to eq(403), last_response.body
    expect(json_body).to eq('error' => 'Already logged in')
  end

  # The key from the delivered reset-password email. The link path is the
  # SPA's `/reset-password`, not `/auth/reset-password`
  # (public_host_email_link_spec.rb).
  def delivered_reset_key
    link = @delivered.filter_map { |mail| mail[:body].to_s[%r{https?://\S+?/reset-password\?key=\S+}] }.first
    expect(link).not_to be_nil, "no /reset-password link among #{@delivered.size} delivered email(s)"
    CGI.parse(URI.parse(link).query).fetch('key').first
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

  it 'lets the signed-in session request and redeem a password reset (the settings page)', :aggregate_failures do
    csrf_json_post('/auth/reset-password-request', login: email)
    expect(last_response.status).to eq(200), last_response.body
    expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(1)

    new_password = "#{AuthTestConstants::TEST_PASSWORD}-reset"
    csrf_json_post('/auth/reset-password', key: delivered_reset_key, password: new_password, 'password-confirm': new_password)
    expect(last_response.status).to eq(200), last_response.body
    expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)
  end
end
