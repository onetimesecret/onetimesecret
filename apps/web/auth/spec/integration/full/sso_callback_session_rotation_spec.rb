# apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# SSO callback sign-in starts a new session id (#4466).
#
# The OmniAuth callback signs in through rodauth-omniauth's `login("omniauth")`
# (rodauth-omniauth 0.6.2 lib/rodauth/features/omniauth.rb), which runs
# Rodauth's login_session -> update_session -> clear_session, and this app's
# clear_session is `session.destroy` (apps/web/auth/config/base.rb). These
# examples drive the real callback, with an anonymous session already stored
# under the browser's cookie, and check the outcome: the signed-in session
# lives under a new id, the old id's blob is gone, and the old cookie is not
# signed in. Both the first sign-in (JIT account creation) and a returning
# identity are covered; they reach login_session by different branches of
# the callback.
#
# Assertions follow spec/integration/full/active_sessions_spec.rb
# ('session rotation on HTTP signup (#4393)').
#
# RUN:
#   tests/lanes/run full-sqlite \
#     --only apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'SSO callback sign-in starts a new session id (#4466)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Same forced reboot as omniauth_jit_verified_spec.rb, so provider
    # registration runs against this suite's WebMock stubs and ENV.
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)

    Onetime::Application::Registry.prepare_application_registry

    mounts = Onetime::Application::Registry.mount_mappings.keys
    raise "Auth app not mounted post-boot: #{mounts.inspect}" unless mounts.any? { |m| m.include?('/auth') }
  end

  before { enable_platform_fallback }

  after { teardown_mock_auth }

  let(:store) { Onetime::Operations::Sessions::Store }
  let(:db) { Familia.dbclient }
  let(:created_customers) { [] }

  after do
    created_customers.each do |customer|
      customer.destroy! if customer&.exists?
    rescue StandardError
      nil
    end
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def blob_for(sid)
    key = store.find_key(db, sid)
    key && store.load_data(db, key, codec: Onetime::SessionCodec.from_config)
  end

  # The anonymous session the browser holds before it signs in, stored
  # server-side (GET /auth mints the CSRF token into it).
  def anonymous_session!
    clear_cookies
    fetch_csrf_token
    sid = current_sid
    expect(sid).not_to be_nil
    expect(blob_for(sid)).not_to be_nil
    expect(blob_for(sid)['authenticated']).not_to be(true)
    sid
  end

  # Status of a session-authenticated API route for the given cookie, on a
  # fresh cookie jar so the current one is untouched.
  def account_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response.status
  end

  def callback!(email, uid)
    response = sso_callback(email: email, uid: uid)
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if response.status == 404
    expect(response.status).to eq(302), "Expected a post-login redirect, got #{response.status}: #{response.body}"
    customer = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))
    created_customers << customer if customer
    response
  end

  def expect_rotated_sign_in(old_sid, email)
    new_sid = current_sid
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    account = auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).first
    blob    = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'account_id' => account[:id])
    expect(blob['active_session_id_hmac']).not_to be_nil

    expect(account_status_for(new_sid)).to eq(200)
    expect(account_status_for(old_sid)).to eq(401)
  end

  it 'signs a first-time SSO user in under a new id (JIT account)', :aggregate_failures do
    email   = unique_test_email('sso-rotation-jit')
    uid     = "sub-#{SecureRandom.hex(8)}"
    old_sid = anonymous_session!

    callback!(email, uid)

    expect_rotated_sign_in(old_sid, email)
  end

  it 'signs a returning SSO identity in under a new id', :aggregate_failures do
    email = unique_test_email('sso-rotation-returning')
    uid   = "sub-#{SecureRandom.hex(8)}"

    # First sign-in creates the account and the identity row.
    anonymous_session!
    callback!(email, uid)
    account = auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).first
    expect(auth_db[:account_identities].where(account_id: account[:id], uid: uid).count).to eq(1)

    old_sid = anonymous_session!
    callback!(email, uid)

    expect_rotated_sign_in(old_sid, email)
  end
end
