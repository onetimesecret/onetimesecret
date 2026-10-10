# frozen_string_literal: true

require_relative '../../spec_helper'
require 'jwt'

# These stateful integration examples span several layers, not one class.
# Boot is shared; records and mutable configuration are isolated per example.
# rubocop:disable RSpec/DescribeClass, RSpec/BeforeAfterAll, RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

# Mounted Entra ID code flow through the REAL omniauth-entra-id strategy, with
# only the token endpoint mocked (#3478, #3499). OmniAuth test_mode is off: the
# strategy builds the authorize redirect, exchanges the code, decodes the ID
# token and maps its claims into the auth hash exactly as it does in
# production. The tenant hooks, SQL identities and Valkey sessions all run.
#
# The ID tokens are SYNTHETIC fixtures shaped like Microsoft's documented v2.0
# payloads (https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference).
# They establish what the strategy DOES with a claim shape, not which shapes a
# given tenant emits; that is the operator smoke test in
# docs/runbooks/sso-entra-claim-smoke-test.md. Mocked auth hashes (the sibling
# omniauth_missing_email_spec.rb) test the hooks; this file tests the strategy
# and route in front of them.
#
# Not reproduced here: signature verification. omniauth-entra-id 3.1.1 decodes
# the ID token it received over TLS from the token endpoint without checking
# its signature (JWT.decode(..., nil, false)) and verifies aud/iss/exp/nbf
# only, so the fixtures are HS256-signed with a throwaway key.
#
# Run: tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/entra_native_claims_spec.rb
RSpec.describe 'Entra ID native claim shapes through the mounted strategy', :shared_db_state, type: :integration do
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:run_id) { SecureRandom.hex(8) }
  let(:tenant_host) { "entra-#{run_id}.tenant-example.com" }
  let(:tenant_id) { "tenant-#{run_id}" }
  let(:client_id) { "client-#{run_id}" }
  let(:client_secret) { "secret-#{run_id}" }
  # The strategy verifies `iss` against its configured tenant and `aud`
  # against its client id (omniauth-entra-id 3.1.1, raw_info).
  let(:issuer) { "https://login.microsoftonline.com/#{tenant_id}/v2.0" }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:oid) { SecureRandom.uuid }
  let(:allowed_domains) { ['contoso.example.com'] }
  let(:member_email) { "member-#{run_id}@contoso.example.com" }
  let(:token_requests) { [] }

  let!(:tenant) do
    owner           = Onetime::Customer.new(email: "owner-#{run_id}@test.local")
    owner.save
    org             = Onetime::Organization.create!("Entra #{run_id}", owner, owner.email)
    domain          = Onetime::CustomDomain.new(display_domain: tenant_host, org_id: org.org_id)
    domain.verified = true
    domain.save
    Onetime::CustomDomain.display_domain_index.put(tenant_host, domain.domainid)
    Onetime::CustomDomain::SsoConfig.create!(
      domain_id: domain.identifier,
      provider_type: 'entra_id',
      tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      enabled: true,
      allowed_domains: allowed_domains,
    )
    { owner: owner, org: org, domain: domain }
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  around do |example|
    saved_mode                = OmniAuth.config.test_mode
    network_config            = WebMock::Config.instance
    saved_network             = [:allow_net_connect, :allow_localhost, :allow, :net_http_connect_on_start]
      .to_h { |key| [key, network_config.public_send(key)] }
    OmniAuth.config.test_mode = false
    WebMock.disable_net_connect!(allow_localhost: true)
    example.run
  ensure
    OmniAuth.config.test_mode = saved_mode
    saved_network.each { |key, value| network_config.public_send("#{key}=", value) }
  end

  before do
    raise 'This spec requires a full SSO lane (ORGS_SSO_ENABLED)' unless Onetime.auth_config.orgs_sso_enabled?

    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
  end

  after do
    [member_email].each do |email|
      customer = Onetime::Customer.find_by_email(email)
      next unless customer

      Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)&.destroy!
      customer.destroy!
    end
    Onetime::CustomDomain::SsoConfig.delete_for_domain!(tenant[:domain].identifier)
    Onetime::CustomDomain.display_domain_index.remove(tenant_host)
    tenant[:domain].destroy!
    tenant[:org].destroy!
    tenant[:owner].destroy!
    clear_auth_database
  end

  def tenant_headers
    clear_body_headers
    header 'Host', canonical_host
    header 'X-Forwarded-Host', tenant_host
    header 'X-Forwarded-Proto', 'https'
    header 'Accept', 'text/html'
  end

  # A v2.0 ID token payload. Everything Microsoft documents as always present
  # is here; `claims` adds or omits the optional ones under test. There is no
  # `mail` claim in any documented ID-token, optional-claim or UserInfo
  # surface, so none of the fixtures carry one.
  def synthetic_id_token(**claims)
    now     = Time.now.to_i
    payload = {
      aud: client_id,
      iss: issuer,
      iat: now,
      nbf: now,
      exp: now + 300,
      ver: '2.0',
      tid: tenant_id,
      oid: oid,
      sub: "sub-#{run_id}",
      name: 'Synthetic User',
    }.merge(claims)
    JWT.encode(payload, 'throwaway-signing-key', 'HS256')
  end

  def start_login
    tenant_headers
    post '/auth/sso/entra', {}, 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(302), last_response.body
    location = URI.parse(last_response.location)
    expect(location.host).to eq('login.microsoftonline.com')
    expect(location.path).to eq("/#{tenant_id}/oauth2/v2.0/authorize")
    query    = CGI.parse(location.query).transform_values(&:first)
    expect(query.fetch('client_id')).to eq(client_id)
    expect(query.fetch('redirect_uri')).to eq("https://#{tenant_host}/auth/sso/entra/callback")
    expect(query.fetch('scope')).to eq('openid profile email')
    expect(query.fetch('state')).not_to be_empty
    expect(last_request.env['rack.session'].to_h['omniauth.state']).to eq(query.fetch('state'))
    query
  end

  # Microsoft access tokens are opaque to the client; the strategy's attempt to
  # decode one as a JWT is rescued and contributes nothing to raw_info.
  def stub_token_endpoint(id_token)
    stub_request(:post, token_url).with do |request|
      token_requests << request
      true
    end.to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: {
        token_type: 'Bearer',
        scope: 'openid profile email',
        expires_in: 3599,
        access_token: "opaque-access-#{run_id}",
        id_token: id_token,
      }.to_json,
    )
  end

  def callback(flow)
    tenant_headers
    get '/auth/sso/entra/callback',
      { code: "code-#{run_id}", state: flow.fetch('state') },
      'REMOTE_ADDR' => '127.0.0.1'
  end

  def complete_flow(**claims)
    flow = start_login
    stub_token_endpoint(synthetic_id_token(**claims))
    callback(flow)
    flow
  end

  def expect_code_exchange(flow)
    request = token_requests.last
    expect(request).not_to be_nil, 'the strategy never exchanged the code'
    params  = URI.decode_www_form(request.body).to_h
    expect(params).to include(
      'grant_type' => 'authorization_code',
      'code' => "code-#{run_id}",
      'redirect_uri' => flow.fetch('redirect_uri'),
    )
    expect(a_request(:post, token_url)).to have_been_made.once
    # The only egress is the token endpoint: no Microsoft Graph or UserInfo
    # enrichment supplies claims the token did not carry.
    expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    expect(a_request(:get, /login\.microsoftonline\.com/)).not_to have_been_made
  end

  def auth_hash
    hash = last_request.env['omniauth.auth']
    expect(hash).not_to be_nil, 'the strategy did not complete its callback phase'
    hash
  end

  def expect_no_account
    session = last_request.env['rack.session'].to_h
    expect(session['authenticated']).not_to be(true)
    expect(session['account_id']).to be_nil
    expect(auth_db[:account_identities].where(provider: 'entra', uid: "#{tenant_id}#{oid}").count).to eq(0)
    expect(auth_db[:accounts].where(Sequel.like(:email, "%#{run_id}%")).count).to eq(0)
  end

  describe 'a managed member whose token carries the email claim' do
    it 'maps the claim into info.email, provisions the account and signs in' do
      flow = complete_flow(email: member_email, preferred_username: member_email)
      expect_code_exchange(flow)

      hash = auth_hash
      expect(hash['provider'].to_s).to eq('entra')
      expect(hash['uid']).to eq("#{tenant_id}#{oid}")
      expect(hash['info']['email']).to eq(member_email)
      expect(hash['extra']['raw_info']['email']).to eq(member_email)
      expect(hash['extra']['raw_info']).not_to have_key('mail')

      expect(last_response.status).to eq(302), last_response.body
      expect(last_response.location).not_to include('auth_error=')
      account  = auth_db[:accounts].where(email: member_email).first
      expect(account).not_to be_nil
      identity = auth_db[:account_identities].where(provider: 'entra', uid: "#{tenant_id}#{oid}").first
      expect(identity).to include(account_id: account[:id], issuer: issuer)
      expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
    end

    it 'trims a padded email claim before the account is persisted' do
      complete_flow(email: "  #{member_email}\t")

      expect(last_response.status).to eq(302), last_response.body
      expect(last_response.location).not_to include('auth_error=')
      expect(auth_db[:accounts].where(email: member_email).count).to eq(1)
    end
  end

  describe 'a token without the email claim' do
    # What a v2.0 token looks like when the app registration has no email
    # optional claim, or the directory has no value to put in it: the standard
    # identity claims are present, `email` is absent, and nothing names a
    # mailbox. preferred_username is present and email-shaped by design.
    let(:guest_upn) { "visitor_gmail.com#EXT\#@contoso-#{run_id}.onmicrosoft.com" }

    it 'yields a nil info.email and no mail key, and is refused as missing_email' do
      flow = complete_flow(preferred_username: member_email)
      expect_code_exchange(flow)

      hash = auth_hash
      expect(hash['uid']).to eq("#{tenant_id}#{oid}")
      expect(hash['info']['email']).to be_nil
      raw  = hash['extra']['raw_info']
      expect(raw).not_to have_key('email')
      expect(raw).not_to have_key('mail')
      expect(raw['preferred_username']).to eq(member_email)

      expect(last_response.status).to eq(302), last_response.body
      expect(last_response.location).to eq('/signin?auth_error=missing_email')
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_tenant_domain_rejected, hash_including(reason: :missing_email))
      expect_no_account
    end

    it 'does not substitute an email-shaped guest UPN for the absent claim' do
      flow = complete_flow(preferred_username: guest_upn, upn: guest_upn, idp: 'live.com')
      expect_code_exchange(flow)

      expect(auth_hash['info']['email']).to be_nil
      expect(last_response.location).to eq('/signin?auth_error=missing_email')
      expect(auth_db[:accounts].where(email: guest_upn).count).to eq(0)
      expect(auth_db[:accounts].where(email: guest_upn.downcase).count).to eq(0)
      expect_no_account
    end

    context 'when the tenant has no email-domain allowlist' do
      let(:allowed_domains) { [] }

      it 'is refused by the provisioning guard instead, with the same outcome' do
        flow = complete_flow(preferred_username: member_email)
        expect_code_exchange(flow)

        expect(auth_hash['info']['email']).to be_nil
        expect(last_response.location).to eq('/signin?auth_error=missing_email')
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_missing_email, hash_including(provider: :entra))
        expect_no_account
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/BeforeAfterAll, RSpec/MultipleMemoizedHelpers
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
