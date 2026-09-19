# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Auth router customer-session evaluator', type: :integration do
  include_context 'auth_rack_test'

  let(:password) { 'Evaluator-Test1234!' }
  let(:email) { "auth-evaluator-#{SecureRandom.hex(8)}@example.com" }

  before do
    @account = create_verified_account(db: test_db, email: email, password: password)
    post_json '/auth/login', { login: email, password: password }
    raise "login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200

    @customer = Onetime::Customer.find_by_extid(session_blob.fetch('external_id'))
    raise 'login did not resolve a Customer' unless @customer

    allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate).and_call_original
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
  end

  it 'uses the shared authenticated verdict for an available /auth account request' do
    # The router forgets the env memo in an `ensure` after r.rodauth, so the
    # verdict is captured where the router obtains it, not read back from
    # last_request.env.
    reasons = []
    allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap { |verdict| reasons << verdict.reason }
    end

    get_json '/auth/account'

    expect(last_response.status).to eq(200), last_response.body
    expect(reasons).not_to be_empty
    expect(reasons).to all(eq(:authenticated))
    expect(last_request.env).not_to have_key(Onetime::CustomerSessionEvaluator::ENV_KEY)
  end

  it 'destroys a revoked session and retains the established 401 JSON response' do
    sid = current_session_id
    active_session_rows.delete

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to eq(
      'error' => 'web.auth.security.session_expired',
      'success' => false,
      'code' => 'active_session_revoked',
      'code_scope' => 'customer_session',
    )
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
    expect(Onetime::CustomerSessionEvaluator).to have_received(:evaluate).at_least(:once)
  end

  it 'destroys a revoked session even when suspension rejects before the shared active-session check' do
    sid = current_session_id
    @customer.suspended = 'true'
    @customer.save
    active_session_rows.delete

    get_json '/auth/account'

    expect_revoked_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'destroys a revoked session even when stale credentials reject before the shared active-session check' do
    sid       = current_session_id
    watermark = Familia.now.to_i
    @customer.last_password_update!(watermark)
    rewrite_session_blob { |blob| blob['authenticated_at'] = watermark - 1 }
    active_session_rows.delete

    get_json '/auth/account'

    expect_revoked_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'destroys a revoked session even when the customer is missing' do
    sid = current_session_id
    active_session_rows.delete
    allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)

    get_json '/auth/account'

    expect_revoked_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'destroys a revoked session even when the customer store is unavailable' do
    sid = current_session_id
    active_session_rows.delete
    allow(Onetime::Customer).to receive(:find_by_extid)
      .and_raise(Redis::ConnectionError, 'customer store unavailable')

    get_json '/auth/account'

    expect_revoked_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'refuses a non-revoked suspended session without exposing account data' do
    sid = current_session_id
    @customer.suspended = 'true'
    @customer.save

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect_session_failure_code('account_suspended', 'customer_session')
    expect_no_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'refuses a non-revoked stale-credential session without exposing account data' do
    sid       = current_session_id
    watermark = Familia.now.to_i
    @customer.last_password_update!(watermark)
    rewrite_session_blob { |blob| blob['authenticated_at'] = watermark - 1 }

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect_session_failure_code('stale_credentials', 'customer_session')
    expect_no_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'preserves and refuses an MFA-pending session without exposing account data' do
    sid = current_session_id
    mark_session_mfa_pending

    get_json '/auth/account'

    expect_mfa_pending_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
  end

  it 'does not invoke an account mutation for an MFA-pending session' do
    sid = current_session_id
    mark_session_mfa_pending
    expect_any_instance_of(Auth::Config).not_to receive(:remove_all_active_sessions_except_current)

    post_json '/auth/remove-all-active-sessions', {}

    expect_mfa_pending_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
  end

  it 'refuses anonymous account-lifecycle routes for an MFA-pending session and preserves it' do
    sid = current_session_id
    mark_session_mfa_pending

    post_json '/auth/reset-password-request', { login: email }

    expect_mfa_pending_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
  end

  it 'destroys an MFA-pending session whose active-session row was revoked' do
    sid = current_session_id
    mark_session_mfa_pending
    active_session_rows.delete

    get_json '/auth/account'

    expect_revoked_refusal_without_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  # An autologin session (verify-account, reset-password, create-account):
  # Rodauth's login_session ran, so it carries account_id, the join key and
  # the surface marker, but after_login never did, so SyncSession never wrote
  # the app-level `authenticated` flag. Rodauth authorizes it from account_id
  # alone.
  describe 'a Rodauth-logged-in session without the authenticated flag' do
    before { rewrite_session_blob { |blob| blob.delete('authenticated') } }

    it 'is served by Rodauth and not destroyed while its active-session row is live' do
      sid = current_session_id

      get_json '/auth/account'

      expect(last_response.status).to eq(200), last_response.body
      expect(JSON.parse(last_response.body)).to include('id' => @account[:id], 'email' => email)
      expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
      expect(session_blob).to include('account_id' => @account[:id])
    end

    it 'is destroyed and refused without account data once its active-session row is revoked' do
      sid = current_session_id
      active_session_rows.delete

      get_json '/auth/account'

      expect_revoked_refusal_without_account_data
      expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :active_session_revoked,
        hash_including(path: '/account', outcome: :refused),
      )
    end

    it 'cannot change the password once its active-session row is revoked' do
      sid = current_session_id
      active_session_rows.delete

      post_json '/auth/change-password',
        { password: password, 'new-password': 'Replaced-Test1234!', 'password-confirm': 'Replaced-Test1234!' }

      expect_revoked_refusal_without_account_data
      expect(session_store.find_key(Familia.dbclient, sid)).to be_nil

      clear_cookies
      post_json '/auth/login', { login: email, password: password }
      expect(last_response.status).to eq(200), 'the original password must still sign in'
    end

    it 'is destroyed and refused on a surface other than the one it was established on' do
      sid = current_session_id
      rewrite_session_blob do |blob|
        blob[Onetime::SessionSurface::KEY] = { 'kind' => 'custom', 'id' => 'other-domain' }
      end

      get_json '/auth/account'

      expect_revoked_refusal_without_account_data
      expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :session_surface_mismatch,
        hash_including(path: '/account', outcome: :refused),
      )
    end

    it 'is preserved and refused while the authentication database cannot verify its row' do
      sid = current_session_id
      allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

      get_json '/auth/account'

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)['error_type']).to eq('SessionUnverified')
      expect_session_failure_code('active_session_unavailable', 'verification_unavailable')
      expect_no_account_data
      expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
    end
  end

  it 'preserves and refuses a non-revoked session when the customer store is unavailable' do
    sid = current_session_id
    allow(Onetime::Customer).to receive(:find_by_extid)
      .and_raise(Redis::ConnectionError, 'customer store unavailable')

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to eq(
      'error' => 'Session could not be verified; try again',
      'error_type' => 'SessionUnverified',
      'code' => 'customer_unavailable',
      'code_scope' => 'verification_unavailable',
    )
    expect_no_account_data
    expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil
  end

  it 'keeps logout available when the customer store is unavailable' do
    sid = current_session_id
    allow(Onetime::Customer).to receive(:find_by_extid)
      .and_raise(Redis::ConnectionError, 'customer store unavailable')

    post_json '/auth/logout', {}

    expect(last_response.status).to eq(200), last_response.body
    expect(JSON.parse(last_response.body)).to include(
      'success' => true,
      'message' => 'web.auth.logout.success',
    )
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'clears stale credentials but continues an anonymous Rodauth recovery route' do
    sid       = current_session_id
    watermark = Familia.now.to_i
    @customer.last_password_update!(watermark)
    rewrite_session_blob { |blob| blob['authenticated_at'] = watermark - 1 }

    post_json '/auth/reset-password-request', { login: email }

    expect(last_response.status).to eq(200), last_response.body
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end

  it 'clears a revoked session but continues an anonymous Rodauth credential route' do
    sid = current_session_id
    active_session_rows.delete

    post_json '/auth/reset-password-request', { login: email }

    expect(last_response.status).to eq(200), last_response.body
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
    expect(Onetime::CustomerSessionEvaluator).to have_received(:evaluate).at_least(:once)
  end

  it 'preserves an unavailable session on 401, then keeps logout available and destroys it' do
    sid = current_session_id
    allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)['error_type']).to eq('SessionUnverified')
    expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil

    post_json '/auth/logout', {}

    expect(last_response.status).to eq(200), last_response.body
    expect(JSON.parse(last_response.body)).to include(
      'success' => true,
      'message' => 'web.auth.logout.success',
    )
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
  end


  it 'uses the shared surface-mismatch verdict and destroys the session' do
    sid = current_session_id
    rewrite_session_blob do |blob|
      blob[Onetime::SessionSurface::KEY] = { 'kind' => 'custom', 'id' => 'other-domain' }
    end

    get_json '/auth/account'

    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)['error']).to eq('web.auth.security.session_expired')
    # The typed verdict crosses the boundary instead of collapsing into the
    # same session_expired body a revocation answers with (#4462).
    expect_session_failure_code('surface_mismatch', 'customer_session')
    expect(session_store.find_key(Familia.dbclient, sid)).to be_nil
    expect(Auth::Logging).to have_received(:log_auth_event).with(
      :session_surface_mismatch,
      hash_including(path: '/account', outcome: :refused),
    )
  end

  it 'leaves a genuinely anonymous credential route to Rodauth' do
    clear_cookies

    post_json '/auth/reset-password-request', { login: email }

    expect(last_response.status).to eq(200), last_response.body
    expect(last_response.body).not_to include('web.auth.security.session_expired')
    expect(Onetime::CustomerSessionEvaluator).to have_received(:evaluate).at_least(:once)
  end

  def current_session_id
    rack_mock_session.cookie_jar['onetime.session']
  end

  def session_store
    Onetime::Operations::Sessions::Store
  end

  def session_codec
    Onetime::SessionCodec.from_config
  end

  def session_blob
    key = session_store.find_key(Familia.dbclient, current_session_id)
    session_store.load_data(Familia.dbclient, key, codec: session_codec)
  end

  def expect_session_failure_code(code, scope)
    expect(JSON.parse(last_response.body)).to include('code' => code, 'code_scope' => scope)
  end

  def expect_revoked_refusal_without_account_data
    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to include(
      'error' => 'web.auth.security.session_expired',
      'success' => false,
    )
    expect_no_account_data
  end

  def expect_mfa_pending_refusal_without_account_data
    expect(last_response.status).to eq(401)
    expect(JSON.parse(last_response.body)).to eq(
      'error' => 'Authentication required',
      'code' => 'awaiting_mfa',
      'code_scope' => 'customer_session',
    )
    expect(last_request.env.fetch(Onetime::CustomerSessionEvaluator::ENV_KEY).reason).to eq(:awaiting_mfa)
    expect_no_account_data
  end

  def expect_no_account_data
    payload = JSON.parse(last_response.body)
    expect(payload).not_to have_key('id')
    expect(payload).not_to have_key('email')
    expect(last_response.body).not_to include(email)
    expect(last_response.body).not_to include(@customer.extid)
  end

  def mark_session_mfa_pending
    rewrite_session_blob do |blob|
      blob.delete('authenticated')
      blob['awaiting_mfa'] = true
    end
  end

  def rewrite_session_blob
    db   = Familia.dbclient
    key  = session_store.find_key(db, current_session_id)
    data = session_store.load_data(db, key, codec: session_codec)
    yield data
    db.set(key, session_codec.encode(data), keepttl: true)
  end

  def active_session_rows
    test_db[:account_active_session_keys].where(account_id: @account[:id])
  end
end
