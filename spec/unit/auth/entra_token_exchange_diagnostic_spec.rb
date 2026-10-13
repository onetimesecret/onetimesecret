# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'onetime/models/custom_domain/sso_config'
require_relative '../../../scripts/diagnostics/entra_token_exchange'

RSpec.describe EntraTokenExchangeDiagnostic do
  let(:output) { StringIO.new }
  let(:host) { 'secrets.example.com' }
  let(:tenant_id) { 'stored-tenant' }
  let(:client_id) { 'stored-client' }
  let(:secret) { 'stored+secret%with:punctuation' }
  let(:token_url) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token" }
  let(:stored) do
    double('stored config', provider_type: 'entra_id', domain_id: 'domain-123', platform_route_name: 'entra',
      to_omniauth_options: { tenant_id: tenant_id, client_id: client_id, client_secret: secret })
  end
  let(:strategy) do
    OmniAuth::Strategies::EntraId.new(->(_env) { [404, {}, []] },
      name: 'entra', path_prefix: '/auth/sso', tenant_id: tenant_id, client_id: client_id, client_secret: secret)
  end
  let(:records) { output.string.lines.map { |line| JSON.parse(line) } }

  before do
    allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id).with('domain-123').and_return(stored)
    env = Rack::MockRequest.env_for("https://#{host}/auth/sso/entra/callback?code=private-code")
    env['rack.session'] = {}
    env['onetime.display_domain'] = host
    env['onetime.tenant_sso_config'] = stored
    strategy.instance_variable_set(:@env, env)
    described_class.observe!(domain_id: 'domain-123', host: host, output: output)
  end

  after { described_class.stop! }

  def refuse_exchange
    stub_request(:post, token_url).to_return(status: 400,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(error: 'invalid_client',
        error_description: "AADSTS7000215: private description #{secret}"))
  end

  it 'observes the actual code exchange without changing the request or swallowing its error' do
    request = refuse_exchange
    expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
    expect(request.with do |wire|
      params = URI.decode_www_form(wire.body).to_h
      params == { 'grant_type' => 'authorization_code', 'code' => 'private-code',
                  'redirect_uri' => "https://#{host}/auth/sso/entra/callback" } &&
        wire.headers['Authorization'] == "Basic #{Base64.strict_encode64("#{client_id}:#{secret}")}"
    end).to have_been_requested.once
    expect(records.first).to include('tenant_config_in_request' => true,
      'raw_basic_matches_stored' => true, 'form_encoded_basic_matches_stored' => false,
      'authorization_code_grant' => true, 'code_present' => true)
    expect(records.last).to include('http_status' => 400, 'aadsts_code' => 'AADSTS7000215')
    expect(records.map { |record| record['probe_id'] }.uniq.length).to eq(1)
    [secret, client_id, tenant_id, 'private-code', 'private description'].each do |value|
      expect(output.string).not_to include(value)
    end
  end

  it 'reports a different runtime secret instead of treating the stored probe as proof' do
    refuse_exchange
    strategy.options.client_secret = 'different-runtime-secret'
    expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
    expect(records.first).to include('raw_basic_matches_stored' => false,
      'form_encoded_basic_matches_stored' => false, 'body_secret_present' => false)
    expect(output.string).not_to include('different-runtime-secret')
  end

  it 'supports request-body authentication and never prints a successful token' do
    strategy.options.client_options.auth_scheme = :request_body
    stub_request(:post, token_url).to_return(headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(access_token: 'private-access-token', token_type: 'Bearer'))
    expect(strategy.send(:build_access_token).token).to eq('private-access-token')
    expect(records.first).to include('authorization_scheme' => 'none',
      'body_client_id_matches_stored' => true, 'body_secret_matches_stored' => true)
    expect(records.last).to include('http_status' => 200, 'access_token_present' => true)
    expect(output.string).not_to include('private-access-token', secret)
  end

  it 'does not observe a different tenant' do
    refuse_exchange
    strategy.env['onetime.display_domain'] = 'other.example.com'
    strategy.env.delete('onetime.tenant_sso_config')
    expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
    expect(output.string).to be_empty
  end

  it 'does not change the OAuth error when the diagnostic sink fails' do
    refuse_exchange
    allow(output).to receive(:puts).and_raise(IOError, 'sink unavailable')
    expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
  end

  it 'does not change the OAuth error when diagnostic credential extraction fails' do
    refuse_exchange
    allow(stored).to receive(:to_omniauth_options).and_raise(StandardError, secret)
    expect { strategy.send(:build_access_token) }.to raise_error(OAuth2::Error)
    expect(records.last).to include('event' => 'observer_failed', 'exception_class' => 'StandardError')
    expect(output.string).not_to include(secret)
  end
end
