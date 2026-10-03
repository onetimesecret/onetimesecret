# spec/integration/full/remember_me_spec.rb
#
# frozen_string_literal: true

# "Remember me" in full mode, through the whole stack: the login's
# `remember-me` parameter, the stamp on the active-session row and in the
# Rack session, the blob TTL and cookie lifetime the session store derives
# from it, the gate's and the sessions-page sweep's deadline rule, and the
# sessions list's remember_enabled flag.
#
# Deadlines are driven the way passive_verification_spec.rb drives them: the
# stored timestamps move, never Time.now, because the gate decides in the
# database's clock.
#
# LANE: spec:integration:full (bundle exec rake spec:integration:full).

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Remember me: a fixed 14-day session (full mode)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Remember-Test1234!' }
  let(:gate) { Onetime::ActiveSessionGate }
  let(:duration) { Onetime::RememberMe::DURATION }

  before do
    clear_cookies
    @matrix_email   = "remember-me-#{SecureRandom.hex(10)}@example.com"
    @matrix_account = create_verified_account(db: test_db, email: @matrix_email, password: matrix_password)
  end

  def login!(**extra)
    post_json '/auth/login', { login: @matrix_email, password: matrix_password }.merge(extra)
    raise "login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200
  end

  def session_cookie_header
    Array(last_response.headers['set-cookie']).join("\n").split("\n").find { |c| c.start_with?('onetime.session=') }
  end

  def blob_ttl
    Familia.dbclient.ttl(session_store.find_key(Familia.dbclient, current_session_id))
  end

  def current_row
    active_session_rows.where(session_id: session_blob.fetch('active_session_id_hmac')).first
  end

  def account_request
    get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.status
  end

  describe 'an unchecked login' do
    it 'is the default rolling session: no stamp, 24h blob, no Max-Age', :aggregate_failures do
      login!('remember-me' => false)

      expect(session_blob).not_to have_key('remember_until')
      expect(current_row[:remember_until]).to be_nil
      expect(blob_ttl).to be_between(1, 86_400)
      expect(session_cookie_header).not_to match(/max-age/i)
    end
  end

  describe 'a checked login' do
    it 'stamps the Rack session and the active-session row, and fixes the blob and cookie at 14 days', :aggregate_failures do
      before_login = Time.now.to_i
      login!('remember-me' => true)

      remember_until = session_blob.fetch('remember_until')
      expect(remember_until).to be_between(before_login + duration, Time.now.to_i + duration)
      expect(current_row[:remember_until]).not_to be_nil

      expect(blob_ttl).to be > 86_400
      expect(blob_ttl).to be <= duration
      max_age = session_cookie_header[/max-age=(\d+)/i, 1].to_i
      expect(max_age).to be > 86_400
      expect(max_age).to be <= duration
      expect(session_cookie_header).to match(/expires=/i)
    end

    it 'is not extended by later activity', :aggregate_failures do
      login!('remember-me' => true)
      remember_until = session_blob.fetch('remember_until')
      Familia.dbclient.expire(session_store.find_key(Familia.dbclient, current_session_id), duration - 3600)

      # The server computes the TTL and Max-Age from its own clock during the
      # request. Bound them by the clock reading taken before the request so
      # a second ticking between the request and the assertion cannot make
      # the bound one second tighter than what the server saw.
      before_request = Time.now.to_i
      expect(account_request).to eq(200)

      expect(session_blob.fetch('remember_until')).to eq(remember_until)
      expect(blob_ttl).to be <= (remember_until - before_request)
      max_age = session_cookie_header && session_cookie_header[/max-age=(\d+)/i, 1]
      expect(max_age.to_i).to be <= (remember_until - before_request) if max_age
    end

    it 'survives idling past the inactivity deadline' do
      login!('remember-me' => true)
      idle = Time.now - (gate::INACTIVITY_DEADLINE + 3600)
      active_session_rows.update(last_use: idle, created_at: idle)

      expect(account_request).to eq(200)
    end

    it 'loses its exemption and 14-day blob once remember-me is switched off', :aggregate_failures do
      login!('remember-me' => true)
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)

      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 86_400)

      idle = Time.now - (gate::INACTIVITY_DEADLINE + 3600)
      active_session_rows.update(last_use: idle, created_at: idle)
      expect(account_request).to eq(401)
    end

    it 'is refused once remember_until has passed, and its row removed', :aggregate_failures do
      login!('remember-me' => true)
      active_session_rows.update(remember_until: Time.now - 60)

      expect(account_request).to eq(401)
      expect(activity_count).to eq(0)
    end

    # The blob's own stamp ends the session on the read (Onetime::Session#find_session),
    # before the gate ever sees it: the same rule as simple mode, so the two
    # clocks (Ruby's in the blob, the database's in the row) both fail closed.
    it 'is ended on the read once the blob\'s remember_until has passed, whatever the row says', :aggregate_failures do
      login!('remember-me' => true)
      remembered_sid = current_session_id
      rewrite_session_blob { |data| data['remember_until'] = Time.now.to_i - 60 }

      expect(account_request).to eq(401)
      expect(current_session_id).not_to eq(remembered_sid)
      expect(session_cookie_header.to_s).not_to match(/max-age/i)
    end

    it 'is still subject to the lifetime deadline' do
      login!('remember-me' => true)
      active_session_rows.update(created_at: Time.now - (gate::DEFAULT_LIFETIME_DEADLINE + 60))

      expect(account_request).to eq(401)
    end

    # The stamp runs inside Rodauth's login transaction. A failing statement
    # there must cost only the stamp: on PostgreSQL an unconfined failure
    # aborts the transaction and takes the active-session row with it. Runs
    # on PostgreSQL in the full-pg-agnostic lane.
    it 'falls back to a default session when the row stamp fails', :aggregate_failures do
      # The stamp's value becomes a column that does not exist, so the
      # database itself rejects the UPDATE (and PostgreSQL aborts the
      # enclosing transaction, as it would on a timeout or a lock error).
      allow(Sequel).to receive(:date_add).and_call_original
      allow(Sequel).to receive(:date_add)
        .with(Sequel::CURRENT_TIMESTAMP, seconds: duration)
        .and_return(Sequel.lit('remember_me_spec_no_such_column'))

      login!('remember-me' => true)

      expect(session_blob).not_to have_key('remember_until')
      expect(current_row).not_to be_nil
      expect(current_row[:remember_until]).to be_nil
      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 86_400)
    end

    it 'ends at logout like any other session', :aggregate_failures do
      login!('remember-me' => true)
      post_json '/auth/logout', {}

      expect(activity_count).to eq(0)
      expect(account_request).to eq(401)
    end
  end

  describe 'parameter strictness' do
    [true, 'true', '1', 'on'].each do |value|
      it "remembers for #{value.inspect}" do
        login!('remember-me' => value)
        expect(session_blob).to have_key('remember_until')
      end
    end

    [false, 'false', '0', 'yes', 'TRUE', 1, '', nil].each do |value|
      it "does not remember for #{value.inspect}" do
        login!('remember-me' => value)
        expect(session_blob).not_to have_key('remember_until')
        expect(current_row[:remember_until]).to be_nil
      end
    end

    it 'does not remember when the parameter is absent' do
      login!
      expect(session_blob).not_to have_key('remember_until')
    end

    it 'does not remember while remember-me is switched off, whatever the parameter says', :aggregate_failures do
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)
      login!('remember-me' => true)

      expect(session_blob).not_to have_key('remember_until')
      expect(current_row[:remember_until]).to be_nil
      expect(blob_ttl).to be_between(1, 86_400)
      expect(session_cookie_header.to_s).not_to match(/max-age/i)
    end
  end

  # The sessions page, opened on a second device, runs Rodauth's sweep
  # (remove_inactive_sessions). It must apply the gate's rule, not Rodauth's,
  # or it would delete a remembered row the first device is still entitled
  # to.
  describe 'the sessions page' do
    it 'keeps an idle remembered row, sweeps an idle default one, and flags remember_enabled', :aggregate_failures do
      login!('remember-me' => true)
      remembered_sid  = current_session_id
      remembered_hmac = session_blob.fetch('active_session_id_hmac')

      clear_cookies
      login!('remember-me' => false)
      default_hmac = session_blob.fetch('active_session_id_hmac')

      idle = Time.now - (gate::INACTIVITY_DEADLINE + 3600)
      active_session_rows.where(session_id: remembered_hmac).update(last_use: idle, created_at: idle)
      test_db[:account_active_session_keys].insert(
        account_id: @matrix_account[:id], session_id: 'idle-default-row', last_use: idle, created_at: idle,
      )

      get_json '/auth/active-sessions'
      expect(last_response.status).to eq(200), last_response.body
      listed = JSON.parse(last_response.body).fetch('sessions').to_h { |s| [s['id'], s] }

      expect(listed.keys).to contain_exactly(remembered_hmac, default_hmac)
      expect(listed.fetch(remembered_hmac)['remember_enabled']).to be(true)
      expect(listed.fetch(default_hmac)['remember_enabled']).to be(false)
      expect(active_session_rows.select_map(:session_id)).to contain_exactly(remembered_hmac, default_hmac)

      clear_cookies
      set_cookie "onetime.session=#{remembered_sid}"
      expect(account_request).to eq(200)
    end

    # Revoking refuses the other device's Rack session but leaves its blob
    # in Redis. Its next request drops the remember deadline, so the blob
    # and cookie fall back to the default lifetime instead of living on to
    # remember_until.
    it 'returns a revoked remembered session to the default lifetime', :aggregate_failures do
      login!('remember-me' => true)
      remembered_sid  = current_session_id
      remembered_hmac = session_blob.fetch('active_session_id_hmac')

      clear_cookies
      login!
      delete_json "/auth/active-sessions/#{remembered_hmac}"
      expect(last_response.status).to eq(200), last_response.body

      clear_cookies
      set_cookie "onetime.session=#{remembered_sid}"
      expect(account_request).to eq(401)

      expect(current_session_id).to eq(remembered_sid)
      expect(session_blob).not_to have_key('remember_until')
      expect(blob_ttl).to be_between(1, 86_400)
    end

    it 'reports remember_enabled false once remember_until has passed' do
      login!('remember-me' => true)
      hmac = session_blob.fetch('active_session_id_hmac')
      remembered_sid = current_session_id

      clear_cookies
      login!
      active_session_rows.where(session_id: hmac).update(remember_until: Time.now - 60)

      get_json '/auth/active-sessions'
      listed = JSON.parse(last_response.body).fetch('sessions').map { |s| s['id'] }

      # The sweep removes it outright; nothing lists a lapsed remembered row.
      expect(listed).not_to include(hmac)
      expect(remembered_sid).not_to be_nil
    end
  end

  it 'no longer mounts Rodauth\'s remember route' do
    login!
    post_json '/auth/remember', { remember: 'remember' }

    expect(last_response.status).to eq(404)
    expect(rack_mock_session.cookie_jar['_remember']).to be_nil
    expect(test_db[:account_remember_keys].where(id: @matrix_account[:id]).count).to eq(0)
  end
end
