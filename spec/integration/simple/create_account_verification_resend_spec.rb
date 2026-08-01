# spec/integration/simple/create_account_verification_resend_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — verification resend on duplicate signup in SIMPLE
#            mode (security audit 2026-07-31, dead-branch finding)
# =============================================================================
#
# `verified` is a boolean_field, and Onetime::FieldTypes::BooleanFieldType
# canonicalizes every stored value to the STRING 'true'/'false'
# (lib/onetime/field_types/boolean_field_type.rb). "false" is truthy in Ruby,
# so `if @cust.verified` in CreateAccount#process took the silent-success
# branch for EVERY persisted customer and the resend at
# apps/api/account/logic/account/create_account.rb:86 was unreachable — a user
# whose first verification email was lost could never get it resent, despite
# the behavior table at apps/web/core/controllers/registration.rb:21
# ("No-autoverify + existing unverified → Yes (resent)"). The fix reads the
# predicate: `if @cust.verified?`.
#
# The unit spec masked the bug by stubbing `verified:` with real Ruby booleans,
# values the model never returns. These examples drive the REAL simple-mode
# rack stack with REAL persisted customers — no model stubs — so the canonical
# string form is what the branch actually sees. The resend example fails
# against the raw-read code; that is the point of this file.
#
# This file MUST live in spec/integration/simple/: in full mode /auth/* is
# Rodauth's (apps/web/auth/application.rb mounts longest-prefix-first) and
# POST /auth/create-account never reaches this logic class.
#
# The suite config has autoverify: false (spec/config.test.yaml:74), which
# these examples require: with autoverify on, the first signup would persist
# verified='true' and the resend branch would be legitimately unreachable.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=simple (the default)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=simple bundle exec rspec \
#     spec/integration/simple/create_account_verification_resend_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'Duplicate-signup verification resend in simple mode (audit dead-branch finding)', type: :integration do
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
    # Full mode would route /auth/create-account to Rodauth — these assertions
    # would then be testing the wrong code path.
    skip 'requires simple auth mode' if Onetime.auth_config.full_enabled?

    # These examples depend on the first signup persisting verified='false'.
    autoverify = OT.conf.dig('site', 'authentication', 'autoverify')
    raise "Test precondition broken: autoverify must be false in spec/config.test.yaml, got #{autoverify.inspect}" if autoverify

    # Intercept delivery at the Mailer seam: send_verification_email delivers
    # SYNCHRONOUSLY via Onetime::Mail::Mailer.deliver (lib/onetime/logic/
    # base.rb), so without this stub every example would attempt real SMTP.
    # Everything upstream of the seam — Receipt.spawn_pair, secret persistence,
    # reset_secret write — still runs for real.
    @deliveries = []
    allow(Onetime::Mail::Mailer).to receive(:deliver) do |template, data, **|
      @deliveries << { template: template, email: data[:email_address] }
      true
    end

    @created_emails = []
  end

  after do
    Array(@created_emails).each do |email|
      cust = Onetime::Customer.find_by_email(email)
      cust&.destroy!
    rescue StandardError => e
      warn "[create-account resend spec] customer cleanup failed: #{e.message}"
    end
  end

  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(8)}@integration-test.example.com"
  end

  # CSRF-correct JSON POST to the Core signup route (apps/web/core/
  # routes.txt:32). Setup failure must be LOUD: a silently-nil shrimp draws a
  # 403 from the CSRF middleware and surfaces as a misleading status-assertion
  # failure three lines later.
  def post_signup(login)
    clear_cookies

    header 'Content-Type', nil
    header 'Content-Length', nil
    header 'Accept', 'application/json'
    get '/'
    token = last_response.headers['X-CSRF-Token']

    if token.to_s.empty?
      raise "CSRF setup failed: GET / returned #{last_response.status} with no X-CSRF-Token header " \
            "(headers: #{last_response.headers.keys.sort.join(', ')})."
    end

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token
    post '/auth/create-account',
         JSON.generate(login: login, password: 'integration-test-pw', skill: '', shrimp: token)

    if last_response.status == 403
      raise "CSRF rejected by the stack (403): #{last_response.body}. " \
            'This is a session/middleware problem, not a signup result.'
    end

    last_response
  end

  # Both signup outcomes must be the enumeration-safe generic success — a
  # bare 200 check would also pass if the route stopped reaching this logic.
  def expect_signup_success(response, context)
    expect(response.status).to eq(200),
      "#{context} should succeed, got #{response.status}: #{response.body}"
  end

  it 'resends the verification email when an unverified account re-submits signup' do
    email = unique_email('resend')
    @created_emails << email

    expect_signup_success(post_signup(email), 'Initial signup')

    cust = Onetime::Customer.find_by_email(email)
    expect(cust).not_to be_nil
    # The model stores the CANONICAL STRING — the exact value that made the
    # raw `if @cust.verified` read always-truthy.
    expect(cust.verified).to eq('false')
    expect(cust.verified?).to be(false)
    # reset_secret is a Familia related `string` object (customer.rb:129) —
    # compare its VALUE; the wrapper object is equal to itself by key.
    first_secret = cust.reset_secret.value
    expect(first_secret).not_to be_nil, 'initial signup must bind a verification secret'
    expect(@deliveries).to eq([{ template: :welcome, email: email }])

    expect_signup_success(post_signup(email), 'Duplicate signup for the unverified account')

    # The resend is observable two independent ways: a second :welcome
    # delivery, and a FRESH verification secret bound to the customer. Under
    # the raw-read bug, both assertions fail — the silent-success branch sends
    # nothing and leaves reset_secret untouched.
    expect(@deliveries.size).to eq(2),
      "duplicate signup for an unverified account must resend verification, deliveries: #{@deliveries.inspect}"
    expect(@deliveries.last).to eq({ template: :welcome, email: email })
    cust.refresh!
    expect(cust.reset_secret.value).not_to eq(first_secret),
      'resend must bind a fresh verification secret'
  end

  it 'takes the silent-success branch for a verified account: 200, no email, secret untouched' do
    email = unique_email('verified')
    @created_emails << email

    expect_signup_success(post_signup(email), 'Initial signup')
    cust = Onetime::Customer.find_by_email(email)
    cust.verified = true
    cust.save
    expect(cust.verified).to eq('true')
    secret_before   = cust.reset_secret.value
    delivery_before = @deliveries.size

    expect_signup_success(post_signup(email), 'Duplicate signup for the verified account')

    expect(@deliveries.size).to eq(delivery_before),
      "verified account must NOT receive email on duplicate signup, deliveries: #{@deliveries.inspect}"
    cust.refresh!
    expect(cust.reset_secret.value).to eq(secret_before)
  end
end
