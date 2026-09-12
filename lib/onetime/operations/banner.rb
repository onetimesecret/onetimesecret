# lib/onetime/operations/banner.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operations — see decision D3 in
# lib/onetime/operations/README.md. The global broadcast banner is a site-wide
# runtime state with no single domain owner (it is read at boot by the
# CheckGlobalBanner initializer and surfaced by GlobalBroadcast.vue), so it
# lives in the central operations home rather than an app-scoped one. Loaded at the call site (colonel logic + the `bin/ots
# banner` CLI), so require the audit dependency explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    # Shared backing-store facts for the broadcast-banner ops. The banner is a
    # single string stored under {KEY} in DB {DB} (Valkey/Redis DB 0), optionally
    # with a TTL. This is the SAME key the `CheckGlobalBanner` initializer reads at
    # boot and the `bin/ots banner` CLI has always used — the value written here is
    # bit-for-bit what the CLI wrote (raw HTML; the frontend sanitizes to <a> tags
    # on render, this layer never rewrites the content).
    module BannerState
      # Redis/Valkey key holding the banner content. Single source of truth for the
      # three ops below; the CLI keeps its own identical literal for its dry-run
      # display text (preserved bit-for-bit).
      KEY = 'global_banner'

      # Sidecar key holding the banner AUDIENCE scope. Stored separately (not folded
      # into the content value) so {KEY} stays a bit-for-bit plain HTML string — the
      # CLI, the boot initializer, and any external reader keep working unchanged.
      # Written/expired in lockstep with {KEY} (same TTL, one MULTI/EXEC) so scope
      # never outlives — or arrives apart from — the banner it describes.
      SCOPE_KEY = 'global_banner:scope'

      # Audience scopes the banner can target (surfaced to the frontend, which owns
      # the page-audience matching). See GlobalBroadcast/BaseLayout:
      #   all           – every page, including recipient (reveal) + custom domains
      #   no_recipient  – every page EXCEPT recipient pages; suppressed on custom domains
      #   workspace     – authenticated workspace pages only
      VALID_SCOPES = %w[all no_recipient workspace].freeze

      # Scope assumed when the sidecar key is absent/blank/invalid. Chosen so
      # pre-existing string-only banners (no sidecar) keep off custom domains and
      # off recipient pages without a migration.
      DEFAULT_SCOPE = 'no_recipient'

      # Database index the banner lives in (DB 0, matching the CLI + initializer).
      DB = 0

      # Seconds a process serves its in-memory banner before re-reading Redis.
      # Bounds cross-process propagation of SetBanner/ClearBanner: without this,
      # a banner published by one Puma worker/container was invisible to every
      # other process until restart (only the handling process refreshed its
      # runtime state). Worst case ~2 Redis GETs/min/process.
      # `unless defined?` keeps this idempotent across code reloads (same
      # pattern as Session::SECURE_COOKIE_WARN_INTERVAL).
      CACHE_TTL = 30 unless defined?(CACHE_TTL)

      # Process-wide staleness clock for the TTL re-read. Holds the monotonic
      # timestamp (Process::CLOCK_MONOTONIC) of the last refresh ATTEMPT; nil
      # means "refresh on next read" (fresh boot before the initializer runs,
      # or after {reset_cache!}). The Mutex guards only the timestamp claim —
      # it is NEVER held across Redis I/O. `||=` keeps these idempotent across
      # code reloads.
      @cache_mutex  ||= Mutex.new
      @refreshed_at ||= nil

      class << self
        # @return [Mutex] guard for the staleness clock (timestamp only, no I/O)
        attr_reader :cache_mutex
      end

      # Coerce a raw sidecar value to a valid scope, collapsing blank/unknown to
      # {DEFAULT_SCOPE}. Shared by GetBanner (read path) and the initializer.
      def self.normalize_scope(raw)
        value = raw.to_s.strip
        VALID_SCOPES.include?(value) ? value : DEFAULT_SCOPE
      end

      # Re-read {KEY} + {SCOPE_KEY} into Runtime.features when the process-local
      # copy is older than {CACHE_TTL}. Called from the `OT.global_banner` /
      # `OT.global_banner_scope` accessors (the page-render path), so it must
      # never raise and must not hit Redis on every request.
      #
      # Exactly one thread claims the refresh at the TTL boundary (the claim
      # stamps the clock BEFORE the Redis read, so concurrent threads — and a
      # dead Redis — cannot stampede; losers serve the last-known value).
      #
      # Note nil is a VALID cached state: key-absent maps to a nil banner, so a
      # ClearBanner from another process propagates within the same TTL.
      #
      # @return [void]
      def self.refresh_if_stale!
        now     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        claimed = cache_mutex.synchronize do
          last = @refreshed_at
          if last.nil? || (now - last) >= CACHE_TTL
            @refreshed_at = now
            true
          else
            false
          end
        end
        refresh! if claimed
        nil
      end

      # Unconditionally re-read the banner pair from Redis into Runtime.features.
      # ONE merged update: content + scope land in the same immutable Features
      # snapshot, so a reader can never see a new banner beside a stale scope.
      # Fail-soft: on any error we log and keep serving the last in-memory value
      # (several unit specs run without OT.boot!, so a missing connection
      # provider must not 500 a page render).
      #
      # @return [void]
      def self.refresh!
        db                 = Familia.dbclient(DB)
        # One MGET: the pair arrives as a single atomic snapshot, so this read
        # can never combine one banner's content with another banner's scope
        # while a concurrent SetBanner/ClearBanner (both MULTI) lands.
        content, raw_scope = db.mget(KEY, SCOPE_KEY)
        Onetime::Runtime.update_features(
          global_banner: content,
          global_banner_scope: normalize_scope(raw_scope),
        )
        nil
      rescue StandardError => ex
        OT.le "[BannerState] banner refresh failed (serving cached value): #{ex.class}: #{ex.message}"
        nil
      end

      # Stamp the staleness clock "fresh now". Called by SetBanner/ClearBanner
      # (whose eager Runtime.update_features already made THIS process correct)
      # and by the boot initializer, so a just-primed process does not
      # immediately re-read Redis.
      #
      # @return [void]
      def self.prime_cache!
        cache_mutex.synchronize { @refreshed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        nil
      end

      # Force the next accessor read to re-read Redis (test hook — lets tryouts
      # cross the TTL boundary without sleeping).
      #
      # @return [void]
      def self.reset_cache!
        cache_mutex.synchronize { @refreshed_at = nil }
        nil
      end
    end

    # Read the current broadcast banner. READ-ONLY — records NO audit event
    # (CONTRACT 4: only mutating verbs audit). The single implementation behind
    # `bin/ots banner show` and the colonel `GET /api/colonel/banner` endpoint.
    #
    # Stateless, single `#call`, returns an immutable {Result}. `ttl` is normalised
    # to nil for a persistent (or absent) banner — mirroring the CLI's
    # `ttl.negative? ? nil : ttl` — so callers never see Redis's -1/-2 sentinels.
    class GetBanner
      # @!attribute active [r]
      #   @return [Boolean] true when a non-empty banner is set.
      # @!attribute scope [r]
      #   @return [String] audience scope (always one of {BannerState::VALID_SCOPES}).
      Result = Data.define(:content, :ttl, :active, :scope, :key, :database)

      # @return [Result]
      def call
        db                 = Familia.dbclient(BannerState::DB)
        # MGET keeps content + scope one atomic snapshot (matching
        # {BannerState.refresh!}). The TTL is a separate read: worst case it
        # reflects a banner published a beat later, which only skews the
        # advisory seconds-remaining display, never the content/scope pairing.
        content, raw_scope = db.mget(BannerState::KEY, BannerState::SCOPE_KEY)
        ttl                = db.ttl(BannerState::KEY)
        scope              = BannerState.normalize_scope(raw_scope)

        Result.new(
          content: content,
          # Redis returns -1 (no expiry) / -2 (no key); collapse both to nil so the
          # wire shape is "seconds remaining, or null for persistent/absent".
          ttl: ttl.negative? ? nil : ttl,
          active: !content.nil? && !content.empty?,
          scope: scope,
          key: BannerState::KEY,
          database: BannerState::DB,
        )
      end
    end

    # Publish / update the global broadcast banner as an operator action, and
    # record it in the admin audit trail (CONTRACT 4).
    #
    # The SINGLE implementation of the set verb: `bin/ots banner set --apply` and
    # the colonel `POST /api/colonel/banner` endpoint are thin adapters over it.
    # The Redis write is IDENTICAL to the prior inline CLI call
    # (`db.set` / `db.setex` + `Onetime::Runtime.update_features`); the op adds
    # exactly one {Onetime::ColonelAuditEvent} per successful publish.
    #
    # Content is stored VERBATIM (raw HTML) — the CLI never sanitised on write and
    # neither does this op, so CLI/UI render identically. Callers (the colonel
    # logic) own any max-length / HTTP validation; the op only guards against an
    # empty write (a backstop mirroring the CLI's own empty check).
    #
    # Setting the banner ALWAYS mutates (it overwrites whatever was there), so it
    # always audits — there is no idempotent no-op branch to suppress.
    class SetBanner
      include Onetime::AuditedFailure

      AUDIT_VERB = 'banner.set'

      # This op has NO refusal STATUS — blank content and an invalid scope both
      # RAISE (ArgumentError), and so does a Redis failure. Content + scope are
      # written in ONE MULTI/EXEC, so a failure applies neither (no torn pair on
      # a site-wide, every-visitor surface); the success record sits after the
      # transaction. Records one `result: :failure` and re-raises.
      audit_failures :call,
        verb: AUDIT_VERB,
        target: BannerState::KEY,
        detail: -> { { ttl: @ttl, scope: @scope.to_s } }

      # @!attribute status [r]
      #   @return [Symbol] :success
      Result = Data.define(:status, :content, :ttl, :scope)

      # @param content [String] the banner body (raw HTML; stored verbatim).
      # @param actor [String, #extid, #email] acting admin's PUBLIC identity
      #   (colonel extid/email, or the CLI sentinel). Never an internal objid.
      # @param ttl [Integer, nil] optional auto-expiry in seconds; nil = persistent.
      # @param scope [String] audience scope; one of {BannerState::VALID_SCOPES}.
      def initialize(content:, actor:, ttl: nil, scope: BannerState::DEFAULT_SCOPE)
        @content = content
        @actor   = actor
        @ttl     = ttl
        @scope   = scope
      end

      # @return [Result]
      # @raise [ArgumentError] when content is blank or scope is invalid
      #   (defensive backstops mirroring the empty-content guard).
      def call
        text = @content.to_s
        raise ArgumentError, 'banner content is empty' if text.empty?

        scope = @scope.to_s
        unless BannerState::VALID_SCOPES.include?(scope)
          raise ArgumentError, "invalid banner scope: #{scope.inspect}"
        end

        db = Familia.dbclient(BannerState::DB)
        # Write content + scope with IDENTICAL TTL semantics so the sidecar can
        # never outlive (or persist past) the banner it describes. One
        # MULTI/EXEC so the pair applies atomically: a reader (MGET in
        # BannerState.refresh!) can never observe new content beside the
        # previous banner's scope, and a failure applies neither key.
        db.multi do |tx|
          if @ttl
            tx.setex(BannerState::KEY, @ttl, text)
            tx.setex(BannerState::SCOPE_KEY, @ttl, scope)
          else
            tx.set(BannerState::KEY, text)
            tx.set(BannerState::SCOPE_KEY, scope)
          end
        end

        # Refresh THIS process's runtime state immediately, and stamp the
        # staleness clock so the publishing process serves the new value without
        # a redundant re-read. Other processes pick the change up via
        # {BannerState.refresh_if_stale!} within {BannerState::CACHE_TTL}s.
        Onetime::Runtime.update_features(global_banner: text, global_banner_scope: scope)
        BannerState.prime_cache!

        # One audit event per successful publish. The banner content is
        # non-secret (it is shown to every visitor), so it is safe to record; the
        # ColonelAuditEvent redactor still truncates overlong values.
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: BannerState::KEY,
          result: :success,
          detail: { ttl: @ttl, scope: scope, length: text.length, content: text },
        )

        Result.new(status: :success, content: text, ttl: @ttl, scope: scope)
      end
    end

    # Clear the global broadcast banner as an operator action, and record it in the
    # admin audit trail (CONTRACT 4).
    #
    # The SINGLE implementation of the clear verb: `bin/ots banner clear --apply`
    # and the colonel `DELETE /api/colonel/banner` endpoint are thin adapters over
    # it. The Redis delete is IDENTICAL to the prior inline CLI call (`db.del` +
    # `Onetime::Runtime.update_features(global_banner: nil)`); the op adds exactly
    # one {Onetime::ColonelAuditEvent} per successful clear.
    #
    # Stateless, single `#call`, returns an immutable {Result}. Clearing when no
    # banner is set returns `status: :not_set` and records NO audit event —
    # nothing mutated AND nothing was refused. The discriminator is the adapter:
    # colonel `ClearBanner` deliberately returns 200 with `cleared: false` for
    # this status ("not surfaced as an error", so a benign TTL race is not a
    # failure), unlike colonel `RemoveEmailSuppression`, whose `:not_found` is a
    # 404 and IS therefore recorded as a refusal.
    class ClearBanner
      include Onetime::AuditedFailure

      AUDIT_VERB = 'banner.clear'

      # Both deletes ride one MULTI/EXEC (a failure removes neither key, so the
      # scope sidecar can never linger behind a deleted banner), but the runtime
      # refresh and the success record still sit after the transaction. Records
      # one `result: :failure` and re-raises.
      audit_failures :call,
        verb: AUDIT_VERB,
        target: BannerState::KEY

      # @!attribute status [r]
      #   @return [Symbol] :success (cleared) or :not_set (no-op)
      Result = Data.define(:status, :cleared, :content)

      # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
      def initialize(actor:)
        @actor = actor
      end

      # @return [Result]
      def call
        db      = Familia.dbclient(BannerState::DB)
        current = db.get(BannerState::KEY)

        if current.nil? || current.empty?
          return Result.new(status: :not_set, cleared: false, content: nil)
        end

        # One MULTI/EXEC: the pair disappears atomically, so a concurrent MGET
        # reader can never see the scope sidecar outliving the banner.
        db.multi do |tx|
          tx.del(BannerState::KEY)
          tx.del(BannerState::SCOPE_KEY)
        end
        # Immediate local refresh + clock stamp (mirrors SetBanner); other
        # processes converge to nil via the TTL re-read.
        Onetime::Runtime.update_features(global_banner: nil, global_banner_scope: BannerState::DEFAULT_SCOPE)
        BannerState.prime_cache!

        # One audit event per successful mutation. No detail: the fact of the clear
        # is the whole record (the cleared content is not re-logged here).
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: BannerState::KEY,
          result: :success,
        )

        Result.new(status: :success, cleared: true, content: current)
      end
    end
  end
end
