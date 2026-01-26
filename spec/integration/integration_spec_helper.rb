# spec/integration/integration_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'json'

# Integration tests use REAL Valkey/Redis on port 2121
# The ConfigureFamilia initializer enforces this for safety (prevents
# accidentally writing to production Redis on default port 6379).
#
# To run integration tests:
#   pnpm run test:database:start  # Start Valkey on port 2121
#   pnpm run test:rspec:failures spec/integration/
#
# FakeRedis is NOT used for integration tests because:
# 1. Integration tests require full application boot (Onetime.boot!)
# 2. Rodauth requires real database transactions
# 3. Session storage needs real Redis operations
# 4. FakeRedis 0.1.4 is incompatible with Redis 5.x client

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include Rack::Test::Methods, type: :integration

  # Parse Redis URI once at configuration time for robust port checking
  redis_uri_string = OT.conf&.dig('redis', 'uri')
  test_redis_port = begin
    URI.parse(redis_uri_string).port if redis_uri_string
  rescue URI::InvalidURIError
    nil
  end

  # Clean Valkey database before all integration tests in a group
  # Skip if :shared_db_state metadata is set (for specs using before(:all) shared setup)
  # Skip if :billing metadata is set (billing tests manage their own plan data)
  config.before(:all, type: :integration) do |context|
    next if context.class.metadata[:shared_db_state]
    next if context.class.metadata[:billing]

    if test_redis_port == 2121
      begin
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database before all: #{e.message}"
        warn e.backtrace.join("\n") if ENV['ONETIME_DEBUG']
      end
    end
  end

  # Clean Valkey database before each integration test
  # Skip if :shared_db_state metadata is set (for specs using before(:all) shared setup)
  # Skip if :billing metadata is set (billing tests manage their own plan data)
  config.before(:each, type: :integration) do |example|
    next if example.metadata[:shared_db_state]
    next if example.metadata[:billing]

    if test_redis_port == 2121
      begin
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database: #{e.message}"
        warn e.backtrace.join("\n") if ENV['ONETIME_DEBUG']
      end
    end
  end

  # NOTE: after(:each) cleanup is handled centrally in spec/spec_helper.rb
  # to ensure ALL integration tests get cleanup regardless of which helper they load.
end

# CSRF Token Helper Module for Integration Tests
#
# Provides helpers for making POST/PUT/DELETE requests with CSRF tokens.
# Auth routes require CSRF tokens (like all browser-facing routes).
# These helpers establish a session, extract the CSRF token from the
# X-CSRF-Token response header, and include it in subsequent requests.
#
# Usage:
#   include CsrfTestHelpers
#
#   it 'posts with csrf' do
#     csrf_post '/auth/login', { login: 'test@example.com', password: 'secret' }
#     expect(last_response.status).to eq(401)  # Invalid credentials, not 403 CSRF
#   end
#
module CsrfTestHelpers
  # Establish a session and retrieve CSRF token
  #
  # Makes a GET request to /auth to initialize a session and retrieve
  # the CSRF token from the X-CSRF-Token response header.
  #
  # @return [String, nil] The CSRF token or nil if not present
  def ensure_csrf_token
    return @csrf_token if defined?(@csrf_token) && @csrf_token

    # Make a GET request to establish session
    header 'Accept', 'application/json'
    get '/auth'
    @csrf_token = last_response.headers['X-CSRF-Token']
    @csrf_token
  end

  # Reset CSRF token (useful between test examples)
  def reset_csrf_token
    @csrf_token = nil
  end

  # POST with JSON content and CSRF token
  #
  # @param path [String] Request path
  # @param params [Hash] Request parameters (will be JSON-encoded)
  # @param headers [Hash] Additional headers
  def csrf_post(path, params = {}, headers = {})
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    # Include shrimp in body (mirrors frontend behavior)
    post path, JSON.generate(params.merge(shrimp: csrf_token)), headers
  end

  # PUT with JSON content and CSRF token
  #
  # @param path [String] Request path
  # @param params [Hash] Request parameters (will be JSON-encoded)
  # @param headers [Hash] Additional headers
  def csrf_put(path, params = {}, headers = {})
    csrf_token = ensure_csrf_token

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    put path, JSON.generate(params.merge(shrimp: csrf_token)), headers
  end

  # DELETE with CSRF token
  #
  # @param path [String] Request path
  # @param params [Hash] Request parameters
  # @param headers [Hash] Additional headers
  def csrf_delete(path, params = {}, headers = {})
    csrf_token = ensure_csrf_token

    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf_token if csrf_token

    delete path, params.merge(shrimp: csrf_token), headers
  end
end
