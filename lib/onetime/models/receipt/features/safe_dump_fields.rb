# lib/onetime/models/receipt/features/safe_dump_fields.rb
#
# frozen_string_literal: true

# =============================================================================
# STATE TERMINOLOGY MIGRATION REFERENCE
# =============================================================================
# This section documents the field mappings for upgrading existing installations.
#
# LEGACY → NEW FIELD MAPPINGS:
#   State values:
#     'viewed'   → 'previewed'  (secret link accessed, confirmation shown)
#     'received' → 'revealed'   (secret content decrypted/consumed)
#
#   Timestamp fields:
#     viewed    → previewed  (when link was first accessed)
#     received  → revealed   (when secret was actually revealed)
#
#   Boolean fields:
#     is_viewed   → is_previewed  (has the link been accessed?)
#     is_received → is_revealed   (has the secret been revealed?)
#
# API BACKWARD COMPATIBILITY:
#   safe_dump returns BOTH old and new field names:
#     - `viewed` field: falls back to `previewed` if `viewed` is nil
#     - `received` field: falls back to `revealed` if `revealed` is nil
#     - `is_viewed`: true if state is 'previewed' OR legacy 'viewed'
#     - `is_received`: true if state is 'revealed' OR legacy 'received'
#
# MIGRATION SCRIPT REQUIREMENTS:
#   For each receipt in Redis:
#     1. If state='viewed', set state='previewed'
#     2. If state='received', set state='revealed'
#     3. Copy `viewed` → `previewed` (if `previewed` is nil)
#     4. Copy `received` → `revealed` (if `revealed` is nil)
#   Legacy fields can be retained for rollback safety.
# =============================================================================

module Onetime::Receipt::Features
  module SafeDumpFields
    # Register our custom SafeDump feature with a unique
    Onetime::Receipt.add_feature self, :safe_dump_fields

    def self.included(base)
      # Lambda to handle counter fields that may be nil/empty - returns '0'
      # if empty, otherwise the string value

      # Enable the Familia SafeDump feature
      base.feature :safe_dump

      # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
      # with hot reloading in dev mode will not work. You will need to restart the
      # server to see the changes.
      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :key, ->(obj) { obj.identifier }
      # custid / owner_id are creator identifiers. Withhold them for
      # guest-submitted (incoming) provenance so the unauthenticated batch
      # endpoint (V3::Logic::Secrets::ShowMultipleReceipts serializes via
      # safe_dump and never runs a logic-layer gate) cannot leak the creator's
      # customer id to anonymous callers. Same provenance gate as
      # secret_identifier below (Receipt#shows_share_link? — false for
      # 'incoming'). Incoming receipts store custid='anon' already; standard /
      # owner-path receipts are unchanged. The frontend contract keeps both
      # fields nullish (src/schemas/contracts/receipt.ts custid/owner_id), so
      # returning nil is shape-preserving.
      base.safe_dump_field :custid, ->(m) { m.shows_share_link? ? m.custid : nil }
      base.safe_dump_field :owner_id, ->(m) { m.shows_share_link? ? m.owner_id : nil }
      base.safe_dump_field :state
      base.safe_dump_field :secret_shortid,
        ->(m) {
                val = m.secret_shortid.to_s
                val.empty? ? m.secret_identifier.to_s.slice(0, 8) : val
        }
      # secret_identifier is the share-link bearer key. Withhold it for
      # provenance that must not expose the link (incoming secrets). This gate
      # is load-bearing for the unauthenticated batch endpoint
      # (V3::Logic::Secrets::ShowMultipleReceipts serializes via safe_dump and
      # never runs the logic-layer gate). See Receipt#shows_share_link?.
      base.safe_dump_field :secret_identifier, ->(m) { m.shows_share_link? ? m.secret_identifier : nil }

      # Coerce numeric fields to Integer at the serialization boundary — see the
      # full note in secret/features/safe_dump_fields.rb (#3424/#3299). TTL and
      # lifespan are integer-second durations, so to_i is lossless. We emit a
      # plain number with no nil/-1 sentinel: a real receipt always has a
      # lifespan, the write-time guarantee lives in Receipt.spawn_pair, and the
      # strict z.number() V3 contract enforces the invariant at read time.
      # created/updated stay to_f, NOT to_i, to preserve the sub-second
      # precision that matters when these values are used as sorted-set scores.
      # Detector: scripts/diagnostics/detect_string_typed_numerics.rb
      base.safe_dump_field :secret_ttl, ->(m) { m.secret_ttl.to_i }
      base.safe_dump_field :metadata_ttl, ->(m) { m.lifespan.to_i }
      base.safe_dump_field :receipt_ttl, ->(m) { m.lifespan.to_i }
      base.safe_dump_field :lifespan, ->(m) { m.lifespan.to_i }
      base.safe_dump_field :share_domain
      base.safe_dump_field :created, ->(m) { m.created.to_f }
      base.safe_dump_field :updated, ->(m) { m.updated.to_f }
      # Coerce to Integer epoch seconds (or nil when unset) — see the note on
      # :previewed below; emitted raw and uncovered by the #3434/#3477 casts (#3424).
      base.safe_dump_field :shared, ->(m) { m.shared.to_i > 0 ? m.shared.to_i : nil }
      # Obscure recipient emails at serialization time so the raw address
      # never reaches the frontend, while the underlying record keeps the
      # clean value. obscure_email is a no-op when the value isn't an email
      # (e.g. already-obscured legacy data, or non-email free text), so this
      # is safe to apply unconditionally.
      base.safe_dump_field :recipients, ->(m) { OT::Utils.obscure_email(m.recipients.to_s) }
      base.safe_dump_field :recipient_name
      base.safe_dump_field :memo
      base.safe_dump_field :shortid, ->(m) { m.identifier.slice(0, 8) }
      base.safe_dump_field :show_recipients, ->(m) { !m.recipients.to_s.empty? }

      # New canonical timestamp fields. Coerce to Integer epoch seconds (or nil
      # when unset) at the boundary — these are emitted raw and the #3434/#3477
      # casts never covered them, so a value ever written as a String (legacy /
      # console / raw HSET) or an empty string would trip the strict
      # z.number().nullish() V3 transform and null the whole receipt (#3424).
      # to_i is a no-op for the healthy Familia.now.to_i values already stored.
      #
      # previewed is telemetry-derived (effective_previewed_at) to stay
      # coherent with is_previewed (#3633): the 'previewed' lifecycle state is
      # retired, so a fresh receipt never stamps the previewed field. When it
      # is unset, it falls back to the earliest access-timeline timestamp — the
      # moment the secret link was first fetched — so a consumer never sees
      # is_previewed=true paired with previewed=null. Legacy receipts with a
      # stored previewed timestamp keep it.
      base.safe_dump_field :previewed, ->(m) { m.effective_previewed_at }
      base.safe_dump_field :revealed, ->(m) { m.revealed.to_i > 0 ? m.revealed.to_i : nil }

      # New canonical boolean fields.
      #
      # is_previewed reflects access TELEMETRY, not lifecycle state (#3633):
      # a receipt no longer advances to a 'previewed' state when its page is
      # viewed. It is true when the secret link has been accessed at least
      # once (the append-only access timeline is non-empty), which is the
      # signal every consumer — the receipt page's post-creation banner and
      # the recent-secrets dashboard status — actually wants. The legacy
      # state?(:previewed)/state?(:viewed) terms are retained so receipts
      # written before the telemetry existed still report correctly. (One
      # ZCARD per dump; receipt lists are small, so this is not a hot path.)
      base.safe_dump_field :is_previewed,
        ->(m) { m.state?(:previewed) || m.state?(:viewed) || m.access_count.to_i.positive? }

      # BACKWARD COMPAT: Returns previewed timestamp for legacy clients. Falls
      # back to the telemetry-derived previewed value (stored timestamp, else
      # first access) when the legacy viewed field is unset — see :previewed.
      base.safe_dump_field :viewed,
        ->(m) { m.viewed.to_s.empty? ? m.effective_previewed_at : m.viewed }
      # BACKWARD COMPAT: Returns revealed timestamp for legacy clients
      # Falls back to revealed if received is nil (new data)
      base.safe_dump_field :received, ->(m) { m.received.to_s.empty? ? m.revealed : m.received }
      # Coerce to Integer epoch seconds (or nil when unset) — see :previewed note (#3424).
      base.safe_dump_field :burned, ->(m) { m.burned.to_i > 0 ? m.burned.to_i : nil }

      # BACKWARD COMPAT: legacy alias of is_previewed (telemetry-derived, #3633).
      base.safe_dump_field :is_viewed,
        ->(m) { m.state?(:previewed) || m.state?(:viewed) || m.access_count.to_i.positive? }
      # BACKWARD COMPAT: Returns true if revealed OR legacy received
      base.safe_dump_field :is_received, ->(m) { m.state?(:revealed) || m.state?(:received) }
      base.safe_dump_field :is_revealed, ->(m) { m.state?(:revealed) || m.state?(:received) }
      base.safe_dump_field :is_burned, ->(m) { m.state?(:burned) }
      base.safe_dump_field :is_expired, ->(m) { m.state?(:expired) }
      base.safe_dump_field :is_orphaned, ->(m) { m.state?(:orphaned) }
      base.safe_dump_field :is_destroyed,
        ->(m) {
          m.state?(:revealed) || m.state?(:received) ||
            m.state?(:burned) || m.state?(:expired) || m.state?(:orphaned)
        }
      # We use the hash syntax here since `:truncated?` is not a valid symbol.
      # base.safe_dump_field :is_truncated, ->(m) { m.truncated? }
      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
      base.safe_dump_field :kind
      base.safe_dump_field :source
    end
  end
end
