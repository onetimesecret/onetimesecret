# lib/onetime/models/organization/features/audit_trail.rb
#
# frozen_string_literal: true

module Onetime::Organization::Features
  # Organization-scoped audit trail of secret activity (#3633).
  #
  # A single capped sorted set per organization (score = epoch seconds,
  # member = compact event hash) recording what happened to the org's
  # secrets: creation, link/status fetches, reveal, burn, expiry. Events
  # are fanned out from the Receipt (see Receipt::Features::AccessTimeline
  # and the receipt state transitions), so every API version that touches
  # a receipt feeds the same trail.
  #
  # This backs the `audit_logs` entitlement (admin-tier; see
  # OrganizationMembership::ADMIN_ENTITLEMENTS and the billing catalog),
  # which until now was sold with no implementation behind it.
  #
  # Design notes:
  # - Append-only; the trail never drives behavior, so there is no CAS and
  #   a failed append must never break the calling path (callers guard).
  # - Capped at AUDIT_EVENTS_MAX (newest kept) to bound memory against
  #   mechanical hammering of anonymous read endpoints. For long-horizon or
  #   compliance-grade retention, a durable export (e.g. via the jobs
  #   publisher) can consume the same fan-out point later.
  # - No TTL: organizations are permanent records; the cap is the bound.
  # - Members are plain Hashes; Familia JSON round-trips them (string keys
  #   on read). A `nonce` field keeps members unique when two identical
  #   events land in the same second.
  module AuditTrail
    Familia::Base.add_feature self, :audit_trail

    # Newest events retained when trimming the trail.
    AUDIT_EVENTS_MAX = 10_000

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.sorted_set :audit_events

      base.include InstanceMethods
    end

    module InstanceMethods
      # Append an audit event to the organization's trail.
      #
      # @param kind [String, Symbol] what happened, e.g. 'created',
      #   'status_get', 'secret_get', 'previewed', 'revealed', 'burned',
      #   'expired', 'orphaned'.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @param attrs [Hash] additional context (receipt/secret shortids,
      #   actor when known). Keep values short and non-sensitive: never
      #   include secret content, full identifiers, or passphrases.
      # @return [Hash, nil] the recorded event, or nil when kind is blank.
      def record_audit_event(kind, at: Familia.now, **attrs)
        return if kind.to_s.empty?

        event = {
          'kind'  => kind.to_s,
          'at'    => at.to_f,
          'nonce' => SecureRandom.hex(4),
        }.merge(attrs.transform_keys(&:to_s))

        audit_events.add(event, at.to_f)
        audit_events.remrangebyrank(0, -(AUDIT_EVENTS_MAX + 1))

        event
      end

      # @return [Integer] number of retained audit events (saturates at
      #   AUDIT_EVENTS_MAX).
      def audit_event_count
        audit_events.element_count
      end

      # A page of audit events, newest first.
      #
      # @param offset [Integer] events to skip from the newest end.
      # @param limit [Integer] maximum events to return.
      # @return [Array<Hash>] events (string keys) newest-first; each
      #   includes its 'kind', 'at' and any recorded context.
      def audit_events_page(offset: 0, limit: 50)
        offset = [offset.to_i, 0].max
        limit  = limit.to_i.clamp(1, 200)

        audit_events.revrange(offset, offset + limit - 1)
      end
    end
  end
end
