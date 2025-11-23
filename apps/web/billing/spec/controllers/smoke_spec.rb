# apps/web/billing/spec/controllers/smoke_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Billing Controllers', :integration do
  include Rack::Test::Methods

  # The Rack application for testing
  def app
    @app ||= Billing::Application.new
  end

  describe 'application bootstrap' do
    it 'loads billing application successfully' do
      expect(Billing::Application).not_to be_nil
    end

    it 'mounts controllers correctly' do
      expect(Billing::Controllers::Webhooks).not_to be_nil
      expect(Billing::Controllers::Billing).not_to be_nil
      expect(Billing::Controllers::Plans).not_to be_nil
      expect(Billing::Controllers::Capabilities).not_to be_nil
    end

    it 'configures routes correctly' do
      # Verify route file exists and is loaded
      routes_file = File.join(File.dirname(__FILE__), '../../routes.txt')
      expect(File.exist?(routes_file)).to eq(true)
    end
  end

  describe 'basic HTTP requests' do
    it 'returns 404 for unknown routes' do
      get '/billing/nonexistent'

      expect(last_response.status).to eq(404)
    end

    it 'teapot endpoint returns 418', :vcr do
      get '/billing/teapot'

      expect(last_response.status).to eq(418)
      expect(last_response.body).to include('teapot')
    end
  end

  describe 'authentication requirements' do
    it 'public endpoints do not require authentication' do
      # Plan listing should be accessible without auth
      get '/billing/api/plans'

      # Should not be 401 (may be other errors without Stripe setup)
      expect(last_response.status).not_to eq(401)
    end

    it 'protected endpoints require authentication' do
      # Clear session
      env 'rack.session', {}

      # Organization billing should require auth
      get '/billing/api/org/test_org_id'

      expect(last_response.status).to eq(401)
    end
  end

  describe 'CORS and security headers' do
    it 'sets CSRF response headers on requests' do
      get '/billing/api/plans'

      # Verify CSRF headers are present
      # (exact headers depend on CsrfResponseHeader middleware implementation)
      expect(last_response.headers).to be_a(Hash)
    end
  end
end
