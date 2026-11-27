# lib/onetime/models/organization/features/secret_activity.rb
#
# frozen_string_literal: true

require 'digest'

module Onetime::Organization::Features
  # Organization-scoped secret activity trail (#3633).
  #
  # Records what happened to the organization's secrets: creation,
  # link/status fetches, reveal, burn, expiry. Events are fanned out from the
  # Receipt (see Receipt::Features::AccessTimeline and the receipt state
  # transitions). State transitions (reveal, burn, expiry, orphaning) record
  # at the model layer and receipt views record from v1 and v2/v3 alike. All
  # of these need the receipt's org_id, which v1 and v2/v3 creation stamp
  # from the creator's organization, or for a guest from the organization
  # owning the custom domain (none when that organization is archived).
  # Creation and link fetch events come from the logic layer
  # (BaseSecretAction#record_created_activity and AccessTelemetry, each with
  # a v1 and a v2/v3 implementation; status fetches exist only in v2/v3).
  # Incoming-secret creations do not feed the trail. Receipts created before
  # stamping was added carry no org_id and never reach it.
  #
  # This backs the `audit_logs` entitlement (admin-tier; see
  # OrganizationMembership::ADMIN_ENTITLEMENTS and the billing catalog).
  #
  # == Storage
  #
  # Every event has a deterministic id (see .event_id). Identical fetch
  # events inside one coalescing window share an id, so a repeat increments
  # a count instead of adding a row; every other kind gets a random bucket
  # and stays its own row. Four keys per organization:
  #
  #   secret_activity_member  ZSET  id -> last_at. Events on receipts with an
  #                                 owner, and events with no receipt context.
  #   secret_activity_guest   ZSET  id -> last_at. Events on receipts a guest
  #                                 created (no owner), whoever the actor is.
  #   secret_activity_detail  HASH  id -> JSON of the first occurrence's
  #                                 attributes, plus first_at.
  #   secret_activity_count   HASH  id -> occurrences.
  #
  # The two partitions have their own caps (max_events, max_guest_events),
  # so guests creating secrets on a public custom domain can only evict
  # guest events, never the members'. One Lua script writes and trims
  # atomically and deletes evicted ids from both hashes in the same step.
  #
  # The pre-coalescing trail, secret_activity_events (members are event JSON
  # with a nonce), is read-only: never written, merged in at read time, and
  # left to age out under its own cap. No migration.
  #
  # Design notes:
  # - Best-effort: the trail never drives behavior, and a failed write must
  #   never break the calling path (callers guard).
  # - Collection is switchable: features.secret_activity.collect false
  #   pauses recording (GDPR data minimization: no events come to exist)
  #   while leaving existing events readable. UI/API exposure is the
  #   separate organizations.audit_logs_enabled axis (#3985).
  # - No TTL: organizations are permanent records; the caps are the bound.
  # - Coalescing keeps the first and last time and the count of a repeated
  #   fetch, not each occurrence's time. Lifecycle events (created,
  #   revealed, burned, expired, ...) are never coalesced.
  module SecretActivity
    Familia::Base.add_feature self, :secret_activity

    # Newest events retained per partition, absent configuration.
    DEFAULT_MAX_EVENTS       = 10_000
    DEFAULT_MAX_GUEST_EVENTS = 10_000

    # Floor for the configurable caps: a paid audit trail that silently
    # retains almost nothing is worse than no trail at all.
    MIN_MAX_EVENTS = 100

    # Seconds of the coalescing window, absent configuration. 0 disables
    # coalescing (every event is its own row).
    DEFAULT_COALESCE_WINDOW = 3600

    # Fetch kinds whose identical repeats inside one window collapse into a
    # single counted row. Everything else is recorded once per occurrence.
    COALESCIBLE_KINDS = %w[
      secret_get status_get previewed creator_status_get reveal_failed_undecryptable
    ].freeze

    # The event attributes that make two events "identical", besides kind
    # and the time bucket. Two requests from different networks differ in
    # net_ip_hash, so they never merge.
    IDENTITY_ATTRS = %w[
      receipt secret actor actor_id net_ip_hash net_ua_partial net_country domain_id
    ].freeze

    PARTITIONS = [:member, :guest].freeze

    ID_PREFIX = 'e1:'

    # KEYS: partition zset, detail hash, count hash
    # ARGV: id, score (at), detail JSON, cap
    # Returns the id's count after the write.
    WRITE_SCRIPT = <<~LUA
      redis.call('HSETNX', KEYS[2], ARGV[1], ARGV[3])
      local count = redis.call('HINCRBY', KEYS[3], ARGV[1], 1)
      redis.call('ZADD', KEYS[1], 'GT', ARGV[2], ARGV[1])
      local over = redis.call('ZCARD', KEYS[1]) - tonumber(ARGV[4])
      if over > 0 then
        local evicted = redis.call('ZRANGE', KEYS[1], 0, over - 1)
        for _, id in ipairs(evicted) do
          redis.call('HDEL', KEYS[2], id)
          redis.call('HDEL', KEYS[3], id)
        end
        redis.call('ZREMRANGEBYRANK', KEYS[1], 0, over - 1)
      end
      return count
    LUA

    WRITE_SCRIPT_SHA = Digest::SHA1.hexdigest(WRITE_SCRIPT)

    class << self
      # The caps and window in force. Set at boot by .configure!.
      def settings
        @settings ||= {
          max_events: DEFAULT_MAX_EVENTS,
          max_guest_events: DEFAULT_MAX_GUEST_EVENTS,
          coalesce_window: DEFAULT_COALESCE_WINDOW,
        }.freeze
      end

      def max_events = settings[:max_events]
      def max_guest_events = settings[:max_guest_events]
      def coalesce_window = settings[:coalesce_window]

      # Apply the configured caps (features.secret_activity.max_events and
      # .max_guest_events, each floored at MIN_MAX_EVENTS) and coalescing
      # window (features.secret_activity.coalesce_window, seconds; 0 turns
      # coalescing off). Called at boot by ConfigureSecretActivity. The caps
      # are read at write time, so a new value applies to every
      # organization from its next write: lowering a cap deletes (not
      # hides) that partition's oldest events.
      #
      # Deliberately unrescued: a malformed value is a configuration error,
      # and the caller owns the fallback policy (the boot initializer
      # rescues to the defaults).
      #
      # @return [Integer] the applied member cap.
      # @raise [ArgumentError, TypeError] when a value is not Integer-able.
      def configure!(max_events, max_guest_events: DEFAULT_MAX_GUEST_EVENTS,
                     coalesce_window: DEFAULT_COALESCE_WINDOW)
        @settings = {
          max_events: [Integer(max_events), MIN_MAX_EVENTS].max,
          max_guest_events: [Integer(max_guest_events), MIN_MAX_EVENTS].max,
          coalesce_window: [Integer(coalesce_window), 0].max,
        }.freeze

        @settings[:max_events]
      end

      # The cap for a partition.
      def cap_for(partition)
        partition == :guest ? max_guest_events : max_events
      end

      # Deterministic event id over the normalized identity.
      #
      # Coalescible kinds use floor(at / window) as the bucket, so repeats
      # of the same fetch inside one window share an id. Every other kind,
      # and every kind when the window is 0, uses a random bucket.
      #
      # @param kind [String]
      # @param attrs [Hash{String=>Object}] the event's attributes
      # @param at [Float] epoch seconds
      # @param window [Integer] coalescing window in seconds
      # @return [String] "e1:" + 20 hex chars
      def event_id(kind, attrs, at:, window: coalesce_window)
        bucket = if window.positive? && COALESCIBLE_KINDS.include?(kind)
                   (at.to_f / window).floor.to_s
                 else
                   SecureRandom.hex(8)
                 end

        identity = [kind, *IDENTITY_ATTRS.map { |name| attrs[name].to_s }, bucket]
        ID_PREFIX + Digest::SHA256.hexdigest(identity.join("\x1F"))[0, 20]
      end
    end

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      # Read-only legacy trail (see the Storage notes above).
      base.sorted_set :secret_activity_events

      base.sorted_set :secret_activity_member
      base.sorted_set :secret_activity_guest
      base.hashkey :secret_activity_detail
      base.hashkey :secret_activity_count

      base.include InstanceMethods
    end

    module InstanceMethods
      # Record a secret activity event on the organization's trail.
      #
      # @param kind [String, Symbol] what happened. The receipt fan-out
      #   emits: 'created', 'status_get' / 'secret_get' (a third party
      #   fetched the status/secret link), 'previewed' (the creator opened
      #   their own secret link), 'creator_status_get' (the creator checked
      #   their own secret's status), 'receipt_viewed' (the creator's
      #   receipt/metadata page was loaded), 'revealed', 'burned', 'expired',
      #   'orphaned', 'reveal_failed_undecryptable'.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @param partition [Symbol] :member, or :guest for events on a receipt
      #   a guest created.
      # @param attrs [Hash] additional context (receipt/secret shortids,
      #   actor when known). Keep values short and non-sensitive: never
      #   include secret content, full identifiers, or passphrases.
      # @return [Hash, nil] the recorded event with its 'id' and 'count', or
      #   nil when kind is blank or collection is paused.
      def record_secret_activity_event(kind, at: Familia.now, partition: :member, **attrs)
        return if kind.to_s.empty?
        # Default-true contract: only an explicit false pauses collection —
        # a missing key (older config file) must still record. Compare on
        # the string form so a hand-edited config that yields 'false'
        # (quoted/ERB-stringified) still disables the flag.
        return if OT.conf.get('features.secret_activity.collect', true).to_s == 'false'

        partition = :member unless PARTITIONS.include?(partition)
        kind      = kind.to_s
        at        = at.to_f
        attrs     = attrs.transform_keys(&:to_s).except('id', 'count', 'first_at', 'last_at', 'at', 'nonce')
        id        = SecretActivity.event_id(kind, attrs, at: at)
        detail    = { 'kind' => kind, 'first_at' => at }.merge(attrs)

        count = run_write_script(
          keys: [secret_activity_partition(partition).dbkey, secret_activity_detail.dbkey,
                 secret_activity_count.dbkey],
          argv: [id, at, Familia::JsonSerializer.dump(detail), SecretActivity.cap_for(partition)],
        )

        detail.merge('id' => id, 'count' => count.to_i, 'last_at' => at, 'at' => at)
      end

      # @return [Integer] retained rows across both partitions and the
      #   legacy trail (a coalesced row counts once).
      def secret_activity_event_count
        secret_activity_member.element_count +
          secret_activity_guest.element_count +
          secret_activity_events.element_count
      end

      # Whether any partition has reached its cap, so older events have
      # been (or are about to be) trimmed. The legacy trail had the member
      # cap before it became read-only.
      #
      # @return [Boolean]
      def secret_activity_trimmed?
        feature = Onetime::Organization::Features::SecretActivity
        secret_activity_member.element_count >= feature.cap_for(:member) ||
          secret_activity_guest.element_count >= feature.cap_for(:guest) ||
          secret_activity_events.element_count >= feature.cap_for(:member)
      end

      # A page of secret activity events, newest first, merged from both
      # partitions and the legacy trail.
      #
      # @param offset [Integer] events to skip from the newest end.
      # @param limit [Integer] maximum events to return.
      # @return [Array<Hash>] events (string keys) newest-first. Each carries
      #   'id', 'kind', 'count', 'first_at', 'last_at', 'at' (= last_at, kept
      #   for older readers) and any recorded context. Legacy events have
      #   count 1, first_at = last_at = at and their nonce as id.
      def secret_activity_events_page(offset: 0, limit: 50)
        offset = [offset.to_i, 0].max
        limit  = limit.to_i.clamp(1, 200)
        depth  = offset + limit

        entries = PARTITIONS.flat_map do |partition|
          zrevrange_with_scores(secret_activity_partition(partition).dbkey, depth).map do |id, score|
            [score, id, nil]
          end
        end

        legacy = zrevrange_with_scores(secret_activity_events.dbkey, depth).map do |raw, score|
          event = Familia::JsonSerializer.parse(raw)
          [score, event['nonce'].to_s, event]
        end

        page = (entries + legacy).sort_by { |score, id, _| [-score, id] }.slice(offset, limit) || []
        hydrate(page)
      end

      private

      def secret_activity_partition(partition)
        partition == :guest ? secret_activity_guest : secret_activity_member
      end

      def run_write_script(keys:, argv:)
        client = secret_activity_detail.dbclient
        client.evalsha(WRITE_SCRIPT_SHA, keys: keys, argv: argv)
      rescue Redis::CommandError => ex
        raise unless ex.message.start_with?('NOSCRIPT')

        client.eval(WRITE_SCRIPT, keys: keys, argv: argv)
      end

      def zrevrange_with_scores(key, depth)
        secret_activity_detail.dbclient.zrevrange(key, 0, depth - 1, with_scores: true)
      end

      # Turns [score, id, legacy_event_or_nil] entries into records, with one
      # HMGET per hash for the coalesced ids.
      def hydrate(page)
        ids             = page.filter_map { |_, id, legacy| id unless legacy }
        details, counts = if ids.empty?
                            [[], []]
                          else
                            client = secret_activity_detail.dbclient
                            [client.hmget(secret_activity_detail.dbkey, *ids),
                             client.hmget(secret_activity_count.dbkey, *ids)]
                          end
        lookup          = ids.each_with_index.to_h { |id, i| [id, [details[i], counts[i]]] }

        page.filter_map do |score, id, legacy|
          if legacy
            legacy.except('nonce').merge(
              'id' => id,
              'count' => 1,
              'first_at' => legacy['at'],
              'last_at' => legacy['at'],
            )
          else
            raw_detail, raw_count = lookup[id]
            # A row whose detail was removed by a concurrent trim is skipped.
            next if raw_detail.nil?

            Familia::JsonSerializer.parse(raw_detail).merge(
              'id' => id, 'count' => [raw_count.to_i, 1].max, 'last_at' => score, 'at' => score,
            )
          end
        end
      end
    end
  end
end
