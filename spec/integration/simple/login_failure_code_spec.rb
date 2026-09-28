# spec/integration/simple/login_failure_code_spec.rb
#
# frozen_string_literal: true

# The stable `code` / `code_scope` pair on the simple-mode sign-in (#4469).
# POST /auth/login is served by Core::Controllers::Authentication here (an
# Otto `noauth` route), which answers a rejected credential itself; the code
# is stashed through Core::Controllers::Base#handle_form_error and rendered by
# Onetime::Middleware::SessionFailureCode. The body it already sent is
# unchanged.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Credential failure codes on the simple-mode sign-in (#4469)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Login-Code-Simple1234!' }
  let(:app) do
    @simple_login_code_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    clear_cookies
    @matrix_email    = "login-code-simple-#{SecureRandom.hex(10)}@example.com"
    @matrix_customer = Onetime::Customer.new(email: @matrix_email)
    @matrix_customer.update_passphrase(matrix_password)
    @matrix_customer.verified = 'true'
    @matrix_customer.save
  end

  after do
    @matrix_customer&.delete!
  end

  it 'codes a wrong password as invalid_credentials in the credential scope, body otherwise unchanged' do
    post_json '/auth/login', { login: @matrix_email, password: 'not-the-password' }

    expect(last_response.status).to eq(401)
    expect(json_response).to include(
      'error' => 'Invalid email or password',
      'field-error' => %w[email invalid],
      'code' => 'invalid_credentials',
      'code_scope' => 'credential',
    )
  end

  it 'codes an unknown email with the same code (no enumeration surface beyond the message)' do
    post_json '/auth/login', { login: "nobody-#{SecureRandom.hex(6)}@example.com", password: matrix_password }

    expect(last_response.status).to eq(401)
    expect(json_response).to include('code' => 'invalid_credentials', 'code_scope' => 'credential')
  end

  it 'codes a valid password on a suspended account as suspended_credentials' do
    @matrix_customer.suspended = 'true'
    @matrix_customer.save

    post_json '/auth/login', { login: @matrix_email, password: matrix_password }

    expect(last_response.status).to eq(401)
    expect(json_response).to include(
      'field-error' => %w[email suspended],
      'code' => 'suspended_credentials',
      'code_scope' => 'credential',
    )
  end

  it 'carries no code on a successful login' do
    post_json '/auth/login', { login: @matrix_email, password: matrix_password }

    expect(last_response.status).to eq(200), last_response.body
    expect(json_response).not_to have_key('code')
  end
end
