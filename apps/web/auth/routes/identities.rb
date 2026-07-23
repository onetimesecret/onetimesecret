# apps/web/auth/routes/identities.rb
#
# frozen_string_literal: true

#
# JSON API for managing an account's linked SSO identities (#3840 Phase 2).
#
# Mirrors routes/active_sessions.rb: list + delete-one of a per-account
# resource, scoped strictly to the CURRENT account. Rows live in the
# account_identities table keyed on (provider, issuer, uid) — see
# migrations/006_omniauth_identities.rb + 008_issuer_scoped_identities.rb.
#
# SECURITY:
#   - Every query is scoped by account_id = rodauth.session_value, so a caller
#     can never see or delete another account's identities (no IDOR): a
#     cross-account id filters to zero rows and yields 404, never a delete.
#   - DELETE enforces last-credential safety: an SSO-only account (no usable
#     password) may not remove its FINAL identity, which would lock it out.
#     Accounts that have a password may remove identities freely.
#
# NOTE: account_identities has NO created_at column (not added by 006/008), so
# the list does not return one. `uid` (the IdP `sub`) is masked for display —
# the row `id` is the delete handle, so the full uid is never needed client-side.
#
module Auth
  module Routes
    module Identities
      def handle_identities_routes(r)
        r.on 'identities' do
          # Require authentication for all identity management endpoints.
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

          # Scoped dataset — NEVER widened. All reads/writes below derive from it,
          # so cross-account access is impossible by construction.
          identities_ds = rodauth.db[:account_identities].where(account_id: account_id)

          # GET /auth/identities
          # List the current account's linked SSO identities.
          r.get do
            rows = identities_ds.order(:id).all

            identities_data = rows.map { |row| serialize_identity(row) }

            response.headers['Content-Type'] = 'application/json'
            { identities: identities_data }
          rescue StandardError => ex
            auth_logger.error 'Error fetching identities',
              {
                exception: ex,
                account_id: account_id,
              }

            response.status = 500
            { error: 'Failed to fetch identities' }
          end

          # DELETE /auth/identities/:id
          # Remove ONE identity, iff it belongs to the current account.
          # Integer matcher: a non-numeric segment simply doesn't match here and
          # falls through to the router's 404.
          r.is Integer do |identity_id|
            next unless r.delete?

            # Scope by BOTH id AND account_id (the dataset already pins
            # account_id). A cross-account id resolves to nil => 404, never a
            # delete of someone else's identity. Built once, reused for the delete.
            scoped = identities_ds.where(id: identity_id)

            # Existence check, last-credential guard, and delete run inside ONE
            # transaction with an account-scoped row lock, closing a TOCTOU: two
            # concurrent DELETEs for DIFFERENT ids of the same SSO-only account
            # could each observe count==2 and both pass the last-credential check,
            # stripping every sign-in method.
            #
            # for_update.all issues "SELECT ... FOR UPDATE": on PostgreSQL this
            # row-locks the account's identity rows, so a concurrent DELETE for
            # the same account blocks here until we commit; on SQLite the lock
            # clause is dropped and SQLite serializes writers anyway, so neither
            # backend raises. Count/existence are derived from this single locked
            # fetch — no redundant per-id re-query.
            #
            # NOTE: do NOT use identities_ds.for_update.count — Sequel emits
            # "SELECT count(*) ... FOR UPDATE", which PostgreSQL REJECTS (FOR
            # UPDATE is not allowed with aggregates). Materialize, then count in Ruby.
            #
            # has_password? checks the session account's password hash. Accounts
            # WITH a password may remove identities freely.
            result = rodauth.db.transaction do
              locked = identities_ds.for_update.all
              target = locked.find { |row| row[:id] == identity_id }

              if target.nil?
                :not_found
              elsif locked.size <= 1 && !rodauth.has_password?
                :last_credential
              else
                scoped.delete
                { provider: target[:provider] }
              end
            end

            case result
            when :not_found
              response.status = 404
              next { error: 'Identity not found' }
            when :last_credential
              response.status = 409
              next {
                error: 'Cannot remove your only sign-in method. ' \
                       'Set a password first, then remove this identity.',
                error_code: 'last_credential',
              }
            end

            auth_logger.warn 'SSO identity disconnected',
              {
                account_id: account_id,
                provider: result[:provider],
              }

            response.headers['Content-Type'] = 'application/json'
            { success: 'Identity removed successfully' }
          rescue StandardError => ex
            auth_logger.error 'Error removing identity',
              {
                exception: ex,
                account_id: account_id,
                identity_id: identity_id,
              }

            response.status = 500
            { error: 'Failed to remove identity' }
          end
        end
      end

      private

      # Transform an account_identities row into the wire shape. `uid` is masked
      # (display-only); the row `id` is the stable delete handle.
      def serialize_identity(row)
        {
          id: row[:id],
          provider: row[:provider],
          issuer: row[:issuer].to_s,
          uid: mask_uid(row[:uid]),
        }
      end

      # Mask the IdP subject identifier for display. Keeps enough to disambiguate
      # without echoing the full opaque `sub`. Short uids are fully masked.
      def mask_uid(uid)
        s = uid.to_s
        return '***' if s.length <= 8

        "#{s[0, 4]}…#{s[-4, 4]}"
      end
    end
  end
end
