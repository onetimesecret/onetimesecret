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
    # ships carry NULL and read as :platform — canonical-only legacy behavior.
    # New subdomain and custom registrations retain their exact establishing
    # surface so their request-host RP ID remains usable only there.
    #
    # This operation returns only the policy projection, optionally carrying
    # the registration RP ID used to authorize related-origin widening:
    #
    #     [{ scope: :platform, rp_id: 'example.com' },
    #      { scope: :tenant, id: '<domain_id>', rp_id: 'tenant.example' }, …]
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
      # @return [Array<Hash>] each `{ scope: :platform, rp_id: String? }`,
      #   `{ scope: :subdomain, host:, rp_id: String? }`, or
      #   `{ scope: :tenant, id: <domain_id>, rp_id: String? }`; empty when the account
      #   has no credentials or the read fails
      def call(account_id)
        return [] if account_id.nil?

        rows = @db[:account_webauthn_keys]
          .where(account_id: Integer(account_id))
          .select(:surface_scope, :rp_id)
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
        return credential_descriptor({ scope: :platform }, row) if raw.to_s.empty?

        parsed = JSON.parse(raw)
        return credential_descriptor({ scope: :platform }, row) unless parsed.is_a?(Hash)

        kind = (parsed['kind'] || parsed[:kind]).to_s

        case kind
        when 'subdomain'
          host       = parsed['host'] || parsed[:host]
          descriptor = host.to_s.empty? ? { scope: :platform } : { scope: :subdomain, host: host.to_s.downcase }
          credential_descriptor(descriptor, row)
        when 'custom'
          id         = parsed['id'] || parsed[:id]
          descriptor = id.to_s.empty? ? { scope: :platform } : { scope: :tenant, id: id.to_s }
          credential_descriptor(descriptor, row)
        else
          credential_descriptor({ scope: :platform }, row)
        end
      rescue JSON::ParserError
        credential_descriptor({ scope: :platform }, row)
      end

      def credential_descriptor(descriptor, row)
        rp_id = row[:rp_id].to_s
        rp_id.empty? ? descriptor : descriptor.merge(rp_id: rp_id)
      end
    end
  end
end
