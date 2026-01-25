# apps/web/core/spec/controllers/page_bootstrap_me_spec.rb
#
# frozen_string_literal: true

# Integration tests for GET /bootstrap/me endpoint
#
# This endpoint returns JSON with the full OnetimeWindow payload for client-side
# state initialization. It's called every 15 minutes to refresh client state
# and after login/MFA completion.
#
# Run with:
#   source .env.test && bundle exec rspec apps/web/core/spec/controllers/page_bootstrap_me_spec.rb

require_relative '../../../../../spec/integration/integration_spec_helper'

RSpec.describe 'GET /bootstrap/me', type: :integration do
  include Rack::Test::Methods

  def app
    @app
  end

  before(:all) do
    require 'rack'
    require 'rack/mock'
    # Clear Redis env vars to ensure test config defaults are used (port 2121)
    @original_rack_env = ENV['RACK_ENV']
    @original_redis_url = ENV['REDIS_URL']
    @original_valkey_url = ENV['VALKEY_URL']
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    # Ensure RACK_ENV is test so boot! is idempotent
    ENV['RACK_ENV'] = 'test'
    @app = Rack::Builder.parse_file('config.ru')
  end

  after(:all) do
    if @original_rack_env
      ENV['RACK_ENV'] = @original_rack_env
    else
      ENV.delete('RACK_ENV')
    end
    if @original_redis_url
      ENV['REDIS_URL'] = @original_redis_url
    else
      ENV.delete('REDIS_URL')
    end
    if @original_valkey_url
      ENV['VALKEY_URL'] = @original_valkey_url
    else
      ENV.delete('VALKEY_URL')
    end
  end

  describe 'response format' do
    it 'returns HTTP 200' do
      get '/bootstrap/me'
      expect(last_response.status).to eq(200)
    end

    it 'returns JSON content type' do
      get '/bootstrap/me'
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns valid JSON body' do
      get '/bootstrap/me'
      expect { JSON.parse(last_response.body) }.not_to raise_error
    end
  end

  describe 'anonymous user' do
    it 'returns authenticated as false' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['authenticated']).to be false
    end

    it 'returns awaiting_mfa as false' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['awaiting_mfa']).to be false
    end

    it 'returns had_valid_session as false for fresh sessions' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['had_valid_session']).to be false
    end

    it 'returns cust with anonymous customer data' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['cust']).to be_a(Hash)
      # Anonymous customer has specific structure from safe_dump
      # Uses extid (external ID) for public identification
      expect(data['cust']).to include('extid')
      expect(data['cust']['extid']).to eq('anon')
    end

    it 'returns custid as nil for anonymous user' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['custid']).to be_nil
    end

    it 'returns email as nil for anonymous user' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['email']).to be_nil
    end
  end

  describe 'CSRF token (shrimp)' do
    it 'includes shrimp key in response' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      # The shrimp key should always be present in the response structure
      # Value may be nil if CSRF middleware hasn't generated a token yet
      expect(data).to have_key('shrimp')
    end

    it 'returns different masked shrimp tokens on each request (BREACH mitigation)' do
      # First request establishes session
      get '/bootstrap/me'
      first_shrimp = JSON.parse(last_response.body)['shrimp']

      # Second request with cookies should have different masked token
      # (same underlying session token, but masked differently each time)
      get '/bootstrap/me'
      second_shrimp = JSON.parse(last_response.body)['shrimp']

      # Masked tokens should differ (BREACH mitigation), but both should be non-nil
      expect(first_shrimp).not_to be_nil
      expect(second_shrimp).not_to be_nil
      expect(first_shrimp).not_to eq(second_shrimp)
    end
  end

  describe 'locale settings' do
    it 'returns locale value' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['locale']).not_to be_nil
    end

    it 'returns default_locale value' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['default_locale']).not_to be_nil
    end

    it 'returns supported_locales array' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['supported_locales']).to be_an(Array)
    end

    it 'returns i18n_enabled flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('i18n_enabled')
    end

    it 'returns fallback_locale value' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('fallback_locale')
    end
  end

  describe 'configuration settings' do
    it 'returns site_host' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['site_host']).not_to be_nil
    end

    it 'returns authentication config' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('authentication')
    end

    it 'returns secret_options' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('secret_options')
    end

    it 'returns domains_enabled flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('domains_enabled')
    end

    it 'returns regions_enabled flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('regions_enabled')
    end

    it 'returns billing_enabled flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('billing_enabled')
    end

    it 'returns features hash' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to be_a(Hash)
    end
  end

  describe 'system information' do
    it 'returns ot_version' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['ot_version']).not_to be_nil
    end

    it 'returns ot_version_long' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['ot_version_long']).not_to be_nil
    end

    it 'returns ruby_version' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['ruby_version']).not_to be_nil
    end

    it 'returns nonce for CSP' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      # nonce may be nil if CSP middleware not active, but key should exist
      expect(data).to have_key('nonce')
    end
  end

  describe 'domain configuration' do
    it 'returns domain_strategy' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('domain_strategy')
    end

    it 'returns canonical_domain' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('canonical_domain')
    end

    it 'returns display_domain' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('display_domain')
    end

    it 'returns domain_context key' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('domain_context')
    end

    it 'returns nil domain_context for anonymous user' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      # Anonymous users don't have domain_context set
      expect(data['domain_context']).to be_nil
    end
  end

  describe 'messages serializer' do
    it 'returns messages key' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('messages')
    end
  end

  describe 'development settings' do
    it 'returns development config hash' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['development']).to be_a(Hash)
    end

    it 'returns frontend_development flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('frontend_development')
    end

    it 'returns frontend_host' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data).to have_key('frontend_host')
    end
  end

  describe 'response structure completeness' do
    # These are the keys from all serializers that should be present
    let(:authentication_keys) do
      %w[authenticated awaiting_mfa had_valid_session custid cust email customer_since]
    end

    let(:config_keys) do
      %w[ui authentication homepage_mode secret_options site_host
         regions_enabled domains_enabled billing_enabled
         frontend_development frontend_host development features]
    end

    let(:domain_keys) do
      %w[domain_strategy canonical_domain display_domain domain_context]
    end

    let(:i18n_keys) do
      %w[locale default_locale fallback_locale supported_locales i18n_enabled]
    end

    let(:system_keys) do
      %w[ot_version ot_version_long ruby_version shrimp nonce]
    end

    it 'includes all authentication serializer keys' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      authentication_keys.each do |key|
        expect(data).to have_key(key), "Expected response to include '#{key}'"
      end
    end

    it 'includes all config serializer keys' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      config_keys.each do |key|
        expect(data).to have_key(key), "Expected response to include '#{key}'"
      end
    end

    it 'includes all domain serializer keys' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      domain_keys.each do |key|
        expect(data).to have_key(key), "Expected response to include '#{key}'"
      end
    end

    it 'includes all i18n serializer keys' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      i18n_keys.each do |key|
        expect(data).to have_key(key), "Expected response to include '#{key}'"
      end
    end

    it 'includes all system serializer keys' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      system_keys.each do |key|
        expect(data).to have_key(key), "Expected response to include '#{key}'"
      end
    end
  end

  describe 'no auth requirement' do
    # The endpoint has auth=noauth, meaning it should work without any authentication
    it 'returns successfully without any session cookies' do
      # Use a fresh browser with no cookies
      clear_cookies
      get '/bootstrap/me'
      expect(last_response.status).to eq(200)
    end

    it 'does not redirect unauthenticated users' do
      clear_cookies
      get '/bootstrap/me'
      expect(last_response.status).not_to eq(302)
      expect(last_response.status).not_to eq(301)
    end
  end

  describe 'feature flags in features hash' do
    it 'includes hardening feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('hardening')
    end

    it 'includes active_sessions feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('active_sessions')
    end

    it 'includes remember_me feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('remember_me')
    end

    it 'includes mfa feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('mfa')
    end

    it 'includes email_auth feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('email_auth')
    end

    it 'includes webauthn feature flag' do
      get '/bootstrap/me'
      data = JSON.parse(last_response.body)
      expect(data['features']).to have_key('webauthn')
    end
  end
end
