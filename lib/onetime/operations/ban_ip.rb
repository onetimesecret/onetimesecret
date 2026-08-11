# lib/onetime/operations/ban_ip.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. IP bans have no single domain owner (the
# perimeter is site-wide, enforced by the ip_ban middleware), so — unlike the
# auth-owned customer verbs — this lives in the central operations home. Loaded
# at the call site (colonel logic + CLI), so require the dependencies explicitly,
# mirroring AdminVerifyDomain.
require 'colonel/models/banned_ip'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    # Ban a single IP address / CIDR as an operator action, and record it in the
    # admin audit trail (epic #33 / CONTRACT 4).
    #
    # This is the SINGLE implementation of the ban verb. Before this extraction
    # `BanIP`/`UnbanIP` were API-only: the colonel logic called
    # {Onetime::BannedIP.ban!} directly, so an incident responder on a shell had
    # no way to ban an IP. The colonel endpoint
    # (`POST /api/colonel/banned-ips`) and the `bin/ots bannedips ban` CLI are now
    # thin adapters over this op.
    #
    # ## Behavioural parity (bit-for-bit)
    #
    # The model call is IDENTICAL to the prior inline call
    # (`Onetime::BannedIP.ban!(ip, reason:, banned_by:, expiration:)`): `banned_by`
    # is still whatever the caller supplies (the colonel logic passes the acting
    # colonel's objid, preserving the stored field verbatim), and `expiration` is
    # passed through unchanged. The op adds exactly one thing the inline call
    # lacked: one {Onetime::ColonelAuditEvent} per successful ban.
    #
    # ## Audit vs. stored identity
    #
    # `banned_by` (stored ON the record, surfaced in the UI's "Banned By" column)
    # and `actor` (the audit-trail identity) are DISTINCT on purpose: the audit
    # actor must be a PUBLIC id (colonel extid/email), never an internal objid,
    # while the historic `banned_by` field keeps its existing objid value for
    # bit-for-bit parity.
    #
    # Stateless, single `#call`, returns an immutable {Result}. A ban that
    # cannot proceed because the IP is already covered by an existing ban
    # returns `status: :already_banned`, mutates NOTHING, and records one
    # `result: :failure` event.
    #
    # That is deliberately NOT the `:no_change` treatment the customer verbs
    # use, and the discriminator is the ADAPTER: colonel `SetRole` renders a
    # `:no_change` as a successful response, whereas colonel `BanIP` renders
    # `:already_banned` as a 422 form error ("IP address is already banned").
    # It is a REFUSAL of an attempted privileged mutation, so it is traceable —
    # the "only audit an actual change" rule governs the SUCCESS event, not
    # whether a refusal leaves a trace.
    class BanIP
      include Onetime::AuditedFailure

      # Audit verb recorded for every successful ban.
      AUDIT_VERB = 'ip.ban'

      # A privileged mutation was asked for and REFUSED.
      REFUSAL_STATUSES = [:already_banned].freeze

      # TARGET NOTE: the success event targets `banned.ip_address` (the stored,
      # normalised form), which does not exist on a failure path — `banned` is a
      # local. The failure targets the operator's `@ip_address` input instead:
      # the same kind of identifier, just not normalised by the model.
      #
      # `BannedIP.ban!` writes the record and its index BEFORE the success
      # record runs, so a partial ban would otherwise be invisible. Records one
      # `result: :failure` and re-raises.
      audit_failures :call,
        verb: AUDIT_VERB,
        target: -> { @ip_address },
        detail: -> { { reason: @reason, expiration: @expiration } }

      # @!attribute status [r]
      #   @return [Symbol] :success (banned) or :already_banned (no-op)
      Result = Data.define(:status, :id, :ip_address, :reason, :banned_by, :banned_at)

      # @param ip_address [String] the IP address or CIDR to ban (caller validates
      #   format; this op does not re-parse it).
      # @param actor [String, #extid, #email] acting admin's PUBLIC identity
      #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
      # @param reason [String, nil] optional human-readable reason (stored + audited).
      # @param banned_by [String, nil] value stored on the record's `banned_by`
      #   field (the colonel logic passes the acting colonel's objid, preserving
      #   the historic behaviour). Distinct from `actor`.
      # @param expiration [Integer, nil] optional TTL in seconds; nil = permanent.
      def initialize(ip_address:, actor:, reason: nil, banned_by: nil, expiration: nil)
        @ip_address = ip_address
        @actor      = actor
        @reason     = reason
        @banned_by  = banned_by
        @expiration = expiration
      end

      # @return [Result]
      def call
        # Defensive idempotency guard so a CLI/reuse caller never double-bans or
        # records a spurious audit event. In the HTTP path the colonel logic's
        # raise_concerns already rejects an already-banned IP with a form error
        # (bit-for-bit preserved), so this branch is reached only off the request
        # path (e.g. the CLI).
        if Onetime::BannedIP.banned?(@ip_address)
          record_refusal(:already_banned)
          return Result.new(
            status: :already_banned,
            id: nil,
            ip_address: @ip_address,
            reason: nil,
            banned_by: nil,
            banned_at: nil,
          )
        end

        banned = Onetime::BannedIP.ban!(
          @ip_address,
          reason: @reason,
          banned_by: @banned_by,
          expiration: @expiration,
        )

        # One audit event per successful mutation. `reason` is non-secret; never
        # put secret content / tokens into detail.
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: banned.ip_address,
          result: :success,
          detail: { reason: @reason, expiration: @expiration },
        )

        Result.new(
          status: :success,
          id: banned.objid,
          ip_address: banned.ip_address,
          reason: banned.reason,
          banned_by: banned.banned_by,
          banned_at: banned.banned_at,
        )
      end

      private

      # Same verb/actor as the success event; see the TARGET NOTE above for why
      # the target is the raw input. Best-effort: never break the op.
      def record_refusal(status)
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: @ip_address,
          result: :failure,
          detail: { reason: status.to_s, expiration: @expiration },
        )
      rescue StandardError => ex
        OT.le "[BanIP] refusal audit failed: #{ex.class}: #{ex.message}"
      end
    end
  end
end
