# apps/web/auth/routes/webauthn_credentials.rb
#
# frozen_string_literal: true

require 'time'

#
# JSON API for listing an account's registered WebAuthn credentials (passkeys).
#
# Mirrors routes/identities.rb: list of a per-account resource, scoped strictly
# to the CURRENT account. Rows live in the account_webauthn_keys table keyed on
# (account_id, webauthn_id) — see migrations/001_initial.rb.
#
# GET only: removal stays with Rodauth's own POST /auth/webauthn-remove, which
# re-authenticates and keeps the two-factor bookkeeping consistent. A bare
# DELETE here would bypass that, so this module deliberately does not add one.
#
# SECURITY:
#   - Every query is scoped by account_id = rodauth.session_value, so a caller
#     can never see another account's credentials.
#   - public_key and sign_count are verification material and are NEVER
#     returned; only the credential id and last-use timestamp leave the server.
#
# NOTE: account_webauthn_keys has NO name and NO created_at column, so the list
# returns neither. `webauthn_id` is the stable client-side handle (it is the
# credential id the authenticator already knows).
#
# DELIBERATELY not gated on the webauthn feature being loaded: this is
# management/visibility data (Settings -> Security), not an offer of a
# completable factor. With AUTH_WEBAUTHN_ENABLED temporarily off, an account's
# registered credentials still exist and hiding them would misreport account
# state. The one webauthn signal that IS feature-gated is mfa-status's
# webauthn_enabled (routes/account.rb), because that drives the MFA challenge
# page toward a route that is only mounted when the feature is on.
#
module Auth
  module Routes
    module WebauthnCredentials
      def handle_webauthn_credentials_routes(r)
        r.on 'webauthn-credentials' do
          # Require authentication for all credential listing endpoints.
          unless rodauth.logged_in?
            response.status = 401
            next { error: 'Authentication required' }
          end

          # Account id straight from the session — no account load required, and
          # the scoping key for every query below.
          account_id = rodauth.session_value
          unless account_id
            response.status = 401
            next { error: 'Invalid session' }
          end

          # Scoped dataset — NEVER widened, so cross-account access is
          # impossible by construction.
          credentials_ds = rodauth.db[:account_webauthn_keys].where(account_id: account_id)

          # GET /auth/webauthn-credentials
          # List the current account's registered passkeys, most recently used
          # first.
          r.get do
            # Explicit column list: public_key/sign_count are verification
            # material and must never even leave the database for this route.
            rows = credentials_ds
              .select(:webauthn_id, :last_use)
              .order(Sequel.desc(:last_use))
              .all

            credentials_data = rows.map { |row| serialize_webauthn_credential(row) }

            response.headers['Content-Type'] = 'application/json'
            { credentials: credentials_data, count: credentials_data.size }
          rescue StandardError => ex
            auth_logger.error 'Error fetching webauthn credentials',
              {
                exception: ex,
                account_id: account_id,
              }

            response.status = 500
            { error: 'Failed to fetch webauthn credentials' }
          end
        end
      end

      private

      # Transform an account_webauthn_keys row into the wire shape. public_key
      # and sign_count are deliberately omitted (verification material).
      def serialize_webauthn_credential(row)
        {
          id: row[:webauthn_id],
          last_used_at: normalize_webauthn_time(row[:last_use]),
        }
      end

      # Emit ISO8601 UTC regardless of backend: SQLite can round-trip
      # timestamps as bare strings while PostgreSQL returns Time, so normalize
      # through Time rather than trusting driver string formats. getutc (not
      # utc) so the row value is not mutated in place.
      def normalize_webauthn_time(value)
        time = value.is_a?(Time) ? value : Time.parse(value.to_s)
        time.getutc.iso8601
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
