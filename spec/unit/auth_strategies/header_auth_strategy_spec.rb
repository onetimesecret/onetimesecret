# spec/unit/auth_strategies/header_auth_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe Onetime::Application::AuthStrategies::HeaderAuthStrategy do
  let(:strategy) { described_class.new }
  let(:base_env) do
    {
      'rack.session' => {},
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_USER_AGENT' => 'Test/1.0'
    }
  end

  describe '#authenticate' do
    context 'when required headers are missing' do
      it 'returns AuthFailure when X-Token-Subject is missing' do
        result = strategy.authenticate(base_env, nil)

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.authenticated?).to be false
        expect(result.failure_reason).to include('HEADER_MISSING')
      end

      it 'returns AuthFailure when X-Token-User-Email is missing' do
        env = base_env.merge('HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser')
        result = strategy.authenticate(env, nil)

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.authenticated?).to be false
        expect(result.failure_reason).to include('EMAIL_MISSING')
      end
    end

    context 'when valid headers are provided' do
      let(:test_email) { "oauth_#{SecureRandom.uuid}@example.com" }
      let(:valid_env) do
        base_env.merge(
          'HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser',
          'HTTP_X_TOKEN_USER_EMAIL' => test_email,
          'HTTP_X_TOKEN_USER_NAME' => 'Test User'
        )
      end

      it 'creates a new customer when email is not found' do
        # Mock Customer.find_by_email to return nil (not found)
        allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(nil)

        # Mock Customer.new and save
        mock_customer = instance_double(Onetime::Customer,
          custid: 'cust_123',
          email: test_email,
          objid: 'cust_123'
        )
        allow(Onetime::Customer).to receive(:new).with(email: test_email).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)

        allow(mock_customer).to receive(:save)

        result = strategy.authenticate(valid_env, nil)

        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.authenticated?).to be true
        expect(result.user).to eq(mock_customer)
        expect(result.auth_method).to eq('oauth_gateway')
      end

      it 'finds existing customer by email' do
        # Mock existing customer
        existing_customer = instance_double(Onetime::Customer,
          custid: 'cust_existing',
          email: test_email,
          objid: 'cust_existing'
        )
        allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(existing_customer)

        result = strategy.authenticate(valid_env, nil)

        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.authenticated?).to be true
        expect(result.user).to eq(existing_customer)
      end

      # Note: metadata tests require integration testing with real Customer model
      # Unit tests with full mocking don't properly test the metadata flow
      it 'includes provider metadata', :skip => 'Requires integration test with Redis' do
        mock_customer = instance_double(Onetime::Customer, custid: 'cust_123', email: test_email, objid: 'cust_123')
        allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(nil)
        allow(Onetime::Customer).to receive(:new).with(email: test_email).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)
        allow(mock_customer).to receive(:save)

        result = strategy.authenticate(valid_env, nil)

        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.metadata[:provider]).to eq('github.com')
        expect(result.metadata[:oauth_subject]).to eq('github.com/testuser')
        expect(result.metadata[:oauth_email]).to eq(test_email)
      end

      it 'includes standard metadata (ip, user_agent)', :skip => 'Requires integration test with Redis' do
        mock_customer = instance_double(Onetime::Customer, custid: 'cust_123', email: test_email, objid: 'cust_123')
        allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(nil)
        allow(Onetime::Customer).to receive(:new).with(email: test_email).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)
        allow(mock_customer).to receive(:save)

        result = strategy.authenticate(valid_env, nil)

        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.metadata[:ip]).to eq('127.0.0.1')
        expect(result.metadata[:user_agent]).to eq('Test/1.0')
      end
    end

    context 'provider extraction', :skip => 'Requires integration test with Redis' do
      let(:test_cases) do
        [
          ['github.com/username', 'github.com'],
          ['google.com/org/username', 'google.com'],
          ['gitlab.com/team/project/user', 'gitlab.com'],
          ['example.com', 'example.com']
        ]
      end

      it 'extracts provider correctly from various subject formats' do
        test_cases.each do |(subject, expected_provider)|
          email = "test_#{SecureRandom.uuid}@example.com"
          env = base_env.merge(
            'HTTP_X_TOKEN_SUBJECT' => subject,
            'HTTP_X_TOKEN_USER_EMAIL' => email
          )

          mock_customer = instance_double(Onetime::Customer, custid: 'cust_123', email: email, objid: 'cust_123')
          allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(nil)
          allow(Onetime::Customer).to receive(:new).with(email: email).and_return(mock_customer)
          allow(mock_customer).to receive(:verified=)
          allow(mock_customer).to receive(:save)

          result = strategy.authenticate(env, nil)

          expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
          expect(result.metadata[:provider]).to eq(expected_provider)
        end
      end
    end

    context 'when name header is optional' do
      let(:test_email) { "no_name_#{SecureRandom.uuid}@example.com" }
      let(:env_no_name) do
        base_env.merge(
          'HTTP_X_TOKEN_SUBJECT' => 'github.com/noname',
          'HTTP_X_TOKEN_USER_EMAIL' => test_email
        )
      end

      it 'creates customer without name' do
        # Mock customer creation without name
        mock_customer = instance_double(Onetime::Customer, custid: 'cust_123', email: test_email, objid: 'cust_123')
        allow(Onetime::Customer).to receive(:find_by_email).with(test_email).and_return(nil)
        allow(Onetime::Customer).to receive(:new).with(email: test_email).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)
        allow(mock_customer).to receive(:save)

        result = strategy.authenticate(env_no_name, nil)

        expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
        expect(result.authenticated?).to be true
        expect(result.user).to eq(mock_customer)
      end
    end

    context 'error handling' do
      it 'returns AuthFailure when customer creation fails' do
        email = "fail_#{SecureRandom.uuid}@example.com"
        env = base_env.merge(
          'HTTP_X_TOKEN_SUBJECT' => 'github.com/testuser',
          'HTTP_X_TOKEN_USER_EMAIL' => email
        )

        # Mock customer find/create to raise error
        allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(nil)
        mock_customer = instance_double(Onetime::Customer, objid: 'cust_fail')
        allow(Onetime::Customer).to receive(:new).with(email: email).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)

        allow(mock_customer).to receive(:save).and_raise(StandardError, 'Save failed')

        result = strategy.authenticate(env, nil)

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.failure_reason).to include('CUSTOMER_CREATE_FAILED')
      end

      it 'always returns a result (never raises)' do
        malformed_env = base_env.merge(
          'HTTP_X_TOKEN_SUBJECT' => 'malformed',
          'HTTP_X_TOKEN_USER_EMAIL' => 'not-an-email'
        )

        # Mock to ensure we always get a result
        mock_customer = instance_double(Onetime::Customer, custid: 'cust_123', email: 'not-an-email', objid: 'cust_123')
        allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
        allow(Onetime::Customer).to receive(:new).and_return(mock_customer)
        allow(mock_customer).to receive(:verified=)

        allow(mock_customer).to receive(:save)

        expect {
          result = strategy.authenticate(malformed_env, nil)
          expect(result).to be_a(Otto::Security::Authentication::StrategyResult).or(
            be_a(Otto::Security::Authentication::AuthFailure)
          )
        }.not_to raise_error
      end
    end
  end

  describe 'security considerations' do
    it 'has correct auth method name' do
      expect(described_class.instance_variable_get(:@auth_method_name)).to eq('oauth_gateway')
    end

    it 'documents header stripping requirement in class comment' do
      source_file_path = File.expand_path('../../../lib/onetime/application/auth_strategies.rb', __dir__)
      source_file = File.read(source_file_path)
      expect(source_file).to include('Caddy')
      expect(source_file).to include('X-Token-*')
    end
  end
end
