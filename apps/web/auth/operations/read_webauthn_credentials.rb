# apps/web/auth/operations/read_webauthn_credentials.rb
#
# frozen_string_literal: true

require 'json'

require 'onetime/session/surface'

module Auth
  module Operations
    # Read an account's registered WebAuthn credentials with the
    # per-surface scope metadata {Onetime::ReauthPolicy} consumes (#4414).
    #
    # The `account_webauthn_keys` table gained a nullable `surface_scope`
    # column (migration 009) holding a JSON-encoded
    # {Onetime::SessionSurface} descriptor. Rows registered before that
    # ships carry NULL and read as :platform — the same refusal shape a
    # nil scope has under ReauthPolicy's unknown-scope default, and the
    # value that matches historical single-origin deployments.
    #
    # This operation returns ONLY the shape the policy consumes:
    #
    #     [{ scope: :platform }, { scope: :tenant, id: '<domain_id>' }, …]
    #
    # No public_key, no sign_count, no last_use — the policy has no
    # opinion about those, and downstream code that DOES need them
    # (list-credentials-for-settings, remove-credential, ceremony
    # verification) reads the row itself, not this projection.
    class ReadWebauthnCredentials
      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param account_id [Integer, String]
      # @return [Array<Hash>] each `{ scope: :platform }` or
      #   `{ scope: :tenant, id: <domain_id> }`; empty when the account
      #   has no credentials or the read fails
      def call(account_id)
        return [] if account_id.nil?

        rows = @db[:account_webauthn_keys]
          .where(account_id: Integer(account_id))
          .select(:surface_scope)
          .all

        rows.map { |row| descriptor_from_row(row) }
      rescue StandardError => ex
        Onetime.get_logger('Auth::ReadWebauthnCredentials').warn 'Read failed',
          account_id: account_id,
          error: ex.message,
          error_class: ex.class.name
        []
      end

      private

      # Turn one row's surface_scope value into the policy-shaped
      # descriptor. NULL / blank / unparseable JSON / an unrecognized
      # descriptor shape all fall back to :platform — the same value
      # legacy rows carry, and the safe refusal shape on any surface
      # other than :canonical.
      def descriptor_from_row(row)
        raw = row[:surface_scope]
        return { scope: :platform } if raw.to_s.empty?

        parsed = JSON.parse(raw)
        return { scope: :platform } unless parsed.is_a?(Hash)

        kind = (parsed['kind'] || parsed[:kind]).to_s

        # Only a :custom descriptor with a non-blank id resolves to a
        # tenant credential. :canonical and :subdomain are both
        # platform-equivalent for the offer rule (a subdomain deployment
        # shares the canonical rp_id treatment until a related-origins
        # declaration widens it), and an unrecognized kind, or a :custom
        # with no id, falls back to :platform — the same safe refusal
        # shape legacy rows carry.
        return { scope: :platform } unless kind == 'custom'

        id = parsed['id'] || parsed[:id]
        id.to_s.empty? ? { scope: :platform } : { scope: :tenant, id: id.to_s }
      rescue JSON::ParserError
        { scope: :platform }
      end
    end
  end
end
