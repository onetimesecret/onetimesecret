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
        # Sampled BEFORE the append: once this receipt's own timeline is
        # saturated, its fetch events stop fanning out to the org trail --
        # otherwise one hammered link (scanner, monitor, attacker) could
        # evict every other receipt's history from the org-wide cap. Each
        # receipt therefore contributes at most ACCESS_EVENTS_MAX fetch
        # events to the trail; lifecycle transitions are unaffected (they
        # call record_org_audit_event directly).
        saturated = access_count >= ACCESS_EVENTS_MAX

        member = format('%s:%d:%s', kind, (at.to_f * 1000).to_i, SecureRandom.hex(4))
        access_events.add(member, at.to_f)

        # Keep the newest ACCESS_EVENTS_MAX events (ranks are ascending by
        # score, so rank 0 is the oldest).
        access_events.remrangebyrank(0, -(ACCESS_EVENTS_MAX + 1))

        # The writes above cascade the receipt's *default* expiration onto the
        # timeline key; tighten it to the receipt's actual remaining TTL so
        # the timeline can never outlive its receipt.
        # current_expiration is nil when the key carries no TTL (Redis TTL -1)
        # in some Familia paths; guard so telemetry never raises NoMethodError.
        remaining = current_expiration
        access_events.update_expiration(expiration: remaining) if remaining&.positive?

        # Fan out to the organization's audit trail (no-op without org
        # context). The org trail is the durable, org-wide view of the same
        # activity; see Organization::Features::AuditTrail.
        record_org_audit_event(kind, at: at) unless saturated

        member
      end

      # Append this receipt's activity to its organization's audit trail
      # (Organization::Features::AuditTrail). No-op for receipts without an
      # organization context. Best-effort by design: the trail is
      # observability, so a failure here must never break the calling path
      # (state transitions, read endpoints).
      #
      # @param kind [String, Symbol] event kind, e.g. 'created',
      #   'status_get' / 'secret_get', 'previewed' (creator opened their own
      #   secret link), 'creator_status_get', 'receipt_viewed' (creator's
      #   receipt page loaded), 'revealed', 'burned', 'expired', 'orphaned'.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @param organization [Onetime::Organization, nil] pass when the
      #   caller already holds the org to skip the extra load.
      # @param event_attrs [Hash] additional string-keyed context merged into
      #   the recorded event (e.g. the lifecycle actor discriminator, #3639).
      # @return [Hash, nil] the recorded event, or nil when skipped.
      def record_org_audit_event(kind, at: Familia.now, organization: nil, **event_attrs)
        organization ||= Onetime::Organization.load(org_id) unless org_id.to_s.empty?
        return if organization.nil?

        organization.record_audit_event(
          kind,
          at: at,
          # Shortids only: full identifiers are capability tokens (the
          # secret identifier IS the link) and must not leak into the trail.
          'receipt' => shortid,
          'secret' => secret_shortid.to_s,
          **event_attrs,
        )
      rescue StandardError => ex
        OT.le "[audit-trail] #{ex.class}: #{ex.message} (kind=#{kind}, receipt=#{shortid})"
        nil
      end

      # Atomic conditional set that claims a one-time timestamp field, run as a
      # single Lua script so the check-and-set is indivisible.
      #
      #   1. If the receipt hash no longer exists, do nothing -- never resurrect
      #      a destroyed/expired receipt (a bare HSETNX would otherwise create
      #      the hash).
      #   2. HSETNX on an existing hash claims the field only when it is
      #      genuinely absent, and performs no TTL change -- safe on a GET.
      #      familia >= 2.11.2 omits nil declared fields from storage (HDEL on
      #      clear) instead of persisting the serialized "null", so absence is
      #      now a reliable signal here; see the Gemfile familia pin comment.
      CLAIM_ONCE_SCRIPT = <<~LUA
        if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
        return redis.call('HSETNX', KEYS[1], ARGV[1], ARGV[2])
      LUA

      # The only fields claim_once! may stamp. claim_once! writes via
      # send("#{field}="), so restrict it to these two declared observability
      # fields — never let a caller-supplied name HSETNX an unknown key
      # (orphaned data) or raise NoMethodError on a missing writer.
      PERMITTED_CLAIM_FIELDS = [:receipt_viewed_at, :secret_value_shown_at].freeze

      # Atomically claim a one-time observability/consumption timestamp field,
      # stamping it with the current epoch seconds. Returns true for the single
      # caller that wins and false for every later OR concurrent caller -- the
      # win is decided atomically in Redis, so simultaneous first-loads can
      # never both succeed (no read-modify-write race). The winner's in-memory
      # attribute is updated to match the persisted value so the loaded object
      # stays coherent within the same request.
      #
      # @param field [Symbol, String] the timestamp field to claim.
      # @return [Boolean] true if this call claimed the field, false if it was
      #   already claimed (or the receipt no longer exists).
      def claim_once!(field)
        raise ArgumentError, "unclaimable field: #{field}" unless PERMITTED_CLAIM_FIELDS.include?(field.to_sym)

        ts  = Familia.now.to_i
        won = dbclient.eval(CLAIM_ONCE_SCRIPT, keys: [dbkey], argv: [field.to_s, ts.to_s]).to_i == 1
        send("#{field}=", ts) if won
        won
      end

      # Record the receipt/metadata page load as a one-time 'receipt_viewed'
      # audit event. Fires at most once per receipt via an atomic claim on the
      # receipt_viewed_at observability field, so even concurrent first-loads
      # record exactly one event. This bounds the org audit trail against a
      # bookmarked or monitored receipt page (whose loads would otherwise be
      # unbounded and could evict every other receipt's history from the
      # org-wide cap -- the receipt page is a safe GET but is not covered by
      # the access timeline's saturation guard, which only bounds link/status
      # fetches).
      #
      # It does NOT advance lifecycle state (#3633): receipt_viewed_at gates
      # nothing and is not part of is_previewed.
      #
      # @return [Hash, nil] the recorded audit event, or nil when already
      #   recorded or when there is no org context.
      def record_receipt_view!
        return unless claim_once!(:receipt_viewed_at)

        record_org_audit_event('receipt_viewed')
      end

      # Claim the one-time display of the secret's plaintext value to its
      # creator on the receipt page. Returns true for the single load that wins
      # the claim; every later or concurrent load gets false and must not
      # re-reveal the value. This is the "one time" guarantee for the
      # creator-side preview (generated passwords are shown nowhere else),
      # enforced independently of any display-window bound. This is the
      # creator-preview claim in ADR-019 (At-Most-Once Secret Reveal); the
      # receipt GET must gate its plaintext display on this, never re-reveal.
      #
      # The claim is taken at DISPLAY time, before the value is returned: this
      # is an at-most-once semantic. If the HTTP response is then lost in
      # flight the reveal is forfeited (the value is shown zero times) rather
      # than risking a second reveal -- the correct reading of "one time", and
      # the same property the retired previewed! state mutation had.
      #
      # @return [Boolean] true if this call claimed the display, else false.
      def claim_secret_value_display!
        claim_once!(:secret_value_shown_at)
      end

      # @return [Integer] number of retained access events (saturates at
      #   ACCESS_EVENTS_MAX; see cap semantics above).
      def access_count
        access_events.element_count
      end

      # Telemetry-derived "previewed at" timestamp (#3633): the stored
      # +previewed+ field when set, else the earliest access-timeline
      # timestamp (the moment the secret link was first fetched), else nil.
      # Keeps the previewed/viewed safe_dump fields coherent with
      # is_previewed now that no request path stamps +previewed+.
      #
      # @return [Integer, nil] epoch seconds, or nil when never previewed.
      def effective_previewed_at
        ts = previewed.to_i
        ts = first_access_at.to_i if ts.zero?
        ts.positive? ? ts : nil
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
