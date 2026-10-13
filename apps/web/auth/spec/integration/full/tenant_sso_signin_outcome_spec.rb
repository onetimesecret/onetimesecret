# apps/web/auth/spec/integration/full/tenant_sso_signin_outcome_spec.rb
#
# frozen_string_literal: true

# The tenant SSO hooks record the outcome of each sign-in against the domain
# (CustomDomain::SsoSigninOutcome), which the domain owner reads as
# `last_sign_in` on the SSO settings page. Driven through the real
# initiation + callback routes in OmniAuth test mode on a tenant host, the
# same way domain_sso_join_organization_spec drives the join.
#
# Covered stages:
#   provider  the strategy fails the callback (mock_auth = :invalid_credentials)
#   callback  the callback lands on a different tenant (tenant_mismatch)
#   account   the identity has no usable email (missing_email)
#   success   a JIT-created tenant sign-in completes
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/tenant_sso_signin_outcome_spec.rb

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'Tenant SSO sign-in outcome (last_sign_in)', type: :integration, oauth_flow: true do
  include Rack::Test::Methods
  include OAuthFlowHelper
  include_context 'domains enabled'

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) { boot_onetime_app }

  let(:run_id) { "outcome-#{SecureRandom.hex(4)}" }
  let(:domain_host) { "secrets-#{run_id}.tenant.example.com" }
  let(:user_email) { "new-user-#{run_id}@tenant.example.com" }

  before do
    skip 'ORGS_SSO_ENABLED not set at boot — /auth/sso/* routes are not registered' unless Onetime.auth_config.orgs_sso_enabled?

    @fixtures = setup_oauth_test_domain(domain_host)
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]
  end

  after do
    Onetime::Customer.find_by_email(user_email)&.destroy! rescue nil
    Onetime::CustomDomain::SsoSigninOutcome.delete_for_domain!(@fixtures[:domain].identifier) rescue nil
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    cleanup_oauth_test_fixtures
  end

  def mock_identity(email:)
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
      provider: 'oidc',
      uid: "uid-#{run_id}",
      info: { email: email, name: 'Outcome Test User' },
    )
  end

  def initiate(host)
    header 'Host', host
    post '/auth/sso/oidc'
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
    expect(last_response.status).to eq(302), "Initiation should redirect, got #{last_response.status}"
  end

  def callback(host)
    header 'Host', host
    post '/auth/sso/oidc/callback'
  end

  def outcome
    Onetime::CustomDomain::SsoSigninOutcome.find_by_domain_id(@fixtures[:domain].identifier)
  end

  it 'records nothing before any sign-in' do
    expect(outcome).to be_nil
  end

  it 'records a completed tenant sign-in as succeeded, with the provider type' do
    mock_identity(email: user_email)
    initiate(domain_host)
    callback(domain_host)
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location.to_s).not_to include('auth_error=')

    recorded = outcome
    expect(recorded).not_to be_nil
    expect(recorded.to_api_h).to include(
      result: 'succeeded',
      failure_stage: nil,
      failure_code: nil,
      provider_type: 'oidc',
    )
    expect(recorded.to_api_h[:succeeded_at]).to be_within(30).of(Time.now.to_i)
  end

  it 'records a strategy failure as failed at the provider stage with the error type' do
    OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
    initiate(domain_host)
    callback(domain_host)
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location.to_s).to include('auth_error=sso_failed')

    expect(outcome.to_api_h).to include(
      result: 'failed',
      failure_stage: 'provider',
      failure_code: 'invalid_credentials',
      succeeded_at: nil,
    )
  end

  it 'records an identity without a usable email as failed at the account stage' do
    mock_identity(email: '')
    initiate(domain_host)
    callback(domain_host)
    expect(last_response.location.to_s).to include('auth_error=missing_email')

    expect(outcome.to_api_h).to include(result: 'failed', failure_stage: 'account', failure_code: 'missing_email')
  end

  it 'records a callback on another tenant as failed at the callback stage, against the domain that started it' do
    other_host     = "secrets-#{run_id}.other.example.com"
    other_fixtures = setup_oauth_test_domain(other_host)
    mock_identity(email: user_email)
    initiate(domain_host)
    callback(other_host)
    expect(last_response.status).to eq(403), last_response.body

    expect(outcome.to_api_h).to include(result: 'failed', failure_stage: 'callback', failure_code: 'tenant_mismatch')
    expect(Onetime::CustomDomain::SsoSigninOutcome.find_by_domain_id(other_fixtures[:domain].identifier)).to be_nil
  ensure
    Onetime::CustomDomain::SsoSigninOutcome.delete_for_domain!(other_fixtures[:domain].identifier) if other_fixtures
  end

  it 'keeps the last success alongside a later failure' do
    mock_identity(email: user_email)
    initiate(domain_host)
    callback(domain_host)
    expect(last_response.location.to_s).not_to include('auth_error=')
    succeeded_at = outcome.to_api_h[:succeeded_at]

    OmniAuth.config.mock_auth[:oidc] = :invalid_credentials
    initiate(domain_host)
    callback(domain_host)

    expect(outcome.to_api_h).to include(result: 'failed', succeeded_at: succeeded_at, failure_code: 'invalid_credentials')
  end

  it 'does not record a platform sign-in on the canonical host' do
    mock_identity(email: user_email)
    clear_body_headers
    post '/auth/sso/oidc/callback'

    expect(outcome).to be_nil
  end
end
