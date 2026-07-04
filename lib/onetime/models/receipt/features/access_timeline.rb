# lib/onetime/models/receipt/features/access_timeline.rb
#
# frozen_string_literal: true

module Onetime::Receipt::Features
  # Append-only access telemetry for a secret, recorded on its receipt.
  #
  # Every access is an event in a single capped sorted set (score = epoch
  # seconds, member = "kind:ms:nonce"), so the timeline carries WHAT happened
  # and WHEN without touching the secret's lifecycle +state+ field. This is
  # the telemetry half of the lifecycle/telemetry split from #3633: reads
  # (GET) append here; only a genuine reveal/burn advances lifecycle.
  #
  # The timeline lives on the Receipt rather than the Secret because the
  # secret is destroyed on reveal while the receipt deliberately outlives it
  # (see Receipt#receipt_ttl) -- exactly when the creator wants to know
  # whether the link was accessed beforehand.
  #
  # Aggregates (count, first/last access) are derived from the set rather
  # than stored, so the hot path is a single ZADD plus trim with no
  # read-modify-write or CAS. The cap bounds memory against mechanical
  # hammering (scanners, monitors); beyond it the OLDEST events are evicted,
  # so first_access_at reflects the earliest RETAINED event and access_count
  # saturates at ACCESS_EVENTS_MAX. Exact-count-under-abuse is an explicit
  # non-goal for this tier; an org audit trail is the follow-up (#3633).
  module AccessTimeline
    Familia::Base.add_feature self, :access_timeline

    # Newest events retained when trimming the timeline.
    ACCESS_EVENTS_MAX = 100

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      # Related field: inherits the receipt's expiration on every write
      # (Familia's DataType#add -> update_expiration cascade) and is deleted
      # with the receipt by Familia's destroy!.
      base.sorted_set :access_events

      base.include InstanceMethods
    end

    module InstanceMethods
      # Append an access event to the timeline.
      #
      # @param kind [String, Symbol] what happened, e.g. 'status_get' (the
      #   status endpoint was fetched) or 'secret_get' (the secret metadata
      #   endpoint was fetched). Kept open-ended so higher-fidelity tiers
      #   (e.g. a client-confirmed render beacon) can append richer kinds.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @return [String, nil] the recorded member, or nil when nothing was
      #   recorded (blank kind, or the receipt no longer exists -- appending
      #   would orphan a timeline key next to a destroyed/expired receipt).
      def record_access_event(kind, at: Familia.now)
        return if kind.to_s.empty?
        return unless exists?

        # Sorted-set members must be unique: two accesses in the same
        # millisecond may not collide, so suffix with a short nonce. The score
        # carries the authoritative timestamp.
        member = format('%s:%d:%s', kind, (at.to_f * 1000).to_i, SecureRandom.hex(4))
        access_events.add(member, at.to_f)

        # Keep the newest ACCESS_EVENTS_MAX events (ranks are ascending by
        # score, so rank 0 is the oldest).
        access_events.remrangebyrank(0, -(ACCESS_EVENTS_MAX + 1))

        # The writes above cascade the receipt's *default* expiration onto the
        # timeline key; tighten it to the receipt's actual remaining TTL so
        # the timeline can never outlive its receipt.
        remaining = current_expiration
        access_events.update_expiration(expiration: remaining) if remaining.positive?

        # Fan out to the organization's audit trail (no-op without org
        # context). The org trail is the durable, org-wide view of the same
        # activity; see Organization::Features::AuditTrail.
        record_org_audit_event(kind, at: at)

        member
      end

      # Append this receipt's activity to its organization's audit trail
      # (Organization::Features::AuditTrail). No-op for receipts without an
      # organization context. Best-effort by design: the trail is
      # observability, so a failure here must never break the calling path
      # (state transitions, read endpoints).
      #
      # @param kind [String, Symbol] event kind, e.g. 'created',
      #   'status_get', 'secret_get', 'previewed', 'revealed', 'burned',
      #   'expired', 'orphaned'.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @param organization [Onetime::Organization, nil] pass when the
      #   caller already holds the org to skip the extra load.
      # @return [Hash, nil] the recorded event, or nil when skipped.
      def record_org_audit_event(kind, at: Familia.now, organization: nil)
        organization ||= Onetime::Organization.load(org_id) unless org_id.to_s.empty?
        return if organization.nil?

        organization.record_audit_event(
          kind,
          at: at,
          # Shortids only: full identifiers are capability tokens (the
          # secret identifier IS the link) and must not leak into the trail.
          'receipt' => shortid,
          'secret'  => secret_shortid.to_s,
        )
      rescue StandardError => ex
        OT.le "[audit-trail] #{ex.class}: #{ex.message} (kind=#{kind}, receipt=#{shortid})"
        nil
      end

      # @return [Integer] number of retained access events (saturates at
      #   ACCESS_EVENTS_MAX; see cap semantics above).
      def access_count
        access_events.element_count
      end

      # @return [Float, nil] epoch seconds of the earliest retained access.
      def first_access_at
        _member, score = access_events.rangeraw(0, 0, with_scores: true).first
        score&.to_f
      end

      # @return [Float, nil] epoch seconds of the most recent access.
      def last_access_at
        _member, score = access_events.rangeraw(-1, -1, with_scores: true).first
        score&.to_f
      end
    end
  end
end
