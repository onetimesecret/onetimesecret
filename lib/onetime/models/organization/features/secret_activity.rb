# lib/onetime/models/organization/features/secret_activity.rb
#
# frozen_string_literal: true

module Onetime::Organization::Features
  # Organization-scoped secret activity trail (#3633).
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
  # - Capped via Familia's max_length (newest kept; write + trim in one
  #   MULTI) to bound memory against mechanical hammering of anonymous read
  #   endpoints. The cap is configurable through
  #   features.secret_activity.max_events (applied at boot by .configure!).
  #   For long-horizon or compliance-grade retention, a durable export (e.g.
  #   via the jobs publisher) can consume the same fan-out point later.
  # - Collection itself is switchable: features.secret_activity.collect
  #   false pauses recording (GDPR data minimization — no events come to
  #   exist) while leaving existing events readable. This is the
  #   data-existence axis; UI/API exposure is the separate
  #   organizations.audit_logs_enabled axis (#3985).
  # - No TTL: organizations are permanent records; the cap is the bound.
  # - Members are plain Hashes; Familia JSON round-trips them (string keys
  #   on read). A `nonce` field keeps members unique when two identical
  #   events land in the same second.
  module SecretActivity
    Familia::Base.add_feature self, :secret_activity

    # Newest events retained when trimming the trail, absent configuration.
    DEFAULT_MAX_EVENTS = 10_000

    # Floor for the configurable cap: a paid audit trail that silently
    # retains almost nothing is worse than no trail at all.
    MIN_MAX_EVENTS = 100

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      # Familia validates max_length eagerly as a positive Integer (no lazy/
      # proc form) and this declaration fires at require time, before
      # Config.load — so the default is compiled in here and the configured
      # value is applied at boot via .configure!.
      base.sorted_set :secret_activity_events, max_length: DEFAULT_MAX_EVENTS

      base.include InstanceMethods
    end

    # Apply the configured retention cap (features.secret_activity.max_events)
    # to the trail. Clamps to MIN_MAX_EVENTS.
    #
    # BOOT-TIME ONLY (see ConfigureSecretActivity): per-org DataType instances
    # materialize lazily — Familia's initialize_relatives re-reads the stored
    # RelatedFieldDefinition's opts on an instance's first accessor call, so
    # mutating those opts here flows into every org materialized afterwards.
    # Any org whose accessor already ran has memoized a DataType with the old
    # cap and will NOT pick this up.
    #
    # @param max_events [Integer] desired cap (newest events retained).
    # @return [Integer] the applied (clamped) cap.
    def self.configure!(max_events)
      max = [Integer(max_events), MIN_MAX_EVENTS].max

      definition                   = Onetime::Organization.related_fields[:secret_activity_events]
      definition.opts[:max_length] = max

      max
    end

    module InstanceMethods
      # Append a secret activity event to the organization's trail.
      #
      # @param kind [String, Symbol] what happened. The receipt fan-out
      #   emits: 'created', 'status_get' / 'secret_get' (a third party
      #   fetched the status/secret link), 'previewed' (the creator opened
      #   their own secret link — the creator-facing "preview" event),
      #   'creator_status_get' (the creator checked their own secret's
      #   status), 'receipt_viewed' (the creator's receipt/metadata page was
      #   loaded — distinct from opening the secret link itself), 'revealed',
      #   'burned', 'expired', 'orphaned'.
      # @param at [Numeric] event time as epoch seconds; defaults to now.
      # @param attrs [Hash] additional context (receipt/secret shortids,
      #   actor when known). Keep values short and non-sensitive: never
      #   include secret content, full identifiers, or passphrases.
      # @return [Hash, nil] the recorded event, or nil when kind is blank
      #   or collection is paused.
      def record_secret_activity_event(kind, at: Familia.now, **attrs)
        return if kind.to_s.empty?
        # Default-true contract: only an explicit false pauses collection —
        # a missing key (older config file) must still record. Compare on
        # the string form so a hand-edited config that yields 'false'
        # (quoted/ERB-stringified) still disables the flag.
        return if OT.conf.dig('features', 'secret_activity', 'collect').to_s == 'false'

        event = {
          'kind' => kind.to_s,
          'at' => at.to_f,
          'nonce' => SecureRandom.hex(4),
        }.merge(attrs.transform_keys(&:to_s))

        # max_length on the sorted set trims atomically with the write.
        secret_activity_events.add(event, at.to_f)

        event
      end

      # @return [Integer] number of retained secret activity events
      #   (saturates at the configured max_events cap).
      def secret_activity_event_count
        secret_activity_events.element_count
      end

      # A page of secret activity events, newest first.
      #
      # @param offset [Integer] events to skip from the newest end.
      # @param limit [Integer] maximum events to return.
      # @return [Array<Hash>] events (string keys) newest-first; each
      #   includes its 'kind', 'at' and any recorded context.
      def secret_activity_events_page(offset: 0, limit: 50)
        offset = [offset.to_i, 0].max
        limit  = limit.to_i.clamp(1, 200)

        secret_activity_events.revrange(offset, offset + limit - 1)
      end
    end
  end
end
