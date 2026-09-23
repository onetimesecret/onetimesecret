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

  describe 'a remember_until the store cannot honour falls back to the default' do
    [['in the past', -> { Time.now.to_i - 60 }], ['not an integer', -> { (Time.now.to_i + 86_400 * 7).to_s }]].each do |label, value|
      it label, :aggregate_failures do
        login!
        rewrite_session_blob { |data| data['remember_until'] = value.call }

        expect(account_request).to eq(200)
        expect(blob_ttl).to be_between(1, 86_400)
        expect(session_cookie_header.to_s).not_to match(/max-age/i)
      end
    end

    it 'caps a deadline beyond 14 days at 14 days' do
      login!
      rewrite_session_blob { |data| data['remember_until'] = Time.now.to_i + (duration * 10) }

      expect(account_request).to eq(200)
      expect(blob_ttl).to be <= duration
    end
  end

  it 'ends at logout, and the next anonymous cookie is a default one', :aggregate_failures do
    login!('remember-me' => true)
    get '/logout'

    expect(account_request).to eq(401)
    expect(session_cookie_header.to_s).not_to match(/max-age/i)
  end
end
