# frozen_string_literal: true

# Pins the gem behaviour that token_endpoint_auth_method (#4764) depends on:
#
# - omniauth_openid_connect declares client_auth_method as a TOP-LEVEL
#   strategy option (not under client_options) and forwards it to
#   Rack::OAuth2::Client#access_token!.
# - rack-oauth2 maps nil to :basic, form-urlencodes the Basic pair
#   (RFC 6749 section 2.3.1), and has NO branch for :client_secret_post —
#   that symbol reaches the `else` arm, which puts client_id / client_secret
#   in the request body. A gem upgrade that adds a branch for it changes the
#   wire shape; this spec is what notices.
#
# Hermetic: WebMock captures the token request; nothing is parsed from it
# except the headers and the form body.

require 'spec_helper'
require 'rack/oauth2'
require 'omniauth_openid_connect'
require 'onetime/sso_provider/oidc'

RSpec.describe 'OIDC token endpoint client authentication' do
  let(:token_endpoint) { 'https://idp.example.com/oauth2/token' }
  # Characters that are not identity under form-urlencoding, so the Basic
  # header pins the ENCODED pair and the body pins the raw one.
  let(:identifier) { 'client id+1' }
  let(:secret) { 'sec+ret%25/with:punct' }
  let(:client) do
    Rack::OAuth2::Client.new(
      identifier: identifier,
      secret: secret,
      token_endpoint: token_endpoint,
      redirect_uri: 'https://app.example.com/auth/sso/oidc/callback',
    )
  end

  def exchange(*args)
    captured = nil
    stub_request(:post, token_endpoint).with { |request| captured = request }.to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { access_token: 'access', token_type: 'Bearer' }.to_json,
    )
    client.authorization_code = 'code-123'
    expect(client.access_token!(*args).access_token).to eq('access')
    [captured.headers['Authorization'], URI.decode_www_form(captured.body).to_h]
  end

  def basic_pair(header)
    expect(header).to start_with('Basic ')
    Base64.strict_decode64(header.delete_prefix('Basic ')).split(':', 2)
  end

  it 'declares client_auth_method as a top-level strategy option, not a client_options key' do
    defaults = OmniAuth::Strategies::OpenIDConnect.default_options

    expect(defaults).to have_key('client_auth_method')
    expect(defaults['client_options']).not_to have_key('client_auth_method')
  end

  it 'sends :basic as a form-urlencoded Basic pair and nothing in the body' do
    header, body = exchange(client_auth_method: :basic)

    expect(basic_pair(header)).to eq([URI.encode_www_form_component(identifier), URI.encode_www_form_component(secret)])
    expect(body.keys).not_to include('client_id', 'client_secret')
    expect(body).to include('grant_type' => 'authorization_code', 'code' => 'code-123')
  end

  it 'treats nil (no selection) exactly like :basic' do
    expect(exchange(client_auth_method: nil)).to eq(exchange(client_auth_method: :basic))
  end

  it 'sends :client_secret_post in the body byte for byte, with no Authorization header' do
    header, body = exchange(client_auth_method: :client_secret_post)

    expect(header).to be_nil
    expect(body).to include('client_id' => identifier, 'client_secret' => secret, 'code' => 'code-123')
  end

  it 'maps every accepted token_endpoint_auth_method value onto one of the two shapes above' do
    expect(Onetime::SsoProvider::Oidc::CLIENT_AUTH_METHODS).to eq(
      'client_secret_basic' => :basic,
      'client_secret_post' => :client_secret_post,
    )
  end
end
