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
      base.safe_dump_field :secret_ttl, ->(m) { m.lifespan }
      base.safe_dump_field :lifespan
      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
      base.safe_dump_field :verification, ->(m) { m.verification? }
      base.safe_dump_field :created
      base.safe_dump_field :updated

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
