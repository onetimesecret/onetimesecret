# spec/integration/full/auth_credential_failure_code_spec.rb
#
# frozen_string_literal: true

# The stable `code` / `code_scope` pair on the /auth surface's own refusals
# (#4469): a rejected login and a rejected password confirmation carry
# `invalid_credentials` in the `credential` scope, a login-required refusal to
# an anonymous request carries the session reason the Otto surfaces answer
# with, and every existing field, status and side effect is unchanged.
#
# The pair reaches the body through one seam: Rodauth's set_error_reason
# (config/overrides/failure_code.rb, Auth::CredentialFailureCode) and the
# router's anonymous stash, rendered by Onetime::Middleware::SessionFailureCode.

require 'spec_helper'

RSpec.describe 'Credential failure codes on /auth (#4469)', type: :integration do
  include_context 'auth_rack_test'

  let(:password) { 'Credential-Code1234!' }
  let(:email) { "credential-code-#{SecureRandom.hex(8)}@example.com" }

  before do
    skip 'requires full auth mode' unless Onetime.auth_config.full_enabled?
    @account = create_verified_account(db: test_db, email: email, password: password)
  end

  def expect_code(code, scope)
    body = json_response
    expect(body['code']).to eq(code), body.inspect
    expect(body['code_scope']).to eq(scope), body.inspect
  end

  describe 'POST /auth/login' do
    it 'codes a wrong password as invalid_credentials in the credential scope, body otherwise unchanged' do
      post_json '/auth/login', { login: email, password: 'not-the-password' }

      expect(last_response.status).to eq(401)
      expect_code('invalid_credentials', 'credential')
      expect(json_response).to include('error' => a_kind_of(String), 'field-error' => ['password', 'invalid password'])
    end

    it 'codes an unknown login with the same code (no enumeration surface beyond the message)' do
      post_json '/auth/login', { login: "nobody-#{SecureRandom.hex(6)}@example.com", password: password }

      expect(last_response.status).to eq(401)
      expect_code('invalid_credentials', 'credential')
    end

    it 'carries no code on a successful login' do
      post_json '/auth/login', { login: email, password: password }

      expect(last_response.status).to eq(200), last_response.body
      expect(json_response).not_to have_key('code')
      expect(json_response).not_to have_key('code_scope')
    end
  end

  describe 'a login-required route reached without a session' do
    it 'codes a custom /auth route refusal with the session reason' do
      get_json '/auth/account'

      expect(last_response.status).to eq(401)
      expect(json_response['error']).to eq('Authentication required')
      expect(json_response['code']).to eq('session_missing').or eq('not_authenticated')
      expect(json_response['code_scope']).to eq('customer_session')
    end

    it "codes Rodauth's login_required refusal with the session reason" do
      post_json '/auth/change-password',
        { password: password, 'new-password': 'Replaced-Test1234!', 'password-confirm': 'Replaced-Test1234!' }

      expect(last_response.status).to eq(401)
      expect(json_response['code']).to eq('session_missing').or eq('not_authenticated')
      expect(json_response['code_scope']).to eq('customer_session')
    end
  end

  describe 'a password confirmation on an account route' do
    before do
      post_json '/auth/login', { login: email, password: password }
      raise "login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200
    end

    it 'codes a wrong current password as invalid_credentials, leaving the session intact' do
      post_json '/auth/change-password',
        { password: 'not-the-password', 'new-password': 'Replaced-Test1234!', 'password-confirm': 'Replaced-Test1234!' }

      expect(last_response.status).to eq(401)
      expect_code('invalid_credentials', 'credential')

      get_json '/auth/account'
      expect(last_response.status).to eq(200), 'a rejected confirmation must not end the session'
    end
  end
end
