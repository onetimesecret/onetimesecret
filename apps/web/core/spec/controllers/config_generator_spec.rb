# apps/web/core/spec/controllers/config_generator_spec.rb
#
# frozen_string_literal: true

# Integration tests for the public Configuration Generator JSON endpoints.
#
# Run with:
#   source .env.test && bundle exec rspec apps/web/core/spec/controllers/config_generator_spec.rb

require_relative '../../../../../spec/integration/integration_spec_helper'

RSpec.describe 'Configuration Generator endpoints', type: :integration do
  include Rack::Test::Methods

  def app
    @app
  end

  before(:all) do
    require 'rack'
    require 'rack/mock'
    @original_rack_env   = ENV['RACK_ENV']
    @original_redis_url  = ENV['REDIS_URL']
    @original_valkey_url = ENV['VALKEY_URL']
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
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

  describe 'GET /config-generator/options' do
    it 'returns HTTP 200 with a JSON catalog, no auth required' do
      get '/config-generator/options'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['options']).to have_key('deployment_mode')
      expect(data['options']).to have_key('default_ttl')
    end
  end

  describe 'GET /config-generator/render' do
    it 'returns default YAML fragments with no query params' do
      get '/config-generator/render'
      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['auth_yaml']).to include('mode: simple')
      expect(data['warnings']).to eq([])
    end

    it 'applies selections passed as query params' do
      get '/config-generator/render', {
        'deployment_mode' => 'full',
        'domains_enabled' => 'true',
        'default_ttl' => '2592000',
      }
      data = JSON.parse(last_response.body)

      expect(data['auth_yaml']).to include('mode: full')
      expect(data['config_yaml']).to include('default_ttl: 2592000')
      expect(YAML.safe_load(data['config_yaml']).dig('features', 'domains', 'enabled')).to be true
    end

    it 'never includes a real secret value in the response' do
      get '/config-generator/render', { 'deployment_mode' => 'full' }
      data = JSON.parse(last_response.body)

      expect(data['env_snippet']).to match(/^SECRET=$/)
      expect(data['config_yaml']).not_to match(/secret:\s*\S/)
      expect(data['auth_yaml']).not_to include('database_url')
    end

    it 'does not error on garbage query params' do
      get '/config-generator/render', { 'deployment_mode' => 'definitely-not-a-mode', 'sso_enabled' => 'yes-please' }
      expect(last_response.status).to eq(200)
    end
  end
end
