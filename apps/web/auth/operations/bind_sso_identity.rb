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
# TRANSACTION SAFETY:
#   The insert is wrapped in a SAVEPOINT (db.transaction(savepoint: true)) so a
#   concurrent-bind UniqueConstraintViolation rolls back ONLY that statement, not
#   an ambient caller transaction. This matters for the deferred bind after MFA
#   (#3877): Rodauth runs `after_two_factor_authentication` INSIDE `transaction do`
#   for the WebAuthn (webauthn.rb) and SMS (sms_codes.rb) second factors. Without
#   the savepoint, on PostgreSQL the violation would abort that outer transaction —
#   the re-read below would then raise PG::InFailedSqlTransaction and the whole MFA
#   transaction would roll back. Called OUTSIDE a transaction (the password-challenge
#   interstitial), the savepoint degrades to a plain single-statement transaction.
#
# Returns:
#   :ok       — row inserted, OR already present for the SAME account (idempotent)
#   :conflict — the (provider, issuer, uid) row is owned by a DIFFERENT account,
#               OR ownership could not be confirmed (the winner vanished between the
#               violation and the re-read). NEVER a success: callers must not log the
#               caller in onto that identity. A post-authentication caller with no
#               error surface (4.A's deferred bind — MFA already succeeded) must
#               audit-and-skip on :conflict, never raise and never fail the login.
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

        # SAVEPOINT so a losing-race violation cannot poison an ambient caller
        # transaction (see TRANSACTION SAFETY above). Degrades to a plain
        # transaction when not already inside one.
        @db.transaction(savepoint: true) do
          dataset.insert(@criteria.merge(account_id: @account_id))
        end
        :ok
      rescue Sequel::UniqueConstraintViolation
        # A concurrent bind inserted the row first; the savepoint rolled back to
        # before our insert, so the outer transaction (if any) is still healthy.
        # Re-read and apply the SAME ownership check to the winner.
        owned_or_conflict(dataset.where(@criteria).first)
      end

      private

      def dataset
        @db[IDENTITIES_TABLE]
      end

      # :ok when the existing identity row belongs to the account we authenticated,
      # :conflict otherwise. A nil row — the winner vanished between the violation and
      # the re-read, or was never found — is :conflict, i.e. "could not confirm this
      # row is yours." It is NEVER upgraded to :ok, so a mismatch (or an unconfirmable
      # race) can never masquerade as a successful bind. See the :conflict caller
      # contract in the Returns doc above.
      def owned_or_conflict(row)
        row && row[:account_id].to_s == @account_id.to_s ? :ok : :conflict
      end
    end
  end
end
