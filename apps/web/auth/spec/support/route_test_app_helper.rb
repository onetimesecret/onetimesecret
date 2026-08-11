# apps/web/auth/spec/support/route_test_app_helper.rb
#
# frozen_string_literal: true

require 'logger'

# =============================================================================
# Mini Roda apps for route-module specs (non-integration lane)
# =============================================================================
#
# Auth::Config is one-shot per process (apps/web/auth/config.rb), so route
# modules cannot be exercised through the real Auth::Router outside the
# integration lane. This helper builds the smallest Roda + Rodauth app that can
# host a route module instead: the same plugins the router relies on (json,
# halt), a real Rodauth instance backed by RodauthTestHelper's in-memory SQLite
# database, and a test-only login route that establishes a Rodauth session
# directly (no login flow, no CSRF plumbing).
#
# The route module under test is the REAL production module — only the hosting
# app is synthetic. Session mechanics are real Rodauth: `logged_in?` /
# `session_value` read the same session key a production login writes
# (convert_session_key handles the Roda sessions plugin's string keys).
#
# Usage:
#   let(:db)  { create_test_database }
#   let(:app) do
#     build_route_test_app(
#       db: db,
#       route_module: Auth::Routes::WebauthnCredentials,
#       handler: :handle_webauthn_credentials_routes,
#     )
#   end
#   ...
#   post '/test-login', account_id: account_id  # establish session
#
module RouteTestAppHelper
  # Build a Roda app hosting a single production route module.
  #
  # @param db [Sequel::Database] test database (RodauthTestHelper.create_test_database)
  # @param route_module [Module] the Auth::Routes::* module under test
  # @param handler [Symbol] the module's handle_*_routes method
  # @param features [Array<Symbol>] Rodauth features to enable
  # @return [Class] Roda application class for Rack::Test
  def build_route_test_app(db:, route_module:, handler:, features: [:base, :login, :logout])
    app_db       = db
    app_features = features

    Class.new(Roda) do
      include route_module

      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :halt

      plugin :rodauth do
        db app_db
        enable(*app_features)
        login_column :email
        hmac_secret SecureRandom.hex(32)
      end

      # Route-module rescue paths log via auth_logger (Onetime::LoggerMethods
      # on the real router); a null logger keeps this app boot-free.
      def auth_logger
        @auth_logger ||= Logger.new(File::NULL)
      end

      route do |r|
        # Test-only session establishment: writes the same session key a
        # successful Rodauth login would, without the login flow.
        r.post 'test-login' do
          session[rodauth.session_key] = Integer(r.params['account_id'])
          { ok: true }
        end

        send(handler, r)

        response.status = 404
        { error: 'Not Found' }
      end
    end
  end

  # Seed a VERIFIED accounts row directly in the mini app's database. The
  # integration-lane AccountSeedHelper pairs accounts with Familia Customers;
  # route-module specs have no Valkey, so a bare row is the whole subject.
  def seed_route_test_account(db, email: nil)
    email ||= "route-test-#{SecureRandom.hex(6)}@example.com"
    db[:accounts].insert(email: email, status_id: AuthTestConstants::STATUS_VERIFIED)
  end

  # Parsed JSON body of the last response.
  def json_body
    JSON.parse(last_response.body)
  end
end
