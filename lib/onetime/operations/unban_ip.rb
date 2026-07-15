# lib/onetime/operations/unban_ip.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Sibling of {Onetime::Operations::BanIP};
# loaded at the call site, so require the dependencies explicitly.
require 'colonel/models/banned_ip'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    # Unban a single IP address / CIDR as an operator action, and record it in the
    # admin audit trail (epic #33 / CONTRACT 4).
    #
    # The SINGLE implementation of the unban verb: the colonel endpoint
    # (`DELETE /api/colonel/banned-ips/:ip`) and the `bin/ots bannedips unban` CLI
    # are thin adapters over it. The model call is IDENTICAL to the prior inline
    # call (`Onetime::BannedIP.unban!(ip)`); the op adds exactly one
    # {Onetime::AdminAuditEvent} per successful unban.
    #
    # Stateless, single `#call`, returns an immutable {Result}. An unban of an IP
    # that is not banned returns `status: :not_found` and records NO audit event
    # (nothing mutated).
    class UnbanIP
      # Audit verb recorded for every successful unban.
      AUDIT_VERB = 'ip.unban'

      # @!attribute status [r]
      #   @return [Symbol] :success (removed) or :not_found (nothing to remove)
      Result = Data.define(:status, :ip_address, :unbanned)

      # @param ip_address [String] the IP address or CIDR to unban.
      # @param actor [String, #extid, #email] acting admin's PUBLIC identity
      #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
      def initialize(ip_address:, actor:)
        @ip_address = ip_address
        @actor      = actor
      end

      # @return [Result]
      def call
        # BannedIP.unban! returns true when a record was removed, false when the
        # exact IP was not indexed (nothing to remove). Preserved verbatim.
        unbanned = Onetime::BannedIP.unban!(@ip_address)

        unless unbanned
          return Result.new(status: :not_found, ip_address: @ip_address, unbanned: false)
        end

        # One audit event per successful mutation.
        Onetime::AdminAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: @ip_address,
          result: :success,
        )

        Result.new(status: :success, ip_address: @ip_address, unbanned: true)
      end
    end
  end
end
