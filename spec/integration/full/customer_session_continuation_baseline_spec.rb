# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Customer-session rotation and continuation baseline (#4466/#4467)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Matrix-Test1234!' }

  describe 'rotation and fixation-cookie selection (#4466)' do
    it 'rotates away the anonymous SID and uses the first duplicate session cookie on the request' do
      email = "rotation-selection-#{SecureRandom.hex(10)}@example.com"
      create_verified_account(db: test_db, email: email, password: matrix_password)

      clear_cookies
      fetch_csrf_token
      pre_login_sid = current_session_id
      expect(pre_login_sid).not_to be_nil
      expect(session_store.find_key(Familia.dbclient, pre_login_sid)).not_to be_nil

      post_json '/auth/login', { login: email, password: matrix_password }
      expect(last_response.status).to eq(200), last_response.body

      authenticated_sid = current_session_id
      expect(authenticated_sid).not_to be_nil
      expect(authenticated_sid).not_to eq(pre_login_sid)
      expect(session_store.find_key(Familia.dbclient, pre_login_sid)).to be_nil
      expect(session_blob['authenticated']).to be(true)

      expect(request_with_duplicate_session_cookies(pre_login_sid, authenticated_sid)).to eq(401)
      expect(request_with_duplicate_session_cookies(authenticated_sid, pre_login_sid)).to eq(200)
    end
  end

  # #4467 pinned that Rodauth's remember credential outlived an active-session
  # revocation (nothing consumed it). The remember-me checkbox now extends the
  # session itself (Onetime::RememberMe), so there is no second credential
  # left behind: revoking the remembered session's row ends it.
  describe 'remember-me continuation revocation (#4467)' do
    it 'leaves no remember credential behind when a remembered session is revoked', :aggregate_failures do
      clear_cookies
      @matrix_email   = "remember-revoke-#{SecureRandom.hex(10)}@example.com"
      @matrix_account = create_verified_account(db: test_db, email: @matrix_email, password: matrix_password)
      post_json '/auth/login', { login: @matrix_email, password: matrix_password, 'remember-me' => true }
      expect(last_response.status).to eq(200), last_response.body
      expect(session_blob).to have_key('remember_until')

      active_session_rows.delete

      get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(401)
      expect(rack_mock_session.cookie_jar['_remember']).to be_nil
      expect(test_db[:account_remember_keys].where(id: @matrix_account[:id]).count).to eq(0)
    end
  end

  def request_with_duplicate_session_cookies(first_sid, second_sid)
    clear_cookies
    get '/api/account/', {}, {
      'HTTP_ACCEPT' => 'application/json',
      'HTTP_COOKIE' => "onetime.session=#{first_sid}; onetime.session=#{second_sid}",
    }
    last_response.status
  end
end
