# apps/web/auth/spec/integration/full/verify_account_autologin_session_rotation_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Verify-account autologin starts a new session id (#4466).
#
# Following the emailed verification key signs the new account in:
# verify_account_autologin? is Rodauth's default true (not overridden in
# apps/web/auth/config/features/account_management.rb), and the route calls
# autologin_session -> login_session -> update_session -> clear_session,
# which this app overrides to `session.destroy` (apps/web/auth/config/base.rb).
# These examples sign up, follow the key from the delivered email with an
# anonymous session already stored under the browser's cookie, and check the
# outcome: the signed-in session lives under a new id, the old id's blob is
# gone, and the old cookie is not signed in.
#
# "Signed in" here is Rodauth's: the autologin never fires after_login, so
# Auth::Operations::SyncSession does not write the app-level `authenticated`
# flag, and the session is served by the /auth routes (`account_id`, checked
# through Auth::SessionRecheck), not by the Otto `sessionauth` routes
# (apps/web/auth/session_recheck.rb, "Autologin sessions"). So the
# signed-in check is GET /auth/account.json.
#
# The lanes boot verify_account OFF (spec/support/auth_mode_helpers.rb
# MockAuthConfig), and Auth::Config is configured once per process. So, as in
# public_host_email_link_spec.rb, the examples run against a router subclass
# with the production verify-account modules applied, leaving the shared
# router untouched.
#
# Assertions follow spec/integration/full/active_sessions_spec.rb
# ('session rotation on HTTP signup (#4393)').
#
# RUN:
#   tests/lanes/run full-sqlite \
#     --only apps/web/auth/spec/integration/full/verify_account_autologin_session_rotation_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require 'rack/test'
require 'cgi'

RSpec.describe 'Verify-account autologin starts a new session id (#4466)', type: :integration do
  include Rack::Test::Methods

  before(:all) { boot_onetime_app }

  let(:password) { 'VerifyRotation-Password123!' }
  let(:account_email) { unique_test_email('verify-rotation') }
  let(:store) { Onetime::Operations::Sessions::Store }
  let(:db) { Familia.dbclient }

  before do
    allow(Onetime.auth_config).to receive(:verify_account_enabled?).and_return(true)
    router = Class.new(Auth::Router)
    router.plugin :rodauth do
      Auth::Config::Features::AccountManagement.configure(self)
      Auth::Config::Email::VerifyAccount.configure(self)
      Auth::Config::Hooks::Account.configure(self)
    end
    allow_any_instance_of(Auth::Application).to receive(:build_router).and_return(router) # rubocop:disable RSpec/AnyInstance
    @verify_app = build_rack_app

    # The delivery seam: the rendered verification email, as the publisher
    # would receive it.
    @delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      @delivered << email
      true
    end
  end

  after do
    Onetime::Customer.find_by_email(OT::Utils.normalize_email(account_email))&.destroy!
  rescue StandardError
    nil
  end

  def app
    @verify_app || super
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def blob_for(sid)
    key = store.find_key(db, sid)
    key && store.load_data(db, key, codec: Onetime::SessionCodec.from_config)
  end

  # Status of GET /auth/account.json (a Rodauth login-required route) for the
  # given cookie, on a fresh cookie jar so the current one is untouched.
  def rodauth_account_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/auth/account.json', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response.status
  end

  # The key from the one delivered verification email.
  def emailed_verify_key
    expect(@delivered.size).to eq(1), "expected one delivered email, got #{@delivered.size}"
    link = @delivered.first[:body].to_s[%r{https?://\S+?/verify-account\?key=\S+}]
    expect(link).not_to be_nil, 'missing /verify-account link in the delivered email'
    CGI.parse(URI.parse(link).query).fetch('key').first
  end

  def sign_up!
    clear_cookies
    csrf_json_post('/auth/create-account', login: account_email, password: password)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['next_action']).to eq('verify_email')

    account = auth_db[:accounts].where(email: OT::Utils.normalize_email(account_email)).first
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    account
  end

  it 'signs the verified account in under a new id and ends the old one', :aggregate_failures do
    account = sign_up!
    key     = emailed_verify_key

    # The anonymous session the browser holds when it follows the link,
    # stored server-side and not signed in.
    fetch_csrf_token
    old_sid = current_sid
    expect(old_sid).not_to be_nil
    expect(blob_for(old_sid)).not_to be_nil
    expect(blob_for(old_sid)['authenticated']).not_to be(true)

    csrf_json_post('/auth/verify-account', key: key)
    expect(last_response.status).to eq(200), last_response.body
    expect(auth_db[:accounts].where(id: account[:id]).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)

    new_sid = current_sid
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('account_id' => account[:id], 'autologin_type' => 'verify_account')
    expect(blob['active_session_id_hmac']).not_to be_nil

    expect(rodauth_account_status_for(new_sid)).to eq(200)
    expect(rodauth_account_status_for(old_sid)).to eq(401)
  end
end
