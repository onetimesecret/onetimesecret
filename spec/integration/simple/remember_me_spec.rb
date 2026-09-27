# spec/integration/simple/remember_me_spec.rb
#
# frozen_string_literal: true

# "Remember me" in simple mode, where the Rack session is the only record:
# Core::Controllers::Authentication stamps `remember_until` and
# Onetime::Session gives the blob and the cookie that fixed lifetime. The
# same store behaviour serves full mode (spec/integration/full/remember_me_spec.rb).

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Remember me: a fixed 14-day session (simple mode)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Remember-Simple1234!' }
  let(:duration) { Onetime::RememberMe::DURATION }
  let(:app) do
    @simple_remember_app ||= begin
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
    @matrix_email    = "remember-simple-#{SecureRandom.hex(10)}@example.com"
    @matrix_customer = Onetime::Customer.new(email: @matrix_email)
    @matrix_customer.update_passphrase(matrix_password)
    @matrix_customer.verified = 'true'
    @matrix_customer.save
  end

  def login!(**extra)
    post_json '/auth/login', { login: @matrix_email, password: matrix_password }.merge(extra)
    raise "login failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200
  end

  def session_cookie_header
    Array(last_response.headers['set-cookie']).join("\n").split("\n").find { |c| c.start_with?('onetime.session=') }
  end

  def blob_key
    session_store.find_key(Familia.dbclient, current_session_id)
  end

  def blob_ttl
    Familia.dbclient.ttl(blob_key)
  end

  def account_request
    get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.status
  end

  it 'leaves an unchecked login on the rolling 24 hours', :aggregate_failures do
    login!('remember-me' => false)

    expect(session_blob).not_to have_key('remember_until')
    expect(blob_ttl).to be_between(1, 86_400)
    expect(session_cookie_header).not_to match(/max-age/i)
  end

  it 'gives a checked login a blob and cookie that end 14 days from sign-in', :aggregate_failures do
    login!('remember-me' => true)

    expect(session_blob.fetch('remember_until')).to be_within(5).of(Time.now.to_i + duration)
    expect(blob_ttl).to be > 86_400
    expect(blob_ttl).to be <= duration
    expect(session_cookie_header[/max-age=(\d+)/i, 1].to_i).to be_within(5).of(duration)
  end

  it 'does not extend a remembered session on activity' do
    login!('remember-me' => true)
    Familia.dbclient.expire(blob_key, duration - 7200)
    remember_until = session_blob.fetch('remember_until')

    expect(account_request).to eq(200)
    expect(blob_ttl).to be <= (remember_until - Time.now.to_i)
  end

  it 'ignores the parameter for anything but the truthy values' do
    login!('remember-me' => 'yes')
    expect(session_blob).not_to have_key('remember_until')
  end

  # The deadlines are decided when the session is READ (Onetime::Session#find_session),
  # not by the blob's TTL: a session past one is ended like a logout ends it,
  # whatever TTL the key still had, so no write can hand it a rolling lifetime.
  describe 'the absolute deadlines' do
    def sid_and_blob_key
      [current_session_id, blob_key]
    end

    it 'ends a session whose remember_until has passed, and never lets it become a rolling one', :aggregate_failures do
      login!('remember-me' => true)
      remembered_sid, remembered_key = sid_and_blob_key
      rewrite_session_blob { |data| data['remember_until'] = Time.now.to_i - 60 }

      expect(account_request).to eq(401)
      expect(current_session_id).not_to eq(remembered_sid)
      expect(Familia.dbclient.exists?(remembered_key)).to be(false)
      expect(session_cookie_header.to_s).not_to match(/max-age/i)

      # And it stays ended: the old cookie does not come back as a default session.
      rack_mock_session.cookie_jar['onetime.session'] = remembered_sid
      expect(account_request).to eq(401)
    end

    it 'ends a session signed in more than 30 days ago, remembered or not', :aggregate_failures do
      login!
      old_sid, old_key = sid_and_blob_key
      rewrite_session_blob { |data| data['authenticated_at'] = Time.now.to_i - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE + 86_400) }

      expect(account_request).to eq(401)
      expect(current_session_id).not_to eq(old_sid)
      expect(Familia.dbclient.exists?(old_key)).to be(false)
    end

    it 'keeps a session signed in 29 days ago, on a blob TTL that ends by the 30th', :aggregate_failures do
      login!
      rewrite_session_blob { |data| data['authenticated_at'] = Time.now.to_i - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE - 86_400) }

      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 86_400)
    end

    it 'sizes the blob to the lifetime deadline when that is nearer than the rolling 24 hours' do
      login!
      rewrite_session_blob { |data| data['authenticated_at'] = Time.now.to_i - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE - 3600) }

      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 3600)
    end

    it 'ends a remembered session at the lifetime deadline too' do
      login!('remember-me' => true)
      rewrite_session_blob { |data| data['authenticated_at'] = Time.now.to_i - (Onetime::ActiveSessionGate::LIFETIME_DEADLINE + 60) }

      expect(account_request).to eq(401)
    end
  end

  describe 'a remember_until the store cannot honour falls back to the default' do
    it 'not an integer', :aggregate_failures do
      login!
      rewrite_session_blob { |data| data['remember_until'] = (Time.now.to_i + 86_400 * 7).to_s }

      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 86_400)
      expect(session_cookie_header.to_s).not_to match(/max-age/i)
    end

    it 'caps a deadline beyond 14 days at 14 days' do
      login!
      rewrite_session_blob { |data| data['remember_until'] = Time.now.to_i + (duration * 10) }

      expect(account_request).to eq(200)
      expect(blob_ttl).to be <= duration
    end
  end

  describe 'with AUTH_REMEMBER_ME_ENABLED=false' do
    it 'ignores the parameter' do
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)
      login!('remember-me' => true)

      expect(session_blob).not_to have_key('remember_until')
    end

    it 'returns a session remembered before the switch to the default lifetime', :aggregate_failures do
      login!('remember-me' => true)
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)

      expect(account_request).to eq(200)
      expect(blob_ttl).to be_between(1, 86_400)
      expect(session_cookie_header.to_s).not_to match(/max-age/i)
    end
  end

  it 'ends at logout, and the next anonymous cookie is a default one', :aggregate_failures do
    login!('remember-me' => true)
    get '/logout'

    expect(account_request).to eq(401)
    expect(session_cookie_header.to_s).not_to match(/max-age/i)
  end
end
