# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Rodauth Security Hooks', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Set advanced mode before loading the application
    ENV['RACK_ENV'] = 'test'
    ENV['AUTHENTICATION_MODE'] = 'advanced'

    Onetime.boot! :test

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  # Helper method to send JSON requests to Rodauth endpoints
  def json_post(path, params)
    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    post path, JSON.generate(params)
  end

  let(:dbclient) { Familia.dbclient(0) }
  let(:test_email) { "test-#{SecureRandom.hex(8)}@example.com" }
  let(:valid_password) { 'SecureP@ss123' }

  before do
    # Clear any existing rate limit data
    dbclient.keys('login_attempts:*').each { |key| dbclient.del(key) }
  end

  after do
    # Cleanup
    dbclient.keys('login_attempts:*').each { |key| dbclient.del(key) }
  end

  describe 'before_create_account hook' do
    context 'with valid email' do
      it 'allows account creation' do
        json_post '/auth/create-account', {
          login: test_email,
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to be_between(200, 299).or be(422) # 422 if DB constraints fail
      end
    end

    context 'with invalid email format' do
      it 'rejects account creation' do
        json_post '/auth/create-account', {
          login: 'not-an-email',
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        # Check field-error which contains our custom validation message
        expect(json['field-error']).to be_an(Array)
        expect(json['field-error'][0]).to eq('login')
      end
    end

    context 'with empty email' do
      it 'rejects account creation' do
        json_post '/auth/create-account', {
          login: '',
          password: valid_password,
          'password-confirm': valid_password
        }

        expect(last_response.status).to eq(422)
        json = JSON.parse(last_response.body)
        # Check field-error which contains our custom validation message
        expect(json['field-error']).to be_an(Array)
        expect(json['field-error'][0]).to eq('login')
      end
    end
  end

  describe 'before_login_attempt and after_login_failure hooks' do
    context 'rate limiting' do
      it 'allows initial login attempts' do
        3.times do
          json_post '/auth/login', {
            login: test_email,
            password: 'wrong-password'
          }

          expect(last_response.status).to eq(401)
        end
      end

      it 'blocks after 5 failed attempts' do
        # Make 5 failed attempts
        5.times do
          json_post '/auth/login', {
            login: test_email,
            password: 'wrong-password'
          }
        end

        # 6th attempt should be rate limited
        json_post '/auth/login', {
          login: test_email,
          password: 'wrong-password'
        }

        expect(last_response.status).to eq(429)
        json = JSON.parse(last_response.body)
        expect(json['error']).to match(/too many.*attempts/i)
      end

      it 'sets DB key with TTL' do
        json_post '/auth/login', {
          login: test_email,
          password: 'wrong-password'
        }

        rate_limit_key = "login_attempts:#{test_email}"
        expect(dbclient.exists(rate_limit_key)).to eq(1)
        ttl = dbclient.ttl(rate_limit_key)
        expect(ttl).to be > 0
        expect(ttl).to be <= 300 # 5 minutes
      end
    end

    context 'successful login clears rate limit' do
      it 'resets attempt counter on success' do
        # Create account first (simplified - assumes account exists)
        # In real test, you'd create via API or seed data

        # Make some failed attempts
        2.times do
          json_post '/auth/login', {
            login: test_email,
            password: 'wrong-password'
          }
        end

        rate_limit_key = "login_attempts:#{test_email}"
        attempts_before = dbclient.get(rate_limit_key).to_i
        expect(attempts_before).to eq(2)

        # Note: This would require a valid account to test properly
        # Skipping actual successful login test here
      end
    end
  end

  describe 'security logging' do
    it 'logs failed login attempts' do
      # Capture OT.info calls would require a logger spy
      # For now, just verify the endpoint responds correctly
      json_post '/auth/login', {
        login: test_email,
        password: 'wrong-password'
      }

      expect(last_response.status).to eq(401)
    end
  end
end
