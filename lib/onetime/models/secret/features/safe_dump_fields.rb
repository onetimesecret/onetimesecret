# lib/onetime/models/secret/features/safe_dump_fields.rb
#
# frozen_string_literal: true

# =============================================================================
# STATE TERMINOLOGY MIGRATION REFERENCE (Secret Model)
# =============================================================================
# See receipt/features/safe_dump_fields.rb for full migration documentation.
#
# LEGACY → NEW STATE VALUES:
#   'viewed'   → 'previewed'  (secret link accessed, confirmation shown)
#   'received' → 'revealed'   (secret content decrypted/consumed)
#
# MIGRATION SCRIPT REQUIREMENTS:
#   For each secret in Redis:
#     1. If state='viewed', set state='previewed'
#     2. If state='received', set state='revealed'
# =============================================================================

module Onetime::Secret::Features
  module SafeDumpFields
    Onetime::Secret.add_feature self, :safe_dump_fields

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
      base.safe_dump_field :shortid, ->(obj) { obj.shortid }
      base.safe_dump_field :state

      # Coerce numeric fields to Integer at this read boundary so the payload
      # always satisfies the strict z.number() V3 contract. Familia v2 storage
      # is type-preserving, not type-enforcing, so a value written as a Ruby
      # String anywhere upstream (unconverted params, console writes, raw HSET)
      # hydrates back as a String and would otherwise be rejected — the
      # recipient sees "no longer available" for a secret nobody consumed
      # (#3424). lifespan is an integer-second duration, so to_i is lossless.
      # We do NOT emit nil/0 sentinels: a real secret always has a lifespan, and
      # the contract enforces that invariant at read time. The write-time
      # guarantee lives in Receipt.spawn_pair and config normalization (#3299);
      # this cast additionally neutralizes already-poisoned records.
      # (created / updated stay to_f below — they are float epoch seconds that
      # double as sorted-set scores, so sub-second precision must be preserved.)
      # A read-only detector for poisoned records lives in
      # scripts/diagnostics/detect_string_typed_numerics.rb.
      # Mechanism tests: try/unit/models/secret_numeric_field_types_try.rb
      base.safe_dump_field :lifespan, ->(m) { m.lifespan.to_i }

      # @deprecated: legacy *_ttl field, to be removed in v0.26. Redundant with
      # lifespan and can be derived in the v1 and v2 logic classes.
      base.safe_dump_field :secret_ttl, ->(m) { m.lifespan.to_i }

      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
      base.safe_dump_field :verification, ->(m) { m.verification? }
      base.safe_dump_field :created, ->(m) { m.created.to_f }
      base.safe_dump_field :updated, ->(m) { m.updated.to_f }

      # State boolean fields - canonical names
      base.safe_dump_field :is_previewed, ->(m) { m.state?(:previewed) }
      base.safe_dump_field :is_revealed, ->(m) { m.state?(:revealed) }

      # BACKWARD COMPAT: Returns true if previewed OR legacy viewed
      base.safe_dump_field :is_viewed, ->(m) { m.state?(:previewed) || m.state?(:viewed) }
      # BACKWARD COMPAT: Returns true if revealed OR legacy received
      base.safe_dump_field :is_received, ->(m) { m.state?(:revealed) || m.state?(:received) }
    end
  end
end
