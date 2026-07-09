# lib/onetime/models/email_suppression.rb
#
# frozen_string_literal: true

module Onetime
  # EmailSuppression — the outbound suppression list plus its bounce/complaint
  # event feed, the receiving side of email deliverability.
  #
  # The mailer can prove mail was SENT (the emails_sent counter); this model
  # records what came BACK: hard bounces, spam complaints, and the addresses we
  # must therefore stop mailing. Continuing to send to bouncing/complaining
  # addresses is what burns sender reputation, so the suppression list is the
  # actual protection — Onetime::Mail::Delivery::Base#deliver consults it before
  # every send and skips suppressed recipients.
  #
  # ## Backing store
  #
  # Three class-level structures (no per-instance Horreum hashes — the
  # AdminAuditEvent capped-collection precedent):
  #
  # - `email_suppression:entries` (hash): normalized address → JSON entry
  #   `{address, reason, source, created}`. Keyed by address so the outbound
  #   guard is a single O(1) HEXISTS.
  # - `email_suppression:index` (sorted set): address scored by created-at, so
  #   the admin list reads newest-first pages without loading the hash.
  # - `email_suppression:events` (sorted set): JSON bounce/complaint events as
  #   they are reported, scored by occurrence time. Capped to MAX_EVENTS on
  #   every write (the AdminAuditEvent trim idiom) — a rolling diagnostic feed,
  #   not an archive.
  #
  # Plus one lifetime counter, `sends_skipped`, ticked each time the outbound
  # guard blocks a send (the Customer.emails_sent class_counter idiom).
  #
  # ## Fail-open contract
  #
  # {.skip_send?} is the only method the send path calls and it NEVER raises: a
  # Redis failure logs and returns false (send proceeds). Losing one skip is a
  # tiny reputation cost; blocking all outbound mail on a Redis hiccup is an
  # outage. Every other method is a plain model accessor and raises normally.
  #
  # ## Where data comes from
  #
  # - Asynchronous ESP feedback (the primary source): bounce/complaint
  #   notifications piped into POST /api/colonel/email/deliverability/events
  #   via CLI/cron (see Onetime::Operations::Email::IngestFeedback).
  # - Synchronous SMTP hard bounces (5xx at send time): recorded as events by
  #   the delivery base class.
  # - Manual suppression via the ingest endpoint (reason 'manual').
  class EmailSuppression < Familia::Horreum
    # No SCHEMA constant on purpose (the AdminAuditEvent precedent): this model
    # is never serialised into an API response directly — the deliverability
    # endpoints declare their own wire contracts via SCHEMAS constants, with
    # Zod shapes at src/schemas/api/internal/responses/colonel-deliverability.ts.

    prefix :email_suppression

    # address → JSON entry. The exact-address lookup the outbound guard uses.
    class_hashkey :entries

    # address scored by created-at: newest-first pagination for the admin list.
    class_sorted_set :index

    # Bounded bounce/complaint feed. member = JSON event payload, score =
    # occurred-at epoch seconds (float). Site-wide, newest-first reads.
    class_sorted_set :events

    # Lifetime count of sends blocked by the suppression guard — the "how much
    # reputation damage did this prevent" number on the deliverability summary.
    class_counter :sends_skipped

    # Why an address is suppressed. 'manual' covers operator-supplied imports.
    REASONS = %w[bounce complaint manual].freeze

    # What the event feed records (suppression itself is state, not an event).
    EVENT_KINDS = %w[bounce complaint].freeze

    # Hard caps (by count), mirroring AdminAuditEvent::MAX_EVENTS: bounded
    # memory with no external configuration dependency. Suppressions get a
    # deeper cap because dropping one re-enables sending to a known-bad
    # address — at 100k the oldest entries are trimmed first.
    MAX_SUPPRESSIONS = 100_000
    MAX_EVENTS       = 10_000

    # Window for the "recent bounces/complaints" summary counts.
    RECENT_WINDOW = 7 * 24 * 60 * 60

    # Atomic suppression trim (Finding: paired hash + index writes must not
    # desync). Reading the oldest overflow members, deleting their hash entries,
    # and dropping them from the index run as ONE server-side step so a
    # concurrent add can never make the index rank removal target a different
    # set than the hash deletion — which would orphan an entry that still blocks
    # mail via {.suppressed?} yet has vanished from {.list}. Held at class level
    # (the StateCas Lua precedent) as the single canonical source.
    #
    # The overflow is re-derived from a live ZCARD inside the script so it is
    # authoritative even if the set changed since the caller's pre-check. Index
    # members are JSON-encoded (Familia serialize_value), hash field names are
    # raw, so each member is cjson.decode'd before the HDEL.
    #
    # KEYS: [entries hash, index sorted set]. ARGV: [cap]. Returns removed count.
    TRIM_SUPPRESSIONS_SCRIPT = <<~LUA
      local cap = tonumber(ARGV[1])
      local overflow = redis.call('ZCARD', KEYS[2]) - cap
      if overflow <= 0 then return 0 end
      local members = redis.call('ZRANGE', KEYS[2], 0, overflow - 1)
      for i = 1, #members do
        redis.call('HDEL', KEYS[1], cjson.decode(members[i]))
      end
      redis.call('ZREMRANGEBYRANK', KEYS[2], 0, overflow - 1)
      return overflow
    LUA

    class << self
      # Canonical address form used for every key: trimmed + downcased.
      def normalize(address)
        address.to_s.strip.downcase
      end

      # Add (or refresh) a suppression entry for an address.
      #
      # Idempotent in effect: suppressing an already-suppressed address
      # overwrites its entry (the reason/source may have changed) and returns
      # :updated so callers can audit only actual state changes.
      #
      # @param address [String] recipient address (normalized here).
      # @param reason [String, Symbol] one of {REASONS}.
      # @param source [String, nil] where the suppression came from, e.g.
      #   'ses', 'sendgrid', 'cli' — free-form provenance, not an enum.
      # @return [Symbol, nil] :created, :updated, or nil for a blank address.
      def suppress!(address:, reason:, source: nil)
        addr = normalize(address)
        return nil if addr.empty?

        reason = reason.to_s
        raise ArgumentError, "invalid suppression reason: #{reason}" unless REASONS.include?(reason)

        existed = entries.key?(addr)
        entry   = {
          'address' => addr,
          'reason' => reason,
          'source' => source.to_s,
          'created' => Familia.now,
        }

        # HSET (entry) and ZADD (index) must commit together for the same reason
        # remove! wraps its HDEL/ZREM: a concurrent remove! or reader landing
        # between the two writes would see a half-added address (in the index
        # but not the hash, or the reverse), desyncing count/list from
        # suppressed?. MULTI/EXEC via #transaction makes the pair atomic. Trim
        # runs after (its own atomic EVAL) — a MULTI must not queue an EVAL that
        # depends on the values written in the same transaction.
        transaction do
          entries[addr] = entry
          index.add(addr, entry['created'])
        end
        trim_suppressions!

        existed ? :updated : :created
      end

      # Remove an address from the suppression list.
      # @return [Boolean] true when an entry was actually removed.
      def remove!(address)
        addr = normalize(address)

        # HDEL (entry) and ZREM (index) must commit together. Issued as separate
        # commands, a concurrent suppress! landing between them resurrects the
        # entry without its index member (or the reverse), desyncing count/list
        # from suppressed?. MULTI/EXEC via #transaction makes the pair atomic;
        # the DataType calls route into the same transaction connection
        # (Fiber-local), preserving their serialization. The HDEL reply is the
        # first result — positive when a field was actually removed.
        result = transaction do
          entries.remove_field(addr)
          index.remove_element(addr)
        end
        result.results.first.to_i.positive?
      end

      # Exact-address membership check (one HEXISTS). Raises on Redis errors —
      # the send path must use {.skip_send?}, which wraps this fail-open.
      def suppressed?(address)
        addr = normalize(address)
        return false if addr.empty?

        entries.key?(addr)
      end

      # @return [Hash, nil] the stored entry (string keys), or nil.
      def lookup(address)
        addr = normalize(address)
        return nil if addr.empty?

        entries[addr]
      end

      # @return [Integer] number of suppressed addresses.
      def count
        index.element_count
      end

      # Newest-first page of suppression entries.
      #
      # @param limit [Integer] max entries to return.
      # @param offset [Integer] rank offset into the newest-first ordering.
      # @return [Array<Hash>] entries with string keys, newest first.
      def list(limit: 50, offset: 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset    = 0 if offset.negative?
        addresses = index.revrange(offset, offset + limit - 1)
        addresses.map { |addr| entries[addr] }.compact
      end

      # THE outbound guard — called by Onetime::Mail::Delivery::Base#deliver
      # before every send. One Redis lookup, FAIL-OPEN by contract: any error
      # is logged and answered with false so a Redis failure can never block
      # mail delivery. When the address is suppressed, the skip is tallied
      # (best-effort — a counter failure never changes the answer).
      #
      # @param address [String] recipient address.
      # @return [Boolean] true when the send should be skipped.
      def skip_send?(address)
        return false unless suppressed?(address)

        begin
          sends_skipped.increment
        rescue StandardError
          nil # counting is best-effort; the skip decision stands
        end
        true
      rescue StandardError => ex
        OT.le('[EmailSuppression] suppression check failed (failing open)', exception: ex)
        false
      end

      # Record one bounce/complaint event into the capped feed.
      #
      # @param address [String] the affected recipient.
      # @param kind [String, Symbol] one of {EVENT_KINDS}.
      # @param reason [String, nil] provider diagnostic (e.g. the SMTP 5xx
      #   line). Truncated; never secret content.
      # @param source [String, nil] provenance, e.g. 'ses', 'smtp-sync'.
      # @return [Hash] the stored event (string keys).
      def record_event(address:, kind:, reason: nil, source: nil)
        kind = kind.to_s
        raise ArgumentError, "invalid event kind: #{kind}" unless EVENT_KINDS.include?(kind)

        event = {
          'address' => normalize(address),
          'kind' => kind,
          'reason' => reason.nil? ? nil : reason.to_s[0, 256],
          'source' => source.to_s,
          'created' => Familia.now,
          # Nonce: keeps otherwise-identical events distinct members (the
          # AdminAuditEvent idiom — a duplicate member would silently collide).
          'id' => Familia.generate_id,
        }

        events.add(event, event['created'])
        trim_events!
        event
      end

      # Newest-first slice of the event feed.
      # @return [Array<Hash>] events with string keys, newest first.
      def recent_events(limit = 50, offset = 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset = 0 if offset.negative?
        events.revrange(offset, offset + limit - 1)
      end

      # @return [Integer] number of retained events.
      def event_count
        events.element_count
      end

      # Per-kind event counts inside the trailing window — the summary's
      # "bounces/complaints this week". Bounded by MAX_EVENTS by construction.
      #
      # @param window [Integer] seconds to look back from now.
      # @return [Hash{Symbol => Integer}] e.g. { bounce: 3, complaint: 1 }
      def recent_event_counts(window = RECENT_WINDOW)
        since  = Familia.now - window.to_i
        counts = EVENT_KINDS.to_h { |kind| [kind.to_sym, 0] }

        events.rangebyscore(since, '+inf').each do |event|
          kind = event['kind'].to_s.to_sym
          counts[kind] += 1 if counts.key?(kind)
        end

        counts
      end

      # Enforce the suppression cap: drop the OLDEST entries past the bound
      # (both index members and their hash entries). No-op below the cap.
      # @return [Integer] number of entries removed.
      def trim_suppressions!(cap = MAX_SUPPRESSIONS)
        cap = cap.to_i
        # Reject a negative cap (matching trim_events!): the Lua script derives
        # overflow as ZCARD - cap, so a negative cap would report a removed count
        # larger than the set could ever hold. Treat bad input as a no-op.
        return 0 if cap.negative?

        # Fast path: skip the round trip when clearly under the cap. The script
        # re-derives the overflow from a live ZCARD, so this pre-check only
        # avoids work on the common under-cap path — it is never the authority.
        return 0 if index.element_count <= cap

        # Read (oldest overflow members), hash deletion, and index removal must
        # be one atomic step. As separate commands a concurrent add shifts ranks
        # between the HDEL and the rank removal, so the index range removed would
        # not match the entries deleted — orphaning entries that still block mail
        # via #suppressed? but have vanished from #list. Lua runs it atomically.
        index.dbclient.eval(
          TRIM_SUPPRESSIONS_SCRIPT,
          keys: [entries.dbkey, index.dbkey],
          argv: [cap],
        ).to_i
      end

      # Enforce the event-feed cap: keep only the newest `cap` events.
      # @return [Integer] number of events removed.
      def trim_events!(cap = MAX_EVENTS)
        cap = cap.to_i
        return 0 if cap.negative?

        events.remrangebyrank(0, -(cap + 1))
      end
    end
  end
end
