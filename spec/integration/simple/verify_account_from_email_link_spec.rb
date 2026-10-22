# spec/integration/simple/verify_account_from_email_link_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — verifying a simple-mode account from the emailed
#            link, as a visitor with no customer (#4831)
# =============================================================================
#
# Simple-mode signup leaves the account unverified and emails a verification
# secret (Logic::Base#send_verification_email). Revealing that secret verifies
# the account. The visitor who opens the link usually has no customer at all:
# on auth=noauth routes the strategy resolves an anonymous caller to nil
# (#2733/#3516). #4831 was V2 RevealSecret refusing exactly that caller with a
# 422 ("Cannot verify when logged in").
#
# Three logic classes can reveal a verification secret, behind five anonymous
# routes. The browser E2E (e2e/auth/simple-mode-email-verification.spec.ts)
# drives only the SPA's route; this file drives each logic class through the
# real router, strategy and session middleware:
#
#   POST /api/v3/guest/secret/:id/reveal    V2 RevealSecret (the SPA's route)
#   POST /api/v2/secret/:id/reveal          V2 RevealSecret, basicauth,noauth
#   GET  /api/v3/guest/secret/:id?continue  V2 ShowSecret#verify_owner
#   GET  /api/v2/secret/:id?continue        V2 ShowSecret, basicauth,noauth
#   POST /api/v1/secret/:key                V1 ShowSecret
#
# The two RevealSecret examples fail against the code before #4832.
#
# This file MUST live in spec/integration/simple/: only simple-mode signup
# emails a verification secret. The suite config has autoverify: false
# (spec/config.test.yaml), which these examples require.
#
# RUN:
#   tests/lanes/run simple --only spec/integration/simple/verify_account_from_email_link_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'Verify a simple-mode account from the emailed link without a customer (#4831)', type: :integration do
  include Rack::Test::Methods

  def app
    # Memoize: repeated generate_rack_url_map calls corrupt middleware state.
    @app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/application/registry'

    app
  end

  before do
    skip 'requires simple auth mode' if Onetime.auth_config.full_enabled?

    autoverify = OT.conf.dig('site', 'authentication', 'autoverify')
    raise "Test precondition broken: autoverify must be false in spec/config.test.yaml, got #{autoverify.inspect}" if autoverify.to_s == 'true'

    # send_verification_email delivers synchronously through the Mailer; stub
    # the seam so no SMTP is attempted. The secret it would carry is still
    # created and bound to the customer as reset_secret.
    allow(Onetime::Mail::Mailer).to receive(:deliver).and_return(true)

    @created_emails = []
  end

  after do
    Array(@created_emails).each do |email|
      Onetime::Customer.find_by_email(email)&.destroy!
    rescue StandardError => ex
      warn "[verify-from-link spec] customer cleanup failed: #{ex.message}"
    end
  end

  # A fresh anonymous session, as the SPA has after loading the link: a session
  # cookie and a CSRF token, no customer. Returns the token.
  def anonymous_visit
    clear_cookies
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get '/'
    token = last_response.headers['X-CSRF-Token']
    raise "CSRF setup failed: GET / returned #{last_response.status} with no X-CSRF-Token header" if token.to_s.empty?

    token
  end

  # Signs up through the simple-mode Core route and returns the customer with
  # the verification secret the welcome email would carry.
  def sign_up
    email = "verify-link-#{SecureRandom.hex(8)}@integration-test.example.com"
    @created_emails << email

    token = anonymous_visit
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    post '/auth/create-account',
      JSON.generate(login: email, password: 'integration-test-pw', skill: '', shrimp: token)
    expect(last_response.status).to eq(200), "signup failed: #{last_response.status} #{last_response.body}"

    cust      = Onetime::Customer.find_by_email(email)
    expect(cust.verified?).to be(false)
    secret_id = cust.reset_secret.value
    expect(secret_id).not_to be_nil, 'signup must bind a verification secret'
    [cust, secret_id]
  end

  def json_post(path, token, body = {})
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    post path, JSON.generate(body)
  end

  {
    'POST /api/v3/guest/secret/:id/reveal' => ->(id, token) {
      json_post("/api/v3/guest/secret/#{id}/reveal", token, continue: true)
    },
    'POST /api/v2/secret/:id/reveal' => ->(id, token) {
      json_post("/api/v2/secret/#{id}/reveal", token, continue: true)
    },
    'GET /api/v3/guest/secret/:id?continue=true' => ->(id, _token) {
      get "/api/v3/guest/secret/#{id}", continue: 'true'
    },
    'GET /api/v2/secret/:id?continue=true' => ->(id, _token) {
      get "/api/v2/secret/#{id}", continue: 'true'
    },
    'POST /api/v1/secret/:key' => ->(id, token) {
      header 'Content-Type', 'application/x-www-form-urlencoded'
      header 'X-CSRF-Token', token
      post "/api/v1/secret/#{id}"
    },
  }.each do |route, reveal|
    it "verifies the account through #{route}" do
      cust, secret_id = sign_up

      token = anonymous_visit
      instance_exec(secret_id, token, &reveal)

      expect(last_response.status).to eq(200), "#{route}: #{last_response.status} #{last_response.body}"
      expect(last_response.body).to include('fortune cookie')

      cust.refresh!
      expect(cust.verified?).to be(true)
      expect(Onetime::Secret.load(secret_id)&.viewable?).to be_falsey
    end
  end
end
