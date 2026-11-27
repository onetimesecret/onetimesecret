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
  # and stays its own row. Six keys per organization:
  #
  #   secret_activity_member    ZSET  id -> last_at. Events on receipts with
  #                                   an owner, events with no receipt
  #                                   context, and migrated legacy events.
  #   secret_activity_guest     ZSET  id -> last_at. Events on receipts a
  #                                   guest created (no owner), whoever the
  #                                   actor is.
  #   secret_activity_detail    HASH  id -> JSON of the first occurrence's
  #                                   attributes.
  #   secret_activity_count     HASH  id -> occurrences.
  #   secret_activity_first_at  HASH  id -> earliest occurrence (epoch s).
  #   secret_activity_trim      HASH  <partition>:evicted -> rows removed by
  #                                   the cap; <partition>:last_evicted_at.
  #
  # The two partitions have their own caps (max_events, max_guest_events),
  # so guests creating secrets on a public custom domain can only evict
  # guest events, never the members'. One Lua script writes and trims
  # atomically: count, earliest and latest time move together, and evicted
  # ids leave every hash in the same step. The trim hash records only real
  # evictions, so "trimmed" never depends on how full a partition is.
  #
  # The pre-coalescing trail, secret_activity_events (members are event JSON
  # with a nonce), is migrated into the member partition on the
  # organization's first write or read after the upgrade (and by
  # migrations/2026-11-27/20261127_01_migrate_secret_activity_legacy.rb):
  # each row becomes id "l1:<nonce>", count 1, its JSON as the detail, then
  # the legacy key is deleted and the member cap applies to the merged rows.
  # The migration is one Lua script, so it is atomic and a rerun is a no-op.
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

    # Prefix of the ids given to migrated legacy rows ("l1:" + nonce), so
    # they cannot collide with event ids.
    LEGACY_ID_PREFIX = 'l1:'

    # Shared Lua. Key order for both scripts:
    #   1 member zset, 2 guest zset, 3 detail, 4 count, 5 first_at, 6 trim,
    #   7 legacy zset
    LUA_HELPERS = <<~LUA
      local function trim(zkey, cap, name)
        local over = redis.call('ZCARD', zkey) - cap
        if over <= 0 then return 0 end
        local evicted = redis.call('ZRANGE', zkey, 0, over - 1, 'WITHSCORES')
        local newest = 0
        for i = 1, #evicted, 2 do
          redis.call('HDEL', KEYS[3], evicted[i])
          redis.call('HDEL', KEYS[4], evicted[i])
          redis.call('HDEL', KEYS[5], evicted[i])
          newest = evicted[i + 1]
        end
        redis.call('ZREMRANGEBYRANK', zkey, 0, over - 1)
        redis.call('HINCRBY', KEYS[6], name .. ':evicted', over)
        local prior = redis.call('HGET', KEYS[6], name .. ':last_evicted_at')
        if not prior or tonumber(newest) > tonumber(prior) then
          redis.call('HSET', KEYS[6], name .. ':last_evicted_at', newest)
        end
        return over
      end

      local function migrate_legacy()
        if redis.call('EXISTS', KEYS[7]) == 0 then return 0 end
        local rows = redis.call('ZRANGE', KEYS[7], 0, -1, 'WITHSCORES')
        for i = 1, #rows, 2 do
          local raw, score = rows[i], rows[i + 1]
          local ok, event = pcall(cjson.decode, raw)
          local nonce = ok and type(event) == 'table' and event['nonce']
          local id
          if type(nonce) == 'string' and nonce ~= '' then
            id = '#{LEGACY_ID_PREFIX}' .. nonce
          else
            id = '#{LEGACY_ID_PREFIX}' .. redis.sha1hex(raw)
          end
          redis.call('HSETNX', KEYS[3], id, raw)
          redis.call('HSETNX', KEYS[4], id, 1)
          redis.call('HSETNX', KEYS[5], id, score)
          redis.call('ZADD', KEYS[1], 'NX', score, id)
        end
        redis.call('DEL', KEYS[7])
        return #rows / 2
      end
    LUA

    # ARGV: partition name ('member' | 'guest'), id, at, detail JSON,
    #       partition cap, member cap
    # Returns {count, first_at} for the id after the write.
    WRITE_SCRIPT = <<~LUA
      #{LUA_HELPERS}
      local zkey = ARGV[1] == 'guest' and KEYS[2] or KEYS[1]
      local id, at = ARGV[2], ARGV[3]
      local migrated = migrate_legacy()
      redis.call('HSETNX', KEYS[3], id, ARGV[4])
      local count = redis.call('HINCRBY', KEYS[4], id, 1)
      local first = redis.call('HGET', KEYS[5], id)
      if not first or tonumber(at) < tonumber(first) then
        redis.call('HSET', KEYS[5], id, at)
        first = at
      end
      redis.call('ZADD', zkey, 'GT', at, id)
      trim(zkey, tonumber(ARGV[5]), ARGV[1])
      if migrated > 0 and zkey ~= KEYS[1] then
        trim(KEYS[1], tonumber(ARGV[6]), 'member')
      end
      return {count, first}
    LUA

    # ARGV: member cap. Returns the number of legacy rows migrated.
    MIGRATE_SCRIPT = <<~LUA
      #{LUA_HELPERS}
      local migrated = migrate_legacy()
      if migrated > 0 then trim(KEYS[1], tonumber(ARGV[1]), 'member') end
      return migrated
    LUA

    SCRIPT_SHAS = {
      WRITE_SCRIPT => Digest::SHA1.hexdigest(WRITE_SCRIPT),
      MIGRATE_SCRIPT => Digest::SHA1.hexdigest(MIGRATE_SCRIPT),
    }.freeze

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

      # Legacy trail, migrated on first use (see the Storage notes above).
      base.sorted_set :secret_activity_events

      base.sorted_set :secret_activity_member
      base.sorted_set :secret_activity_guest
      base.hashkey :secret_activity_detail
      base.hashkey :secret_activity_count
      base.hashkey :secret_activity_first_at
      base.hashkey :secret_activity_trim

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
        detail    = { 'kind' => kind }.merge(attrs)

        count, first_at = run_script(
          WRITE_SCRIPT,
          argv: [partition.to_s, id, at, Familia::JsonSerializer.dump(detail),
                 SecretActivity.cap_for(partition), SecretActivity.max_events],
        )

        detail.merge(
          'id' => id,
          'nonce' => id,
          'count' => count.to_i,
          'first_at' => first_at.to_f,
          'last_at' => at,
          'at' => at,
        )
      end

      # Move the legacy trail into the member partition and apply the member
      # cap. Idempotent: with no legacy key it does nothing. Runs on the
      # first write or read after the upgrade, and from the migration.
      #
      # @return [Integer] legacy rows migrated by this call.
      def migrate_legacy_secret_activity!
        return 0 unless secret_activity_events.exists?

        run_script(MIGRATE_SCRIPT, argv: [SecretActivity.max_events]).to_i
      end

      # @return [Integer] retained rows across both partitions and any
      #   not-yet-migrated legacy trail (a coalesced row counts once).
      def secret_activity_event_count
        secret_activity_member.element_count +
          secret_activity_guest.element_count +
          secret_activity_events.element_count
      end

      # Whether the caps have removed any rows from this organization's
      # trail. Records only what the write script actually evicted, so
      # reaching a cap exactly is not "trimmed", and raising a cap after an
      # eviction does not clear it. Rows the pre-upgrade trail dropped under
      # its own cap left no record and are not counted.
      #
      # @return [Boolean]
      def secret_activity_trimmed?
        trim = secret_activity_trim
        trim.dbclient.hmget(trim.dbkey, *PARTITIONS.map { |partition| "#{partition}:evicted" })
          .any? { |value| value.to_i.positive? }
      end

      # A page of secret activity events, newest first, merged from both
      # partitions.
      #
      # The order is score descending, then id descending: the order
      # ZREVRANGE returns ties in, so the rows selected from each partition
      # are always the leading rows of the merged order and pages neither
      # repeat nor skip a tied row.
      #
      # @param offset [Integer] events to skip from the newest end.
      # @param limit [Integer] maximum events to return.
      # @return [Array<Hash>] events (string keys) newest-first. Each carries
      #   'id', 'nonce' ('id' for new rows, the original nonce for migrated
      #   legacy rows; kept for clients that predate 'id'), 'kind', 'count',
      #   'first_at', 'last_at', 'at' (= last_at) and any recorded context.
      def secret_activity_events_page(offset: 0, limit: 50)
        offset = [offset.to_i, 0].max
        limit  = limit.to_i.clamp(1, 200)
        depth  = offset + limit

        migrate_legacy_secret_activity!

        entries = PARTITIONS.flat_map do |partition|
          secret_activity_detail.dbclient
            .zrevrange(secret_activity_partition(partition).dbkey, 0, depth - 1, with_scores: true)
        end

        page = entries.sort { |(a_id, a_score), (b_id, b_score)| [b_score, b_id] <=> [a_score, a_id] }
        hydrate(page.slice(offset, limit) || [])
      end

      private

      def secret_activity_partition(partition)
        partition == :guest ? secret_activity_guest : secret_activity_member
      end

      def script_keys
        [secret_activity_member, secret_activity_guest, secret_activity_detail, secret_activity_count,
         secret_activity_first_at, secret_activity_trim, secret_activity_events].map(&:dbkey)
      end

      def run_script(script, argv:)
        client = secret_activity_detail.dbclient
        client.evalsha(SCRIPT_SHAS.fetch(script), keys: script_keys, argv: argv)
      rescue Redis::CommandError => ex
        raise unless ex.message.start_with?('NOSCRIPT')

        client.eval(script, keys: script_keys, argv: argv)
      end

      # Turns [id, score] entries into records, with one HMGET per hash.
      def hydrate(page)
        return [] if page.empty?

        ids                     = page.map(&:first)
        client                  = secret_activity_detail.dbclient
        details, counts, firsts = [secret_activity_detail, secret_activity_count, secret_activity_first_at]
          .map { |field| client.hmget(field.dbkey, *ids) }

        page.each_with_index.filter_map do |(id, score), i|
          # A row whose detail was removed by a concurrent trim is skipped.
          next if details[i].nil?

          detail = Familia::JsonSerializer.parse(details[i])
          # Migrated legacy rows keep their original nonce.
          nonce  = id.start_with?(LEGACY_ID_PREFIX) ? detail['nonce'].to_s : id
          detail.merge(
            'id' => id,
            'nonce' => nonce.empty? ? id : nonce,
            'count' => [counts[i].to_i, 1].max,
            'first_at' => (firsts[i] || score).to_f,
            'last_at' => score,
            'at' => score,
          )
        end
      end
    end
  end
end
