# lib/onetime/operations/banner.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operations — see decision D3 in
# lib/onetime/operations/README.md. The global broadcast banner is a site-wide
# runtime state with no single domain owner (it is read at boot by the
# CheckGlobalBanner initializer and surfaced by GlobalBroadcast.vue), so — like
# {Onetime::Operations::BanIP} — it lives in the central operations home rather
# than an app-scoped one. Loaded at the call site (colonel logic + the `bin/ots
# banner` CLI), so require the audit dependency explicitly.
require 'onetime/models/admin_audit_event'

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
      # Written/expired in lockstep with {KEY} (same TTL) so scope never outlives
      # the banner it describes.
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

      # Coerce a raw sidecar value to a valid scope, collapsing blank/unknown to
      # {DEFAULT_SCOPE}. Shared by GetBanner (read path) and the initializer.
      def self.normalize_scope(raw)
        value = raw.to_s.strip
        VALID_SCOPES.include?(value) ? value : DEFAULT_SCOPE
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
        db      = Familia.dbclient(BannerState::DB)
        content = db.get(BannerState::KEY)
        ttl     = db.ttl(BannerState::KEY)
        scope   = BannerState.normalize_scope(db.get(BannerState::SCOPE_KEY))

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
    # exactly one {Onetime::AdminAuditEvent} per successful publish.
    #
    # Content is stored VERBATIM (raw HTML) — the CLI never sanitised on write and
    # neither does this op, so CLI/UI render identically. Callers (the colonel
    # logic) own any max-length / HTTP validation; the op only guards against an
    # empty write (a backstop mirroring the CLI's own empty check).
    #
    # Setting the banner ALWAYS mutates (it overwrites whatever was there), so it
    # always audits — there is no idempotent no-op branch to suppress.
    class SetBanner
      AUDIT_VERB = 'banner.set'

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
        # never outlive (or persist past) the banner it describes.
        if @ttl
          db.setex(BannerState::KEY, @ttl, text)
          db.setex(BannerState::SCOPE_KEY, @ttl, scope)
        else
          db.set(BannerState::KEY, text)
          db.set(BannerState::SCOPE_KEY, scope)
        end

        # Refresh THIS process's runtime state (parity with the CLI note that the
        # refresh reaches only the current process; other processes re-read at
        # boot). Kept identical to the extracted CLI behaviour.
        Onetime::Runtime.update_features(global_banner: text, global_banner_scope: scope)

        # One audit event per successful publish. The banner content is
        # non-secret (it is shown to every visitor), so it is safe to record; the
        # AdminAuditEvent redactor still truncates overlong values.
        Onetime::AdminAuditEvent.record(
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
    # one {Onetime::AdminAuditEvent} per successful clear.
    #
    # Stateless, single `#call`, returns an immutable {Result}. Clearing when no
    # banner is set returns `status: :not_set` and records NO audit event (nothing
    # mutated) — the "only audit an actual change" rule shared with UnbanIP.
    class ClearBanner
      AUDIT_VERB = 'banner.clear'

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

        db.del(BannerState::KEY)
        db.del(BannerState::SCOPE_KEY)
        Onetime::Runtime.update_features(global_banner: nil, global_banner_scope: BannerState::DEFAULT_SCOPE)

        # One audit event per successful mutation. No detail: the fact of the clear
        # is the whole record (the cleared content is not re-logged here).
        Onetime::AdminAuditEvent.record(
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
