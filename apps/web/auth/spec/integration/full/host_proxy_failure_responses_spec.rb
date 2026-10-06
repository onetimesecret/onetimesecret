# apps/web/auth/spec/integration/full/host_proxy_failure_responses_spec.rb
#
# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'

# Baseline characterization: the same legitimate tenant request before and
# during an identity lookup failure. Only the lookup is stubbed; classification,
# policy gates, OmniAuth, error translation and email composition stay mounted.
#
# A failed read gets ONE answer whatever the read raised (#4668): the Rodauth
# routes answer 503 with Onetime::DomainUnavailable, SSO initiation lands on
# /signin?auth_error=domain_unavailable. Both stay fail-closed: no email, no
# IdP URL, reset keys unchanged.
RSpec.describe 'Tenant host lookup failure responses', :shared_db_state, type: :integration do
  include Rack::Test::Methods
  include_context 'tenant fixtures'
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:account_email) { unique_test_email('host-failure') }
  let!(:account_id) { seed_account_with_password(account_email) }

  before do
    expect(Onetime.auth_config.orgs_sso_enabled?).to be(true),
      'Run this spec through tests/lanes/run full-sqlite; tenant SSO must register at boot.'
    customer = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
    Onetime::OrganizationMembership.ensure_membership(
      test_organization, customer, role: 'member', domain_scope_id: test_custom_domain.objid,
    )
    Onetime::Application::MiddlewareStack.ip_privacy_security_config
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: test_custom_domain.identifier,
      enabled: true,
      signin_enabled: true,
      sso_enabled: true,
    )
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end

    header 'Host', canonical_host
    header 'X-Forwarded-Host', tenant_domain
    header 'X-Forwarded-Proto', 'https'
    env 'REMOTE_ADDR', '127.0.0.1'
  end

  after do
    Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
    clear_auth_database
  end

  def fail_tenant_lookup!
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    allow(Onetime::CustomDomain).to receive(:from_display_domain).and_wrap_original do |original, host|
      raise lookup_failure if host == tenant_domain

      original.call(host)
    end
  end

  def expect_healthy_tenant_request
    expect(last_request.env['onetime.domain_strategy']).to eq(:custom)
    expect(last_request.env['onetime.display_domain']).to eq(tenant_domain)
    expect(last_request.env['HTTP_HOST']).to eq(rewrite_on ? tenant_domain : canonical_host)
    expect_host_rewrite(canonical_host, rewritten: rewrite_on)
  end

  # `logged_event` names the domain-unavailable check that answered: the
  # refusal is logged there with the exception class and message as scalars,
  # not by a gate's own rescue, which knows only Redis::BaseError.
  def expect_failed_tenant_request(logged_event)
    request_env = last_request.env
    lookup = request_env.fetch(Onetime::CustomDomain::Lookup::ENV_KEY)
    expect(lookup).to be_read_failed
    expect(lookup.error).to be(lookup_failure)
    expect(request_env['onetime.domain_strategy']).to eq(:invalid)
    expect(request_env['onetime.display_domain']).to eq(tenant_domain)
    expect(request_env['HTTP_HOST']).to eq(canonical_host)
    expect(request_env['onetime.custom_domain']).to be_nil
    expect_host_rewrite(canonical_host, rewritten: false)
    expect(@delivered).to be_empty
    expect(last_response.body).not_to include(lookup_failure.message, "secret-#{test_run_id}")
    expect(Auth::Logging).to have_received(:log_auth_event).with(
      logged_event,
      hash_including(
        level: :error,
        host: tenant_domain,
        error_class: lookup_failure.class.name,
        error: lookup_failure.message,
      ),
    )
  end

  [false, true].each do |rewrite|
    context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
      let(:rewrite_on) { rewrite }
      include_context 'public host rewrite setting'

      [Redis::BaseError, RuntimeError].each do |error_class|
        context "when CustomDomain lookup raises #{error_class}" do
          let(:lookup_failure) { error_class.new('private tenant lookup failure detail') }

          it 'refuses SSO with the domain-unavailable redirect, not an IdP authorization URL' do
            post '/auth/sso/entra'
            expect(last_response.status).to eq(302)
            healthy_location = URI.parse(last_response.headers.fetch('Location'))
            expect(healthy_location.host).to eq('login.microsoftonline.com')
            expect(healthy_location.path).to eq("/#{test_sso_config.tenant_id}/oauth2/v2.0/authorize")
            expect(CGI.parse(healthy_location.query).fetch('redirect_uri')).to eq(
              ["https://#{tenant_domain}/auth/sso/entra/callback"],
            )
            expect_healthy_tenant_request

            clear_cookies
            clear_body_headers
            fail_tenant_lookup!
            post '/auth/sso/entra'

            expect(last_response.status).to eq(302)
            expect(last_response.headers.fetch('Location')).to eq('/signin?auth_error=domain_unavailable')
            expect_failed_tenant_request(:omniauth_domain_lookup_failed)
          end

          it 'refuses password-reset emission with the domain-unavailable 503' do
            csrf_json_post('/auth/reset-password-request', login: account_email)
            expect(last_response.status).to eq(200)
            expect(@delivered.size).to eq(1)
            expect(@delivered.first.fetch(:body)).to include("https://#{tenant_domain}/reset-password?key=")
            expect_healthy_tenant_request
            reset_keys = auth_db[:account_password_reset_keys].where(id: account_id).all
            expect(reset_keys.size).to eq(1)

            clear_cookies
            @delivered.clear
            fail_tenant_lookup!
            csrf_json_post('/auth/reset-password-request', login: account_email)

            expect(last_response.status).to eq(503)
            expect(json_body).to include(
              'error' => 'This domain is not available. If this is your domain, contact us.',
              'error_type' => 'DomainUnavailable',
              'retry_after' => 5,
            )
            expect(last_response.headers['Retry-After']).to eq('5')
            expect(last_response.headers['Location']).to be_nil
            expect(last_response.body).not_to include('reset-password?key=', 'redirect_uri=')
            expect(auth_db[:account_password_reset_keys].where(id: account_id).all).to eq(reset_keys)
            expect_failed_tenant_request(:rodauth_domain_lookup_failed)
          end
        end
      end
    end
  end
end
