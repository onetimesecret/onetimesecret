# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Customer-session rotation and continuation baseline (#4466/#4467)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Matrix-Test1234!' }

  # A request that carries the session cookie twice is refused in either
  # order (Onetime::Middleware::CookieTossing, site.middleware.cookie_tossing,
  # on in spec/config.test.yaml as in the defaults). The baseline recorded
  # before #4466 was first-wins; the refusal is the observable outcome
  # asserted here, whatever the middleware answers with.
  describe 'rotation and fixation-cookie refusal (#4466)' do
    it 'rotates away the anonymous SID and refuses duplicate session cookies in either order' do
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

      expect(request_with_duplicate_session_cookies(pre_login_sid, authenticated_sid)).to eq(403)
      expect(request_with_duplicate_session_cookies(authenticated_sid, pre_login_sid)).to eq(403)

      # The one cookie on its own still works: the refusal is about the
      # duplicate, not the session.
      expect(request_with_session_cookie(authenticated_sid)).to eq(200)
    end

    # The refusal expires every copy of the cookie it can reach. A session
    # Set-Cookie on the same response would come after those clears, so the
    # browser would keep its value as the host cookie. When the first cookie
    # names a live session (a planted cookie sorts first with a longer Path),
    # that session would outlive the refusal meant to remove it.
    it 'answers a duplicate with clears only, never a session cookie value', :aggregate_failures do
      email = "tossing-reissue-#{SecureRandom.hex(10)}@example.com"
      create_verified_account(db: test_db, email: email, password: matrix_password)

      clear_cookies
      post_json '/auth/login', { login: email, password: matrix_password }
      expect(last_response.status).to eq(200), last_response.body
      planted_sid = current_session_id
      expect(session_blob['authenticated']).to be(true)

      clear_cookies
      fetch_csrf_token
      own_sid = current_session_id
      expect(own_sid).not_to be_nil

      [[planted_sid, own_sid], [own_sid, planted_sid]].each do |first_sid, second_sid|
        expect(request_with_duplicate_session_cookies(first_sid, second_sid)).to eq(403)
        values = session_set_cookie_values(last_response)
        expect(values).not_to be_empty
        expect(values.uniq).to eq([''])
      end
    end
  end

  # The CSRF exemption for /api/ requests is keyed on the authenticated
  # session (Onetime::Middleware::Registry, AuthenticityToken allow_if). On a
  # session-authenticated request an Authorization header does not change
  # which identity answers: `sessionauth` runs first on every chain that has
  # it, so the session is used and the header is never read.
  describe 'CSRF on a session-authenticated API request carrying Basic credentials' do
    it 'requires the token even when the request carries Authorization: Basic', :aggregate_failures do
      email   = "csrf-basic-#{SecureRandom.hex(10)}@example.com"
      account = create_verified_account(db: test_db, email: email, password: matrix_password)

      clear_cookies
      post_json '/auth/login', { login: email, password: matrix_password }
      expect(last_response.status).to eq(200), last_response.body
      extid      = test_db[:accounts].where(id: account[:id]).get(:external_id)
      preference = Onetime::Customer.find_by_extid(extid).notify_on_reveal
      update     = { field: 'notify_on_reveal', value: (!preference).to_s }.to_json
      headers    = {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('nobody@example.com:not-a-key')}",
      }

      post '/api/account/update-notification-preference', update, headers
      expect(last_response.status).to eq(403)
      expect(last_request.env[Onetime::Middleware::InstrumentedAuthenticityToken::REJECTION_ENV_KEY]).to be(true)
      expect(Onetime::Customer.find_by_extid(extid).notify_on_reveal).to eq(preference)

      # With the token, the session answers and the header is not read.
      token = fetch_csrf_token
      post '/api/account/update-notification-preference', update, headers.merge('HTTP_X_CSRF_TOKEN' => token)
      expect(last_response.status).to eq(200), last_response.body
      expect(Onetime::Customer.find_by_extid(extid).notify_on_reveal).to eq((!preference).to_s)
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
    expect(last_response.body).not_to include('"cust"')
    last_response.status
  end

  def request_with_session_cookie(sid)
    clear_cookies
    get '/api/account/', {}, {
      'HTTP_ACCEPT' => 'application/json',
      'HTTP_COOKIE' => "onetime.session=#{sid}",
    }
    last_response.status
  end

  # The value of every session-cookie Set-Cookie on the response, in order;
  # '' for a clear.
  def session_set_cookie_values(response)
    Array(response.headers['set-cookie'])
      .flat_map { |value| value.split("\n") }
      .select { |line| line.start_with?('onetime.session=') }
      .map { |line| line.split(';').first.delete_prefix('onetime.session=') }
  end
end
