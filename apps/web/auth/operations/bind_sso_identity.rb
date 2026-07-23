# apps/web/auth/operations/bind_sso_identity.rb
#
# frozen_string_literal: true

#
# Idempotent, issuer-scoped insert of an SSO identity row for a PROVEN account.
#
# This is the shared bind primitive (#3840 Phase 4), extracted verbatim from the
# password-challenge interstitial (Auth::Routes::LinkSso) so every linking surface
# that has ALREADY authorized a bind reuses the SAME ownership semantics:
#   - the password-challenge interstitial (Auth::Routes::LinkSso),
#   - deferred bind after MFA (#3877),
#   - mailbox-proof passwordless linking (Phase 4.B).
#
# It does NOT decide WHETHER a bind is authorized — the caller owns that decision
# (password proof, MFA completion, mailbox proof). This operation only performs
# the insert safely and reports whether the resulting row belongs to `account_id`.
#
# SECURITY MODEL:
#   The column shape mirrors omniauth_identity_insert_hash
#   (config/features/omniauth.rb): { account_id, provider, uid, issuer }. `issuer`
#   is coerced to the '' sentinel (NEVER nil) so it matches the
#   (provider, issuer, uid) unique index that issuer-scoped identities depend on
#   (#3838 — a NULL vs '' split would break the index).
#
#   The unique index on (provider, issuer, uid) plus "challenge minted only when
#   no identity row exists" makes cross-account escalation impossible, so :conflict
#   only ever fires as a benign idempotency guard — but ownership is verified at
#   BOTH the pre-SELECT and the concurrent-insert (UniqueConstraintViolation) site
#   so a mismatch can never masquerade as success (i.e. log the caller in onto an
#   identity that is not theirs).
#
# The `db` is passed EXPLICITLY (not rodauth.db) so the op is usable outside a
# Rodauth request context — e.g. a background bind completed after MFA (#3877).
#
# Returns:
#   :ok       — row inserted, OR already present for the SAME account (idempotent)
#   :conflict — the (provider, issuer, uid) row is owned by a DIFFERENT account
#
# Example:
#   result = Auth::Operations::BindSsoIdentity.call(
#     db: rodauth.db,
#     account_id: account_id,
#     provider: challenge.provider,
#     issuer: challenge.issuer,
#     uid: challenge.uid,
#   )
#   # => :ok | :conflict
#
module Auth
  module Operations
    class BindSsoIdentity
      IDENTITIES_TABLE = :account_identities

      # @param db [Sequel::Database] the auth database (explicit — NOT rodauth.db,
      #   so the op is usable outside a Rodauth request context)
      # @param account_id [Integer, String] the proven account the identity binds to
      # @param provider [String] OmniAuth provider name
      # @param issuer [String, nil] resolved IdP issuer; nil → '' sentinel
      # @param uid [String] provider-scoped subject id
      # @return [:ok, :conflict]
      def self.call(db:, account_id:, provider:, issuer:, uid:)
        new(db: db, account_id: account_id, provider: provider, issuer: issuer, uid: uid).call
      end

      def initialize(db:, account_id:, provider:, issuer:, uid:)
        @db         = db
        @account_id = account_id
        @criteria   = {
          provider: provider,
          issuer: issuer.to_s,
          uid: uid,
        }
      end

      # @return [:ok, :conflict]
      def call
        existing = dataset.where(@criteria).first
        return owned_or_conflict(existing) if existing

        dataset.insert(@criteria.merge(account_id: @account_id))
        :ok
      rescue Sequel::UniqueConstraintViolation
        # A concurrent bind inserted the row first — re-read and apply the SAME
        # ownership check to the winner.
        owned_or_conflict(dataset.where(@criteria).first)
      end

      private

      def dataset
        @db[IDENTITIES_TABLE]
      end

      # :ok when the existing identity row belongs to the account we authenticated,
      # :conflict otherwise (including a row that vanished between checks).
      def owned_or_conflict(row)
        row && row[:account_id].to_s == @account_id.to_s ? :ok : :conflict
      end
    end
  end
end
